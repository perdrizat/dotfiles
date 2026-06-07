#!/bin/bash
# validate_project.sh — Check agent file setup in the current project
#
# Verifies:
#   - CONTRIBUTING.md exists (source of truth)
#   - CLAUDE.md, AGENTS.md are symlinks to CONTRIBUTING.md
#   - All three symlinks are listed in .gitignore

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

issues=0
fix_commands=()

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
            fix_commands+=("rm $name && ln -s CONTRIBUTING.md $name")
            ((issues++))
        fi
    elif [ -f "$name" ]; then
        printf "  %-20s ${RED}✗ Regular file${NC}  — replace with symlink\n" "$name"
        fix_commands+=("rm $name && ln -s CONTRIBUTING.md $name")
        ((issues++))
    else
        printf "  %-20s ${RED}✗ Missing${NC}\n" "$name"
        fix_commands+=("ln -s CONTRIBUTING.md $name")
        ((issues++))
    fi
}

check_gitignore() {
    local name="$1"
    if [ -f .gitignore ] && grep -qxF "$name" .gitignore; then
        return
    fi
    printf "  %-20s ${RED}✗ Not in .gitignore${NC}\n" "$name"
    fix_commands+=("echo '$name' >> .gitignore")
    ((issues++))
}

echo "Agent file check:"

check_source

for name in CLAUDE.md AGENTS.md; do
    check_symlink "$name"
    check_gitignore "$name"
done

echo ""

if [ "$issues" -eq 0 ]; then
    exit 0
fi

echo "To fix, copy-paste:"
echo ""
# One-liner: `( cd "<run cwd>" && cmd1 && cmd2 && ... )`.
# The cd prefix uses the script's run cwd so the line is pasteable from any shell,
# whether validate_project.sh was launched standalone inside a project or invoked
# from validate_setup.sh (which cd's into ~/dotfiles before calling it).
fix_line="( cd \"$(pwd)\""
for cmd in "${fix_commands[@]}"; do
    fix_line+=" && $cmd"
done
fix_line+=" )"
echo "$fix_line"
echo ""
exit 1
