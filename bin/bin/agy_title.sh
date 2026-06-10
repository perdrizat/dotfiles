#!/bin/bash
# agy_title.sh — Terminal title for Antigravity CLI (agy)
#
# agy pipes a state JSON payload on stdin whenever the agent state changes;
# stdout becomes the terminal window title. Mirrors the claude@<session> naming
# convention: "agy@<workspace>", prefixed with ✳ while the agent is working.

DATA=$(cat)
CWD=$(echo "$DATA" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
STATE=$(echo "$DATA" | jq -r '.agent_state // "idle"' 2>/dev/null)

WORKSPACE=$(basename "${CWD:-$PWD}")

case "$STATE" in
    idle|"") echo "agy@$WORKSPACE" ;;
    *)       echo "✳ agy@$WORKSPACE" ;;
esac
