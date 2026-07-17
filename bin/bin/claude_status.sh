#!/bin/bash

# --- 1. HANDLE INPUT ---
if read -t 0.1 -r first_line; then
    INPUT_JSON="$first_line$(cat)"
else
    INPUT_JSON="{}"
fi

CRED_FILE="$HOME/.claude/.credentials.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
CACHE_FILE="/tmp/claude_usage_cache.json"   # holds the last *successful* usage payload
STAMP_FILE="/tmp/claude_usage_last_fetch"   # mtime = last fetch attempt; throttles retries
CACHE_TTL=300

# --- 2. PARSE SESSION STATE ---
MODEL_NAME=$(echo "$INPUT_JSON" | jq -r '.model.display_name // "?"')
CONTEXT_RAW=$(echo "$INPUT_JSON" | jq -r '.context_window.context_window_size // 200000')
CONTEXT_USED_PCT=$(echo "$INPUT_JSON" | jq -r '.context_window.used_percentage // 0')

if [ "$CONTEXT_RAW" -ge 1000000 ]; then
    CONTEXT_DISPLAY=$(printf "%.1fm" "$(echo "scale=1; $CONTEXT_RAW / 1000000" | bc -l)")
else
    CONTEXT_DISPLAY="$((CONTEXT_RAW / 1000))k"
fi

# Derive used tokens from context percentage
used_ctx_tokens=$(echo "($CONTEXT_RAW * $CONTEXT_USED_PCT) / 100" | bc -l | xargs printf "%.0f")
used_ctx_k=$(( used_ctx_tokens / 1000 ))

EFFORT=$(jq -r '.effortLevel // "default"' "$SETTINGS_FILE" 2>/dev/null)
THINKING=$(jq -r '.alwaysThinkingEnabled // false' "$SETTINGS_FILE" 2>/dev/null)
[[ "$THINKING" == "true" ]] && THINK_LABEL="On" || THINK_LABEL="Off"

# --- 3. COLORS ---
BLUE='\e[38;5;33m'
CYAN='\e[38;5;39m'
GREEN='\e[38;5;71m'
AMBER='\e[38;5;208m'
RED='\e[38;5;196m'
GRAY='\e[38;5;242m'
RESET='\e[0m'

pct_color() {
    local pct=$1
    if [ "$pct" -le 50 ]; then echo -ne "$GREEN"
    elif [ "$pct" -le 80 ]; then echo -ne "$AMBER"
    else echo -ne "$RED"
    fi
}

active_color() {
    local val="${1,,}"
    case "$val" in
        on|high|max|true) echo -ne "$AMBER" ;;
        *) echo -ne "$GRAY" ;;
    esac
}

# --- 4. FETCH API DATA ---
TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE")
[[ -z "$TOKEN" ]] && echo "Claude Offline" && exit 0

# Query the usage endpoint and cache it. Overwrite only on a real usage payload
# (has .five_hour.utilization); a 429 error body lacks it, so the previous good
# cache survives the rate limit.
fetch_and_cache() {
    local resp
    resp=$(curl -s -H "Authorization: Bearer $TOKEN" \
         -H "anthropic-beta: oauth-2025-04-20" \
         https://api.anthropic.com/api/oauth/usage)
    if echo "$resp" | jq -e '.five_hour.utilization != null' >/dev/null 2>&1; then
        echo "$resp" > "$CACHE_FILE"
    fi
}

# The usage endpoint rate-limits hard (HTTP 429) when polled too often — e.g.
# several tmux panes each rendering this line — so warm refreshes are throttled
# to one shared fetch per CACHE_TTL, stamped up front so concurrent panes don't
# all fetch. But when the cache file is *missing* (cold /tmp, or a stale stamp
# left by a failed attempt) the throttle must not gate the fetch, or the bars
# stay unknown until the stamp ages out. So on a cold cache we reverse the
# order: query first, stamp second, ignoring the throttle entirely.
now=$(date +%s)
last_attempt=0
[[ -f "$STAMP_FILE" ]] && last_attempt=$(stat -c %Y "$STAMP_FILE")
if [[ ! -f "$CACHE_FILE" ]]; then
    fetch_and_cache
    touch "$STAMP_FILE"
elif (( now - last_attempt >= CACHE_TTL )); then
    touch "$STAMP_FILE"
    fetch_and_cache
fi

# No cached payload yet (fetch failed / offline) → render unknown, not 0%.
if [[ -s "$CACHE_FILE" ]]; then
    data=$(cat "$CACHE_FILE")
    have_usage=1
else
    data='{}'
    have_usage=0
fi

# --- 5. PARSE API STATS ---
# Round to nearest 10 minutes: (timestamp + 300) / 600 * 600
round_to_10min() {
    local ts=$1
    local fmt=$2
    local rounded=$(( (ts + 300) / 600 * 600 ))
    date -d @"$rounded" +"$fmt"
}

# Only parse when we actually have a cached payload. With data='{}' the
# `resets_at // now` fallback yields jq's float epoch, which `date -d` rejects.
if (( have_usage )); then
    curr_util=$(echo "$data" | jq -r '.five_hour.utilization // 0')
    week_util=$(echo "$data" | jq -r '.seven_day.utilization // 0')
    curr_pct=$(echo "$curr_util" | xargs printf "%.0f")
    week_pct=$(echo "$week_util" | xargs printf "%.0f")

    reset_curr=$(round_to_10min "$(date -d "$(echo "$data" | jq -r '.five_hour.resets_at // now')" +%s)" "%H:%M")
    reset_week=$(round_to_10min "$(date -d "$(echo "$data" | jq -r '.seven_day.resets_at // now')" +%s)" "%m/%d %H:%M")

    extra_enabled=$(echo "$data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        used_cents=$(echo "$data" | jq -r '.extra_usage.used_credits // 0')
        limit_cents=$(echo "$data" | jq -r '.extra_usage.monthly_limit // 0')
        used_dollars=$(echo "scale=2; $used_cents / 100" | bc -l)
        limit_dollars=$(echo "$limit_cents / 100" | bc)
        extra_display=$(printf "\$%s/\$%s" "$used_dollars" "$limit_dollars")
    else
        extra_display="disabled"
    fi
fi

# --- 6. RENDER ---
draw_dots() {
    local pct=$1
    local filled=$(( pct / 10 ))
    local color; color=$(pct_color "$pct")
    local bar="${color}${pct}% "
    for ((i=0; i<filled; i++)); do bar+="o"; done
    bar+="${GRAY}"
    for ((i=filled; i<10; i++)); do bar+="o"; done
    bar+="${RESET}"
    echo -ne "$bar"
}

# Line 1: Session-local values
ctx_pct_int=$(printf "%.0f" "$CONTEXT_USED_PCT")
ctx_color=$(pct_color "$ctx_pct_int")
think_color=$(active_color "$THINK_LABEL")
effort_color=$(active_color "$EFFORT")
printf "${BLUE}%s${RESET} ${GRAY}with${RESET} ${CYAN}%sk/%s${RESET} ${GRAY}context:${RESET} ${ctx_color}%d%% used${RESET} ${GRAY}|${RESET} ${GRAY}Thinking:${RESET} ${think_color}%s${RESET} ${GRAY}|${RESET} ${GRAY}Effort:${RESET} ${effort_color}%s${RESET}\n" \
    "$MODEL_NAME" "$used_ctx_k" "$CONTEXT_DISPLAY" "$ctx_pct_int" "$THINK_LABEL" "$EFFORT"

# Line 2: Global API status
if (( have_usage )); then
    extra_color=$(active_color "$extra_enabled")
    printf "${GRAY}5h:${RESET} %s ${GRAY}till %s${RESET} ${GRAY}|${RESET} ${GRAY}7d:${RESET} %s ${GRAY}till %s${RESET} ${GRAY}|${RESET} ${GRAY}Extra:${RESET} ${extra_color}%s${RESET}\n" \
        "$(draw_dots "$curr_pct")" "$reset_curr" "$(draw_dots "$week_pct")" "$reset_week" "$extra_display"
else
    printf "${GRAY}5h:${RESET} unknown ${GRAY}|${RESET} ${GRAY}7d:${RESET} unknown ${GRAY}|${RESET} ${GRAY}Extra:${RESET} unknown\n"
fi
