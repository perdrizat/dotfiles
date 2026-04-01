#!/bin/bash

# --- 1. HANDLE INPUT ---
if read -t 0.1 -r first_line; then
    INPUT_JSON="$first_line$(cat)"
else
    INPUT_JSON="{}"
fi

CRED_FILE="$HOME/.claude/.credentials.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
CACHE_FILE="/tmp/claude_usage_cache.json"
CACHE_TTL=60

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

if [[ -f "$CACHE_FILE" ]] && [[ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE"))) -lt $CACHE_TTL ]]; then
    data=$(cat "$CACHE_FILE")
else
    data=$(curl -s -H "Authorization: Bearer $TOKEN" \
         -H "anthropic-beta: oauth-2025-04-20" \
         https://api.anthropic.com/api/oauth/usage)
    echo "$data" > "$CACHE_FILE"
fi

# --- 5. PARSE API STATS ---
curr_util=$(echo "$data" | jq -r '.five_hour.utilization // 0')
week_util=$(echo "$data" | jq -r '.seven_day.utilization // 0')

curr_pct=$(echo "$curr_util" | xargs printf "%.0f")
week_pct=$(echo "$week_util" | xargs printf "%.0f")

reset_curr=$(date -d "$(echo "$data" | jq -r '.five_hour.resets_at // now')" +"%I:%M%P")
reset_week=$(date -d "$(echo "$data" | jq -r '.seven_day.resets_at // now')" +"%b %d, %I:%M%P")

extra_enabled=$(echo "$data" | jq -r '.extra_usage.is_enabled // false')
if [ "$extra_enabled" = "true" ]; then
    used_ext=$(echo "$data" | jq -r '.extra_usage.used_credits // 0')
    limit_ext=$(echo "$data" | jq -r '.extra_usage.monthly_limit // 0')
    extra_display=$(printf "\$%.2f/\$%.2f" "$used_ext" "$limit_ext")
else
    extra_display="disabled"
fi

# --- 6. RENDER ---
draw_dots() {
    local pct=$1
    local filled=$(( pct / 10 ))
    local color; color=$(pct_color "$pct")
    local bar="${color}"
    for ((i=0; i<filled; i++)); do bar+="o"; done
    bar+="${GRAY}"
    for ((i=filled; i<10; i++)); do bar+="o"; done
    bar+=" ${color}${pct}%${RESET}"
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
extra_color=$(active_color "$extra_enabled")
printf "${GRAY}current:${RESET} %s${GRAY}, resets %s${RESET} ${GRAY}|${RESET} ${GRAY}weekly:${RESET} %s${GRAY}, resets %s${RESET} ${GRAY}|${RESET} ${GRAY}Extra:${RESET} ${extra_color}%s${RESET}\n" \
    "$(draw_dots "$curr_pct")" "$reset_curr" "$(draw_dots "$week_pct")" "$reset_week" "$extra_display"
