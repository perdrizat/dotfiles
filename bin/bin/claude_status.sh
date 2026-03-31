#!/bin/bash

# --- 1. HANDLE INPUT ---
if read -t 0.1 -r first_line; then
    INPUT_JSON="$first_line$(cat)"
else
    INPUT_JSON="{}"
fi

CRED_FILE="$HOME/.claude/.credentials.json"
CACHE_FILE="/tmp/claude_usage_cache.json"
CACHE_TTL=60

# --- 2. PARSE SESSION STATE ---
MODEL_NAME=$(echo "$INPUT_JSON" | jq -r '.model.display_name // "Sonnet 3.5"')
CONTEXT_RAW=$(echo "$INPUT_JSON" | jq -r '.model.context_window // 200000')
IS_THINKING=$(echo "$INPUT_JSON" | jq -r '.thinking // false')
THINK_LABEL="Off"; [[ "$IS_THINKING" == "true" ]] && THINK_LABEL="On"

if [ "$CONTEXT_RAW" -ge 1000000 ]; then
    CONTEXT_DISPLAY=$(printf "%.1fm" "$(echo "scale=1; $CONTEXT_RAW / 1000000" | bc -l)")
else
    CONTEXT_DISPLAY="$((CONTEXT_RAW / 1000))k"
fi

# --- 3. COLORS ---
BLUE='\e[38;5;33m'
CYAN='\e[38;5;39m'
GREEN='\e[38;5;71m'
ORANGE='\e[38;5;208m'
GRAY='\e[38;5;242m'
RESET='\e[0m'

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

used_tokens=$(echo "($CONTEXT_RAW * $curr_util) / 100" | bc -l | xargs printf "%.0f")
used_k=$(( used_tokens / 1000 ))
curr_pct=$(echo "$curr_util" | xargs printf "%.0f")
week_pct=$(echo "$week_util" | xargs printf "%.0f")

reset_curr=$(date -d "$(echo "$data" | jq -r '.five_hour.resets_at // now')" +"%I:%M%P")
reset_week=$(date -d "$(echo "$data" | jq -r '.seven_day.resets_at // now')" +"%b %d, %I:%M%P")

extra_enabled=$(echo "$data" | jq -r '.extra_usage.is_enabled // false')
if [ "$extra_enabled" = "true" ]; then
    used_ext=$(echo "$data" | jq -r '.extra_usage.used_credits // 0')
    limit_ext=$(echo "$data" | jq -r '.extra_usage.monthly_limit // 0')
    extra_display="\$${used_ext}/\$${limit_ext}.00"
else
    extra_display="disabled"
fi

# --- 6. RENDER ---
draw_dots() {
    local pct=$1
    local filled=$(( pct / 10 ))
    local bar="${GREEN}"
    for ((i=0; i<filled; i++)); do bar+="o"; done
    bar+="${GRAY}"
    for ((i=filled; i<10; i++)); do bar+="o"; done
    bar+=" ${pct}%${RESET}"
    echo -ne "$bar"
}

# Line 1: Model + context | thinking | extra
printf "${BLUE}%s${RESET} ${GRAY}with${RESET} ${CYAN}%sk/%s${RESET} ${GRAY}context:${RESET} ${GREEN}%d%% used${RESET} ${GRAY}|${RESET} ${GRAY}Thinking:${RESET} ${ORANGE}%s${RESET} ${GRAY}|${RESET} ${GRAY}Extra:${RESET} ${GRAY}%s${RESET}\n" \
    "$MODEL_NAME" "$used_k" "$CONTEXT_DISPLAY" "$curr_pct" "$THINK_LABEL" "$extra_display"

# Line 2: Bars + resets
printf "${GRAY}current:${RESET} %s ${GRAY}resets %s${RESET} ${GRAY}|${RESET} ${GRAY}weekly:${RESET} %s ${GRAY}resets %s${RESET}\n" \
    "$(draw_dots "$curr_pct")" "$reset_curr" "$(draw_dots "$week_pct")" "$reset_week"
