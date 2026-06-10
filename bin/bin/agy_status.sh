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

# --- 4. FETCH QUOTA & CREDITS FROM CACHE ---
QUOTA_PCT="?"
RESET_TIME="?"
PROMPT_CREDITS="?"
FLOW_CREDITS="?"

if [[ -f "$AGY_CACHE" && "$MODEL_NAME" != "?" ]]; then
    # Get model-specific quota info
    remaining_fraction=$(jq -r --arg model "$MODEL_NAME" 'first(.userStatus.cascadeModelConfigData.clientModelConfigs[] | select(.label == $model) | .quotaInfo.remainingFraction // empty)' "$AGY_CACHE" 2>/dev/null)
    reset_utc=$(jq -r --arg model "$MODEL_NAME" 'first(.userStatus.cascadeModelConfigData.clientModelConfigs[] | select(.label == $model) | .quotaInfo.resetTime // empty)' "$AGY_CACHE" 2>/dev/null)
    
    if [[ -n "$remaining_fraction" && "$remaining_fraction" != "null" ]]; then
        QUOTA_PCT=$(echo "$remaining_fraction * 100" | bc -l | xargs printf "%.0f")
    fi
    if [[ -n "$reset_utc" && "$reset_utc" != "null" ]]; then
        # Convert UTC reset time to local time (HH:MM)
        RESET_TIME=$(date -d "$reset_utc" +"%H:%M" 2>/dev/null || echo "?")
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
printf "${GRAY}Quota left:${RESET} %s ${GRAY}till %s${RESET} ${GRAY}|${RESET} ${GRAY}Credits:${RESET} %s prompts, %s flow ${GRAY}|${RESET} ${GRAY}Sandbox:${RESET} ${sandbox_color}%s${RESET}\n" \
    "$(draw_dots "$QUOTA_PCT")" "$RESET_TIME" "$PROMPT_CREDITS" "$FLOW_CREDITS" "$SANDBOX_LABEL"
