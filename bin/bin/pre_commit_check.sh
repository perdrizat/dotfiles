#!/bin/bash
# pre_commit_check.sh — Pre-commit checks: safety scan, doc freshness, changed files
#
# Run this once before committing. Output is both human-readable and
# useful as context for an LLM agent preparing a commit.

set -uo pipefail

# --- Changed files ---
status=$(git status --short 2>/dev/null)
if [ -z "$status" ]; then
    echo "Nothing to commit — working tree is clean."
    exit 0
fi

echo "=== Changed files ==="
echo "$status"
echo ""
git diff --stat HEAD 2>/dev/null
echo ""

# --- Safety scan ---
diff_text=$(git diff HEAD 2>/dev/null; git diff --cached 2>/dev/null)
warnings=()

# Secrets: check for files that look like they contain secrets
secret_files=$(echo "$status" | grep -iE '\.(env|pem|key)$|credentials|secret' | awk '{print $NF}' || true)
if [ -n "$secret_files" ]; then
    while IFS= read -r f; do
        warnings+=("Secret file staged: $f")
    done <<< "$secret_files"
fi

# Debug remnants in added lines
debug_hits=$(echo "$diff_text" | grep -n '^+' | grep -iE 'console\.log|debugger|print\(' | head -10 || true)
if [ -n "$debug_hits" ]; then
    while IFS= read -r line; do
        warnings+=("Debug remnant: $line")
    done <<< "$debug_hits"
fi

if [ ${#warnings[@]} -gt 0 ]; then
    echo "=== Safety warnings ==="
    for w in "${warnings[@]}"; do
        echo "  ~  $w"
    done
    echo ""
else
    echo "=== Safety scan ==="
    echo "  No secrets or debug remnants found."
    echo ""
fi

# --- Documentation freshness ---
changed_files=$(echo "$status" | awk '{print $NF}')
echo "=== Documentation freshness ==="
for doc in CHANGELOG.md CONTRIBUTING.md README.md; do
    if [ -f "$doc" ] || [ -L "$doc" ]; then
        if echo "$changed_files" | grep -qxF "$doc"; then
            echo "  $doc — updated"
        else
            echo "  $doc — not updated (may be stale)"
        fi
    fi
done
echo ""
