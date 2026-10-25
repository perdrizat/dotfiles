#!/bin/bash

# --- 1. HANDLE INPUT ---
if read -t 0.1 -r first_line || [ -n "$first_line" ]; then
    # We must temporarily disable set -e if we expect cat to fail without EOF
    INPUT_JSON="$first_line$(cat 2>/dev/null)"
else
    INPUT_JSON="{}"
fi

AGY_CACHE="$HOME/.agy.json"
CACHE_TTL=120

# --- 2. UPDATE CACHE ---
if [[ ! -f "$AGY_CACHE" ]] || [[ $(($(date +%s) - $(stat -c %Y "$AGY_CACHE" 2>/dev/null || echo 0))) -ge $CACHE_TTL ]]; then
    # Fork to background and properly detach so it isn't killed when the script exits
    (
        PIDS=$(pgrep -x agy | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$PIDS" ]]; then
            export PATH=$PATH:/usr/sbin:/usr/bin:/bin
            PORTS=$(lsof -nP -iTCP -sTCP:LISTEN -a -p "$PIDS" 2>/dev/null | awk -F':' '/LISTEN/ {print $2}' | awk '{print $1}')
            for PORT in $PORTS; do
                RESPONSE=$(curl -sk -X POST -H "Content-Type: application/json" -H "Connect-Protocol-Version: 1" -d '{}' "https://127.0.0.1:$PORT/exa.language_server_pb.LanguageServerService/GetUserStatus" 2>/dev/null)
                if echo "$RESPONSE" | jq -e '.userStatus' >/dev/null 2>&1; then
                    # tmp+mv is deliberate: atomic publish. Concurrent status-line runs
                    # read this cache and must never see a torn file; ~/.agy.json is owned
                    # by this script and never hard/symlinked, so inode replacement is safe.
                    echo "$RESPONSE" > "$AGY_CACHE.tmp"
                    mv "$AGY_CACHE.tmp" "$AGY_CACHE"
                    break
                fi
            done
        fi
    ) </dev/null >/dev/null 2>&1 &
    disown
fi

# --- 3. PARSE SESSION STATE ---
MODEL_NAME=$(echo "$INPUT_JSON" | jq -r '.model.display_name // "?"')
CONTEXT_RAW=$(echo "$INPUT_JSON" | jq -r '.context_window.context_window_size // 0')
CONTEXT_USED_PCT=$(echo "$INPUT_JSON" | jq -r '.context_window.used_percentage // 0')
CACHE_INPUT_TOKENS=$(echo "$INPUT_JSON" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
AGENT_STATE=$(echo "$INPUT_JSON" | jq -r '.agent_state // "unknown"')
SANDBOX_ENABLED=$(echo "$INPUT_JSON" | jq -r '.sandbox.enabled // false')

if [[ "$CONTEXT_USED_PCT" == "0" && "$MODEL_NAME" == "?" ]]; then
    ctx_pct_int="0"
else
    ctx_pct_int=$(printf "%.0f" "$CONTEXT_USED_PCT")
fi

# Context formatting
if [ "$CONTEXT_RAW" -ge 1000000 ]; then
    CONTEXT_DISPLAY=$(printf "%.1fm" "$(echo "scale=1; $CONTEXT_RAW / 1000000" | bc -l)")
elif [ "$CONTEXT_RAW" -gt 0 ]; then
    CONTEXT_DISPLAY="$((CONTEXT_RAW / 1000))k"
else
    CONTEXT_DISPLAY="?"
fi

# Calculate used tokens
if [ "$CONTEXT_RAW" -gt 0 ]; then
    used_ctx_tokens=$(echo "($CONTEXT_RAW * $CONTEXT_USED_PCT) / 100" | bc -l | xargs printf "%.0f")
    used_ctx_k=$(( used_ctx_tokens / 1000 ))
else
    used_ctx_k="0"
fi

# Calculate cache size display
cache_k=$(( CACHE_INPUT_TOKENS / 1000 ))

# Sandbox mapping
[[ "$SANDBOX_ENABLED" == "true" ]] && SANDBOX_LABEL="On" || SANDBOX_LABEL="Off"

# --- 4. FETCH QUOTA & CREDITS ---
# Newer agy versions pass bucketed quotas directly in the stdin JSON under .quota
# (gemini-argon-wtu-weekly, gemini-5h, gemini-weekly, 3p-5h, 3p-weekly), reporting
# remaining_fraction (what's left). Standard Gemini and 3P models have both a 5h
# and a 7d (weekly) window; Argon only has a 7d window.
PROMPT_CREDITS="?"
FLOW_CREDITS="?"

format_reset() {
    local utc=$1
    local fmt=$2
    [[ -z "$utc" || "$utc" == "null" ]] && { echo "?"; return; }
    local ts
    ts=$(date -d "$utc" +%s 2>/dev/null || echo 0)
    (( ts > 0 )) && date -d @"$ts" +"$fmt" 2>/dev/null || echo "?"
}

parse_bucket_pct() {
    local frac=$1
    if [[ -n "$frac" && "$frac" != "null" ]]; then
        echo "$frac * 100" | bc -l | xargs printf "%.0f"
    else
        echo "?"
    fi
}

model_lc="${MODEL_NAME,,}"
has_5h=0
has_7d=0
QUOTA_5H_PCT="?"
RESET_5H="?"
QUOTA_7D_PCT="?"
RESET_7D="?"

if [[ "$model_lc" == *argon* ]]; then
    has_7d=1
    frac_7d=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-argon-wtu-weekly"].remaining_fraction // empty' 2>/dev/null)
    utc_7d=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-argon-wtu-weekly"].reset_time // empty' 2>/dev/null)
    QUOTA_7D_PCT=$(parse_bucket_pct "$frac_7d")
    RESET_7D=$(format_reset "$utc_7d" "%m/%d %H:%M")
elif [[ "$model_lc" == *gemini* ]]; then
    has_5h=1
    has_7d=1
    frac_5h=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-5h"].remaining_fraction // empty' 2>/dev/null)
    utc_5h=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-5h"].reset_time // empty' 2>/dev/null)
    frac_7d=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-weekly"].remaining_fraction // empty' 2>/dev/null)
    utc_7d=$(echo "$INPUT_JSON" | jq -r '.quota["gemini-weekly"].reset_time // empty' 2>/dev/null)
    QUOTA_5H_PCT=$(parse_bucket_pct "$frac_5h")
    RESET_5H=$(format_reset "$utc_5h" "%H:%M")
    QUOTA_7D_PCT=$(parse_bucket_pct "$frac_7d")
    RESET_7D=$(format_reset "$utc_7d" "%m/%d %H:%M")
elif [[ "$model_lc" != "?" ]]; then
    has_5h=1
    has_7d=1
    frac_5h=$(echo "$INPUT_JSON" | jq -r '.quota["3p-5h"].remaining_fraction // empty' 2>/dev/null)
    utc_5h=$(echo "$INPUT_JSON" | jq -r '.quota["3p-5h"].reset_time // empty' 2>/dev/null)
    frac_7d=$(echo "$INPUT_JSON" | jq -r '.quota["3p-weekly"].remaining_fraction // empty' 2>/dev/null)
    utc_7d=$(echo "$INPUT_JSON" | jq -r '.quota["3p-weekly"].reset_time // empty' 2>/dev/null)
    QUOTA_5H_PCT=$(parse_bucket_pct "$frac_5h")
    RESET_5H=$(format_reset "$utc_5h" "%H:%M")
    QUOTA_7D_PCT=$(parse_bucket_pct "$frac_7d")
    RESET_7D=$(format_reset "$utc_7d" "%m/%d %H:%M")
fi

if [[ -f "$AGY_CACHE" ]]; then
    # Fallback to cached GetUserStatus if stdin had no quota for a 5h model
    if (( has_5h )) && [[ "$QUOTA_5H_PCT" == "?" && "$MODEL_NAME" != "?" ]]; then
        frac_5h=$(jq -r --arg model "$MODEL_NAME" 'first(.userStatus.cascadeModelConfigData.clientModelConfigs[] | select(.label == $model) | .quotaInfo.remainingFraction // empty)' "$AGY_CACHE" 2>/dev/null)
        utc_5h=$(jq -r --arg model "$MODEL_NAME" 'first(.userStatus.cascadeModelConfigData.clientModelConfigs[] | select(.label == $model) | .quotaInfo.resetTime // empty)' "$AGY_CACHE" 2>/dev/null)
        QUOTA_5H_PCT=$(parse_bucket_pct "$frac_5h")
        RESET_5H=$(format_reset "$utc_5h" "%H:%M")
    fi

    # Get global credits
    PROMPT_CREDITS=$(jq -r '.userStatus.planStatus.availablePromptCredits // "?"' "$AGY_CACHE" 2>/dev/null)
    FLOW_CREDITS=$(jq -r '.userStatus.planStatus.availableFlowCredits // "?"' "$AGY_CACHE" 2>/dev/null)
fi

# --- 5. COLORS ---
BLUE='\e[38;5;33m'
CYAN='\e[38;5;39m'
GREEN='\e[38;5;71m'
AMBER='\e[38;5;208m'
RED='\e[38;5;196m'
GRAY='\e[38;5;242m'
RESET='\e[0m'

pct_color() {
    local pct=$1
    if [[ "$pct" == "?" ]]; then echo -ne "$GRAY"; return; fi
    if [ "$pct" -le 50 ]; then echo -ne "$GREEN"
    elif [ "$pct" -le 80 ]; then echo -ne "$AMBER"
    else echo -ne "$RED"
    fi
}

quota_color() {
    local pct=$1
    if [[ "$pct" == "?" ]]; then echo -ne "$GRAY"; return; fi
    # For quota: lower is red, higher is green
    if [ "$pct" -ge 50 ]; then echo -ne "$GREEN"
    elif [ "$pct" -ge 20 ]; then echo -ne "$AMBER"
    else echo -ne "$RED"
    fi
}

active_color() {
    local val="${1,,}"
    case "$val" in
        on|high|max|true|generating|running_command) echo -ne "$AMBER" ;;
        idle|false|off) echo -ne "$GRAY" ;;
        *) echo -ne "$CYAN" ;;
    esac
}

draw_dots() {
    local pct=$1
    if [[ "$pct" == "?" ]]; then echo -ne "${GRAY}?% oooooooooo${RESET}"; return; fi
    local filled=$(( pct / 10 ))
    local color; color=$(quota_color "$pct")
    local bar="${color}${pct}% "
    for ((i=0; i<filled; i++)); do bar+="o"; done
    bar+="${GRAY}"
    for ((i=filled; i<10; i++)); do bar+="o"; done
    bar+="${RESET}"
    echo -ne "$bar"
}

# --- 6. RENDER ---
ctx_color=$(pct_color "$ctx_pct_int")
state_color=$(active_color "$AGENT_STATE")
sandbox_color=$(active_color "$SANDBOX_LABEL")

# Line 1: Session-local values
printf "${BLUE}%s${RESET} ${GRAY}with${RESET} ${CYAN}%sk/%s${RESET} ${GRAY}context:${RESET} ${ctx_color}%d%% used${RESET} ${GRAY}|${RESET} ${GRAY}Cache:${RESET} %sk ${GRAY}|${RESET} ${GRAY}State:${RESET} ${state_color}%s${RESET}\n" \
    "$MODEL_NAME" "$used_ctx_k" "$CONTEXT_DISPLAY" "$ctx_pct_int" "$cache_k" "$AGENT_STATE"

# Line 2: Global API status
if (( has_5h && has_7d )); then
    quota_segment=$(printf "${GRAY}5h left:${RESET} %s ${GRAY}till %s${RESET} ${GRAY}|${RESET} ${GRAY}7d left:${RESET} %s ${GRAY}till %s${RESET}" \
        "$(draw_dots "$QUOTA_5H_PCT")" "$RESET_5H" "$(draw_dots "$QUOTA_7D_PCT")" "$RESET_7D")
else
    quota_segment=$(printf "${GRAY}7d left:${RESET} %s ${GRAY}till %s${RESET}" \
        "$(draw_dots "$QUOTA_7D_PCT")" "$RESET_7D")
fi
printf "%s ${GRAY}|${RESET} ${GRAY}Credits:${RESET} %s prompts, %s flow ${GRAY}|${RESET} ${GRAY}Sandbox:${RESET} ${sandbox_color}%s${RESET}\n" \
    "$quota_segment" "$PROMPT_CREDITS" "$FLOW_CREDITS" "$SANDBOX_LABEL"
