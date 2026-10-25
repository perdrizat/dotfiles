#!/bin/bash

# --- 1. HANDLE INPUT ---
if read -t 0.1 -r first_line || [ -n "$first_line" ]; then
    # We must temporarily disable set -e if we expect cat to fail without EOF
    INPUT_JSON="$first_line$(cat 2>/dev/null)"
else
    INPUT_JSON="{}"
fi

# --- 2. PARSE SESSION STATE ---
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

# --- 3. PARSE QUOTA BUCKETS ---
# agy passes all 3 independent quota pools in the stdin JSON under .quota:
# - Argon:   gemini-argon-wtu-weekly (7d only on Pro plans)
# - Gemini:  gemini-5h, gemini-weekly
# - 3P:      3p-5h, 3p-weekly (Claude, GPT)

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

read -r argon_7d_f argon_7d_t gem_5h_f gem_5h_t gem_7d_f gem_7d_t tp_5h_f tp_5h_t tp_7d_f tp_7d_t < <(
    echo "$INPUT_JSON" | jq -r '[
        (.quota["gemini-argon-wtu-weekly"].remaining_fraction // "null"),
        (.quota["gemini-argon-wtu-weekly"].reset_time // "null"),
        (.quota["gemini-5h"].remaining_fraction // "null"),
        (.quota["gemini-5h"].reset_time // "null"),
        (.quota["gemini-weekly"].remaining_fraction // "null"),
        (.quota["gemini-weekly"].reset_time // "null"),
        (.quota["3p-5h"].remaining_fraction // "null"),
        (.quota["3p-5h"].reset_time // "null"),
        (.quota["3p-weekly"].remaining_fraction // "null"),
        (.quota["3p-weekly"].reset_time // "null")
    ] | @tsv' 2>/dev/null
)

ARGON_7D_PCT=$(parse_bucket_pct "$argon_7d_f")
ARGON_7D_RESET=$(format_reset "$argon_7d_t" "%m/%d %H:%M")

GEM_5H_PCT=$(parse_bucket_pct "$gem_5h_f")
GEM_5H_RESET=$(format_reset "$gem_5h_t" "%H:%M")
GEM_7D_PCT=$(parse_bucket_pct "$gem_7d_f")
GEM_7D_RESET=$(format_reset "$gem_7d_t" "%m/%d %H:%M")

TP_5H_PCT=$(parse_bucket_pct "$tp_5h_f")
TP_5H_RESET=$(format_reset "$tp_5h_t" "%H:%M")
TP_7D_PCT=$(parse_bucket_pct "$tp_7d_f")
TP_7D_RESET=$(format_reset "$tp_7d_t" "%m/%d %H:%M")

# --- 4. COLORS ---
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

fmt_pct() {
    local pct=$1
    local color; color=$(quota_color "$pct")
    echo -ne "${color}${pct}%${RESET}"
}

# --- 5. RENDER ---
ctx_color=$(pct_color "$ctx_pct_int")
state_color=$(active_color "$AGENT_STATE")
[[ "$SANDBOX_ENABLED" == "true" ]] && sandbox_color="$GREEN" || sandbox_color="$AMBER"

# Line 1: Session-local values
printf "${BLUE}%s${RESET} ${GRAY}with${RESET} ${CYAN}%sk/%s${RESET} ${GRAY}context:${RESET} ${ctx_color}%d%% used${RESET} ${GRAY}|${RESET} ${GRAY}Cache:${RESET} %sk ${GRAY}|${RESET} ${GRAY}State:${RESET} ${state_color}%s${RESET} ${GRAY}|${RESET} ${GRAY}Sandbox:${RESET} ${sandbox_color}%s${RESET}\n" \
    "$MODEL_NAME" "$used_ctx_k" "$CONTEXT_DISPLAY" "$ctx_pct_int" "$cache_k" "$AGENT_STATE" "$SANDBOX_LABEL"

# Line 2: Global API quota status (active model pool expanded with bar + reset times; inactive pools compact)
model_lc="${MODEL_NAME,,}"
if [[ "$model_lc" == *argon* || "$MODEL_NAME" == "?" ]]; then
    printf "${GRAY}Argon 7d:${RESET} %s ${GRAY}till %s${RESET} ${GRAY}|${RESET} ${GRAY}Gemini 5h/7d:${RESET} %s${GRAY}/${RESET}%s ${GRAY}|${RESET} ${GRAY}3P 5h/7d:${RESET} %s${GRAY}/${RESET}%s\n" \
        "$(draw_dots "$ARGON_7D_PCT")" "$ARGON_7D_RESET" \
        "$(fmt_pct "$GEM_5H_PCT")" "$(fmt_pct "$GEM_7D_PCT")" \
        "$(fmt_pct "$TP_5H_PCT")" "$(fmt_pct "$TP_7D_PCT")"
elif [[ "$model_lc" == *gemini* ]]; then
    printf "${GRAY}Gemini 5h:${RESET} %s ${GRAY}till %s · 7d:${RESET} %s ${GRAY}(%s)${RESET} ${GRAY}|${RESET} ${GRAY}Argon 7d:${RESET} %s ${GRAY}|${RESET} ${GRAY}3P:${RESET} %s${GRAY}/${RESET}%s\n" \
        "$(draw_dots "$GEM_5H_PCT")" "$GEM_5H_RESET" "$(fmt_pct "$GEM_7D_PCT")" "$GEM_7D_RESET" \
        "$(fmt_pct "$ARGON_7D_PCT")" \
        "$(fmt_pct "$TP_5H_PCT")" "$(fmt_pct "$TP_7D_PCT")"
else
    printf "${GRAY}3P 5h:${RESET} %s ${GRAY}till %s · 7d:${RESET} %s ${GRAY}(%s)${RESET} ${GRAY}|${RESET} ${GRAY}Argon 7d:${RESET} %s ${GRAY}|${RESET} ${GRAY}Gemini:${RESET} %s${GRAY}/${RESET}%s\n" \
        "$(draw_dots "$TP_5H_PCT")" "$TP_5H_RESET" "$(fmt_pct "$TP_7D_PCT")" "$TP_7D_RESET" \
        "$(fmt_pct "$ARGON_7D_PCT")" \
        "$(fmt_pct "$GEM_5H_PCT")" "$(fmt_pct "$GEM_7D_PCT")"
fi
