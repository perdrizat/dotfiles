#!/bin/bash
# check_repos.sh — Check all git repos under ~ for uncommitted code

set -uo pipefail

show_help() {
    cat << 'EOF'
check_repos.sh — Report status of all git repos under ~

Output format (one line per repo):
  repo_path: clean
  repo_path: 2M/1A/3?

Status symbols (git native):
  M = modified files
  A = added files
  D = deleted files
  R = renamed files
  C = copied files
  U = unmerged files (conflicts)
  ? = untracked files

Examples:
  /home/user/project: clean         (no uncommitted changes)
  /home/user/website: 2M/1A/3?      (2 modified, 1 added, 3 untracked)
  /home/user/dotfiles: 1M/2D        (1 modified, 2 deleted)

Usage:
  check_repos.sh              Show all repos (clean or with changes)
  check_repos.sh -v|--verbose Show full git status output for each repo
  check_repos.sh -h|--help    Show this help
EOF
}

# Handle flags
VERBOSE=false
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_help && exit 0
[[ "${1:-}" == "-v" || "${1:-}" == "--verbose" ]] && VERBOSE=true

# Directories to skip
skip_patterns=(
    '.cache'
    '.local'
    '.config'
    '.ssh'
    '.gnupg'
    '.nvm'
    'node_modules'
    '.pytest_cache'
    '__pycache__'
)

# Find all git repos, collect them for sorting
repos=()
while IFS= read -r gitdir; do
    repo_path=$(dirname "$gitdir")

    # Skip unwanted directories
    skip=false
    for pattern in "${skip_patterns[@]}"; do
        [[ "$repo_path" == *"/$pattern"* ]] && skip=true && break
    done
    $skip && continue

    repos+=("$repo_path")
done < <(find ~ -name .git -type d 2>/dev/null)

# Sort repos alphabetically
mapfile -t repos < <(printf '%s\n' "${repos[@]}" | sort)

# Process each repo
for repo_path in "${repos[@]}"; do
    # Get repo name (basename of path)
    repo_name=$(basename "$repo_path")

    # Get status and count changes
    status=$(git -C "$repo_path" status --porcelain 2>/dev/null)

    if [ -z "$status" ]; then
        # Clean repo - no uncommitted changes
        if $VERBOSE; then
            printf "\033[1m# git -C %s status\033[0m\n" "$repo_path"
            git -C "$repo_path" status
            echo ""
        else
            echo "$repo_name: clean"
        fi
    else
        # Count changes by type (git porcelain format: XY where X=staged, Y=unstaged)
        # Anchored patterns: ^X = staged, ^ X = unstaged (space in first position, status in second)
        M=$(echo "$status" | grep -cE '^M|^ M' || true)
        A=$(echo "$status" | grep -cE '^A|^ A' || true)
        D=$(echo "$status" | grep -cE '^D|^ D' || true)
        R=$(echo "$status" | grep -cE '^R|^ R' || true)
        C=$(echo "$status" | grep -cE '^C|^ C' || true)
        U=$(echo "$status" | grep -cE '^U|^ U' || true)
        untracked=$(echo "$status" | grep -cE '^\?\?' || true)

        # Build summary line (git status symbols)
        parts=()
        [ "$M" -gt 0 ] && parts+=("${M}M")
        [ "$A" -gt 0 ] && parts+=("${A}A")
        [ "$D" -gt 0 ] && parts+=("${D}D")
        [ "$R" -gt 0 ] && parts+=("${R}R")
        [ "$C" -gt 0 ] && parts+=("${C}C")
        [ "$U" -gt 0 ] && parts+=("${U}U")
        [ "$untracked" -gt 0 ] && parts+=("${untracked}?")

        summary=$(IFS=/ ; echo "${parts[*]}")

        if $VERBOSE; then
            printf "\033[1m# git -C %s status\033[0m\n" "$repo_path"
            git -C "$repo_path" status
            echo ""
        else
            printf "\033[1m%s: %s\033[0m\n" "$repo_name" "$summary"
        fi
    fi
done
