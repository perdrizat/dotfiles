#!/bin/bash
# validate_setup.sh — Validate dotfiles setup, report status, print fix commands
#
# Checks everything managed by setup.sh:
#   prerequisites, repo sync, shell config, stow symlinks,
#   SSH, git, apt packages, agent config, and Claude Code settings.
#
# Exit codes: 0 = all green, 1 = issues found

set -uo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- State ---
missing_items=()

# --- Helpers ---
print_header() {
    echo ""
    printf "${BOLD}%s${NC}\n" "$1"
}

print_row() {
    local label="$1" status="$2" detail="$3"
    printf "  %-30s %b  %s\n" "$label" "$status" "$detail"
}

check_symlink() {
    local label="$1" link="$2" expected_target="$3" fix_id="$4"
    if [ -L "$link" ]; then
        local actual expected
        actual=$(readlink -f "$link")
        expected=$(readlink -f "$expected_target" 2>/dev/null || echo "$expected_target")
        if [ "$actual" = "$expected" ]; then
            print_row "$label" "${GREEN}✓ Linked${NC}" "→ ${expected_target#"$HOME"/}"
        else
            print_row "$label" "${YELLOW}⚠ Wrong target${NC}" "→ $actual"
            missing_items+=("$fix_id")
        fi
    elif [ -e "$link" ]; then
        print_row "$label" "${YELLOW}⚠ Not a symlink${NC}" "$link is a regular file"
        missing_items+=("$fix_id")
    else
        print_row "$label" "${RED}✗ Missing${NC}" "$link"
        missing_items+=("$fix_id")
    fi
}

check_perms() {
    local label="$1" path="$2" expected="$3" fix_id="$4"
    if [ -e "$path" ]; then
        local actual
        actual=$(stat -c %a "$path")
        if [ "$actual" = "$expected" ]; then
            print_row "$label" "${GREEN}✓ $actual${NC}" ""
        else
            print_row "$label" "${YELLOW}⚠ $actual${NC}" "expected $expected"
            missing_items+=("$fix_id")
        fi
    fi
}

# ==========================================
#  CHECKS
# ==========================================

echo ""
printf "${BOLD}Dotfiles Setup Validation${NC}\n"

# --- Prerequisites ---
print_header "Prerequisites"

for cmd in git curl stow age; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ver=$(dpkg -s "$cmd" 2>/dev/null | grep '^Version:' | cut -d' ' -f2 || echo "installed")
        print_row "$cmd" "${GREEN}✓ Installed${NC}" "$ver"
    else
        print_row "$cmd" "${RED}✗ Missing${NC}" ""
        missing_items+=("prereq-$cmd")
    fi
done

# --- Dotfiles Repo ---
print_header "Dotfiles Repository"

if [ -d "$HOME/dotfiles/.git" ]; then
    cd "$HOME/dotfiles"
    git fetch --quiet 2>/dev/null || true
    local_head=$(git rev-parse HEAD 2>/dev/null)
    remote_head=$(git rev-parse origin/main 2>/dev/null || echo "")
    if [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
        behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
        ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        print_row "dotfiles repo" "${YELLOW}⚠ Out of sync${NC}" "${behind} behind, ${ahead} ahead"
        missing_items+=("dotfiles-sync")
    else
        print_row "dotfiles repo" "${GREEN}✓ Up to date${NC}" "~/dotfiles"
    fi
else
    print_row "dotfiles repo" "${RED}✗ Missing${NC}" "~/dotfiles"
    missing_items+=("dotfiles-clone")
fi

# --- Shell Configuration ---
print_header "Shell Configuration"

if grep -q "Custom Dotfiles Loader" "$HOME/.bashrc" 2>/dev/null; then
    print_row ".bashrc loader" "${GREEN}✓ Present${NC}" "Custom Dotfiles Loader"
else
    print_row ".bashrc loader" "${RED}✗ Missing${NC}" "Loader block not in ~/.bashrc"
    missing_items+=("bashrc-loader")
fi

# --- Stow Symlinks ---
print_header "Stow Symlinks"

check_symlink ".bash_aliases" "$HOME/.bash_aliases" "$HOME/dotfiles/bash/.bash_aliases" "stow-bash"
check_symlink ".bash_extra" "$HOME/.bash_extra" "$HOME/dotfiles/bash/.bash_extra" "stow-bash"
check_symlink "~/bin" "$HOME/bin" "$HOME/dotfiles/bin/bin" "stow-bin"
check_symlink ".claude/settings.json" "$HOME/.claude/settings.json" "$HOME/dotfiles/claude/.claude/settings.json" "stow-claude"
check_symlink ".claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$HOME/dotfiles/claude/.claude/CLAUDE.md" "stow-claude"
check_symlink ".gitconfig" "$HOME/.gitconfig" "$HOME/dotfiles/git/.gitconfig" "stow-git"
check_symlink ".ssh/config" "$HOME/.ssh/config" "$HOME/dotfiles/ssh/.ssh/config" "stow-ssh"
check_symlink ".ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/dotfiles/ssh/.ssh/id_ed25519.pub" "stow-ssh"
check_symlink ".ssh/id_ed25519.age" "$HOME/.ssh/id_ed25519.age" "$HOME/dotfiles/ssh/.ssh/id_ed25519.age" "stow-ssh"
check_symlink ".ssh/known_hosts" "$HOME/.ssh/known_hosts" "$HOME/dotfiles/ssh/.ssh/known_hosts" "stow-ssh"

# --- Agent Symlinks (manual, not stow) ---
print_header "Agent Configuration"

if [ -d "$HOME/.agent" ]; then
    check_symlink ".agent/skills" "$HOME/.agent/skills" "$HOME/dotfiles/agent/.agent/skills" "agent-symlinks"
    check_symlink ".agent/workflows" "$HOME/.agent/workflows" "$HOME/dotfiles/agent/.agent/workflows" "agent-symlinks"
else
    print_row ".agent/ directory" "${RED}✗ Missing${NC}" "~/.agent"
    missing_items+=("agent-symlinks")
fi

# --- SSH ---
print_header "SSH"

if [ -f "$HOME/.ssh/id_ed25519" ]; then
    print_row "SSH private key" "${GREEN}✓ Decrypted${NC}" "~/.ssh/id_ed25519"
elif [ -f "$HOME/.ssh/id_ed25519.age" ]; then
    print_row "SSH private key" "${YELLOW}⚠ Encrypted${NC}" "Needs age decryption"
    missing_items+=("ssh-decrypt")
else
    print_row "SSH private key" "${RED}✗ Missing${NC}" "No key or .age file"
fi

check_perms ".ssh/ permissions" "$HOME/.ssh" "700" "ssh-dir-perms"
check_perms "Private key permissions" "$HOME/.ssh/id_ed25519" "600" "ssh-key-perms"
check_perms ".ssh/config permissions" "$HOME/.ssh/config" "644" "ssh-config-perms"
check_perms "dotfiles ssh dir" "$HOME/dotfiles/ssh/.ssh" "700" "ssh-stow-dir-perms"

# --- Git ---
print_header "Git Configuration"

if [ -f "$HOME/.gitconfig" ]; then
    git_user=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    if [ -n "$git_user" ] && [ -n "$git_email" ]; then
        print_row "User identity" "${GREEN}✓ Set${NC}" "$git_user <$git_email>"
    else
        print_row "User identity" "${YELLOW}⚠ Incomplete${NC}" "name='$git_user' email='$git_email'"
        missing_items+=("stow-git")
    fi

    default_branch=$(git config --global init.defaultBranch 2>/dev/null || echo "")
    pull_rebase=$(git config --global pull.rebase 2>/dev/null || echo "")
    if [ "$default_branch" = "main" ] && [ "$pull_rebase" = "true" ]; then
        print_row "Git settings" "${GREEN}✓ Correct${NC}" "branch=main, pull=rebase"
    else
        print_row "Git settings" "${YELLOW}⚠ Drift${NC}" "branch='$default_branch' pull.rebase='$pull_rebase'"
        missing_items+=("stow-git")
    fi
else
    print_row "Git config" "${RED}✗ Missing${NC}" "~/.gitconfig"
    missing_items+=("stow-git")
fi

# --- APT Packages ---
print_header "APT Packages"

for pkg in build-essential python3-venv docker-compose-v2; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ver=$(dpkg -s "$pkg" 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "$pkg" "${GREEN}✓ Installed${NC}" "$ver"
    else
        print_row "$pkg" "${RED}✗ Missing${NC}" ""
        missing_items+=("apt-$pkg")
    fi
done

# --- Claude Code ---
print_header "Claude Code"

if command -v claude >/dev/null 2>&1; then
    claude_ver=$(claude --version 2>/dev/null || echo "unknown")
    print_row "Claude Code CLI" "${GREEN}✓ Installed${NC}" "$claude_ver"
else
    print_row "Claude Code CLI" "${RED}✗ Missing${NC}" ""
    missing_items+=("claude-cli")
fi

if [ -f "$HOME/.claude/settings.json" ]; then
    settings_issues=""
    if ! grep -q "alwaysThinkingEnabled.*true" "$HOME/.claude/settings.json"; then
        settings_issues="thinking"
    fi
    if ! grep -q "statusLine" "$HOME/.claude/settings.json"; then
        settings_issues="${settings_issues:+$settings_issues, }statusLine"
    fi

    if [ -z "$settings_issues" ]; then
        print_row "Claude Code settings" "${GREEN}✓ Configured${NC}" "Thinking + status line enabled"
    else
        print_row "Claude Code settings" "${YELLOW}⚠ Incomplete${NC}" "Missing: $settings_issues"
        missing_items+=("claude-settings")
    fi
else
    print_row "Claude Code settings" "${RED}✗ Missing${NC}" "~/.claude/settings.json"
    missing_items+=("claude-settings")
fi

# ==========================================
#  SUMMARY + FIX COMMANDS
# ==========================================

echo ""

if [ ${#missing_items[@]} -eq 0 ]; then
    printf "${GREEN}${BOLD}All checks passed!${NC}\n\n"
    exit 0
fi

# Deduplicate missing_items while preserving order
declare -A seen
unique_items=()
for item in "${missing_items[@]}"; do
    if [ -z "${seen[$item]+x}" ]; then
        seen[$item]=1
        unique_items+=("$item")
    fi
done

printf "${BOLD}Fix commands (in dependency order):${NC}\n"

# 1. Prerequisites
prereqs=()
for item in "${unique_items[@]}"; do
    case "$item" in prereq-*) prereqs+=("${item#prereq-}") ;; esac
done
if [ ${#prereqs[@]} -gt 0 ]; then
    printf "\n  ${CYAN}# Install prerequisites${NC}\n"
    echo "  sudo apt update && sudo apt install -y ${prereqs[*]}"
fi

# 2. Dotfiles repo
for item in "${unique_items[@]}"; do
    case "$item" in
        dotfiles-clone)
            printf "\n  ${CYAN}# Clone dotfiles${NC}\n"
            echo "  cd ~ && git clone https://github.com/perdrizat/dotfiles.git"
            ;;
        dotfiles-sync)
            printf "\n  ${CYAN}# Sync dotfiles${NC}\n"
            echo "  cd ~/dotfiles && git pull --rebase"
            ;;
    esac
done

# 3. Stow symlinks (batch all needed packages)
stow_packages=()
for item in "${unique_items[@]}"; do
    case "$item" in
        stow-bash)   stow_packages+=("bash") ;;
        stow-bin)    stow_packages+=("bin") ;;
        stow-claude) stow_packages+=("claude") ;;
        stow-ssh)    stow_packages+=("ssh") ;;
        stow-git)    stow_packages+=("git") ;;
    esac
done
if [ ${#stow_packages[@]} -gt 0 ]; then
    printf "\n  ${CYAN}# Re-link stow packages${NC}\n"
    cmd="  cd ~/dotfiles"
    for pkg in "${stow_packages[@]}"; do cmd+=" && stow --adopt $pkg"; done
    echo "$cmd"
fi

# 4. Shell config
for item in "${unique_items[@]}"; do
    case "$item" in
        bashrc-loader)
            printf "\n  ${CYAN}# Inject dotfiles loader into .bashrc${NC}\n"
            echo "  cd ~/dotfiles && bash setup.sh"
            break ;;
    esac
done

# 5. SSH (before git — git push/pull needs SSH)
ssh_fixes=false
for item in "${unique_items[@]}"; do
    case "$item" in ssh-*) ssh_fixes=true; break ;; esac
done
if $ssh_fixes; then
    printf "\n  ${CYAN}# Fix SSH${NC}\n"
    for item in "${unique_items[@]}"; do
        case "$item" in
            ssh-decrypt)        echo "  age --decrypt -o ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.age && chmod 600 ~/.ssh/id_ed25519" ;;
            ssh-dir-perms)      echo "  chmod 700 ~/.ssh" ;;
            ssh-stow-dir-perms) echo "  chmod 700 ~/dotfiles/ssh/.ssh" ;;
            ssh-key-perms)      echo "  chmod 600 ~/.ssh/id_ed25519" ;;
            ssh-config-perms)   echo "  chmod 644 ~/.ssh/config" ;;
        esac
    done
fi

# 6. Agent symlinks
for item in "${unique_items[@]}"; do
    case "$item" in
        agent-symlinks)
            printf "\n  ${CYAN}# Link agent config${NC}\n"
            echo "  mkdir -p ~/.agent && ln -sf ~/dotfiles/agent/.agent/skills ~/.agent/skills && ln -sf ~/dotfiles/agent/.agent/workflows ~/.agent/workflows"
            break ;;
    esac
done

# 7. APT packages
apt_pkgs=()
for item in "${unique_items[@]}"; do
    case "$item" in apt-*) apt_pkgs+=("${item#apt-}") ;; esac
done
if [ ${#apt_pkgs[@]} -gt 0 ]; then
    printf "\n  ${CYAN}# Install packages${NC}\n"
    echo "  sudo apt update && sudo apt install -y ${apt_pkgs[*]}"
fi

# 8. Claude Code
for item in "${unique_items[@]}"; do
    case "$item" in
        claude-cli)
            printf "\n  ${CYAN}# Install Claude Code${NC}\n"
            echo "  npm install -g @anthropic-ai/claude-code"
            ;;
        claude-settings)
            printf "\n  ${CYAN}# Configure Claude Code settings${NC}\n"
            echo "  # Edit ~/.claude/settings.json — enable alwaysThinkingEnabled and statusLine"
            ;;
    esac
done

echo ""
exit 1
