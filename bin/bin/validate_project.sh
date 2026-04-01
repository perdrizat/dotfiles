#!/bin/bash
# validate_project.sh — Check agent file setup in the current project
#
# Verifies:
#   - CONTRIBUTING.md exists (source of truth)
#   - CLAUDE.md, AGENTS.md, GEMINI.md are symlinks to CONTRIBUTING.md
#   - All three symlinks are listed in .gitignore

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

issues=0

check_source() {
    if [ -f CONTRIBUTING.md ]; then
        printf "  %-20s ${GREEN}✓ Present${NC}\n" "CONTRIBUTING.md"
    else
        printf "  %-20s ${RED}✗ Missing${NC}  — create it or run init_project.sh\n" "CONTRIBUTING.md"
        ((issues++))
    fi
}

check_symlink() {
    local name="$1"
    if [ -L "$name" ]; then
        local target
        target=$(readlink "$name")
        if [ "$target" = "CONTRIBUTING.md" ]; then
            printf "  %-20s ${GREEN}✓ Linked${NC}  → CONTRIBUTING.md\n" "$name"
        else
            printf "  %-20s ${YELLOW}⚠ Wrong target${NC}  → %s (expected CONTRIBUTING.md)\n" "$name" "$target"
            ((issues++))
        fi
    elif [ -f "$name" ]; then
        printf "  %-20s ${RED}✗ Regular file${NC}  — replace with: ln -sf CONTRIBUTING.md %s\n" "$name" "$name"
        ((issues++))
    else
        printf "  %-20s ${RED}✗ Missing${NC}  — run: ln -s CONTRIBUTING.md %s\n" "$name" "$name"
        ((issues++))
    fi
}

check_gitignore() {
    local name="$1"
    if [ -f .gitignore ] && grep -qxF "$name" .gitignore; then
        return
    fi
    printf "  %-20s ${RED}✗ Not in .gitignore${NC}  — run: echo '%s' >> .gitignore\n" "$name" "$name"
    ((issues++))
}

echo "Agent file check:"

check_source

for name in CLAUDE.md AGENTS.md GEMINI.md; do
    check_symlink "$name"
    check_gitignore "$name"
done

echo ""
[ "$issues" -eq 0 ] && exit 0 || exit 1
