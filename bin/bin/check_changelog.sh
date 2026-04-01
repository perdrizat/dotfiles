#!/bin/bash
# check_changelog.sh — Stop hook: remind agent to update CHANGELOG.md
#
# Prints a warning when the working tree has changes but CHANGELOG.md
# is not among them. Silent otherwise (clean tree, not a repo, or
# CHANGELOG.md already touched).

git rev-parse --is-inside-work-tree &>/dev/null || exit 0

changed_files=$(git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
[ -z "$changed_files" ] && exit 0

if ! echo "$changed_files" | grep -q "CHANGELOG.md"; then
    echo "Files were changed but CHANGELOG.md was not updated. Remember to update it before wrapping up."
fi
