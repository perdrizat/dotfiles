#!/bin/bash
# validate_setup.sh — Validate dotfiles setup, report status, print fix commands
#
# Derives stow packages and symlinks at runtime from the filesystem.
# Shared config (prereqs, apt packages) lives in ~/dotfiles/dotfiles.conf.
#
# Exit codes: 0 = all green, 1 = issues found

set -uo pipefail

DOTFILES_DIR="$HOME/dotfiles"
source "$DOTFILES_DIR/setup.sh"

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
        actual=$(stat -Lc %a "$path")
        if [ "$actual" = "$expected" ]; then
            print_row "$label" "${GREEN}✓ $actual${NC}" ""
        else
            print_row "$label" "${YELLOW}⚠ $actual${NC}" "expected $expected"
            missing_items+=("$fix_id")
        fi
    fi
}

is_stow_skip() {
    local name="$1"
    for s in "${STOW_SKIP[@]}"; do
        [[ "$name" == "$s" ]] && return 0
    done
    return 1
}

# ==========================================
#  CHECKS
# ==========================================

echo ""
printf "${BOLD}Dotfiles Setup Validation${NC}\n"

# --- Prerequisites (from dotfiles.conf) ---
print_header "Prerequisites"

for cmd in "${PREREQS[@]}"; do
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

if [ -d "$DOTFILES_DIR/.git" ]; then
    cd "$DOTFILES_DIR"
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

# Check remote is SSH (not HTTPS)
if [ -d "$DOTFILES_DIR/.git" ]; then
    current_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)
    if [ "$current_remote" = "$DOTFILES_SSH_REMOTE" ]; then
        print_row "Remote URL" "${GREEN}✓ SSH${NC}" "$current_remote"
    else
        print_row "Remote URL" "${YELLOW}⚠ Not SSH${NC}" "$current_remote"
        missing_items+=("dotfiles-ssh-remote")
    fi
fi

# --- Shell Configuration ---
print_header "Shell Configuration"

if grep -q "Custom Dotfiles Loader" "$HOME/.bashrc" 2>/dev/null; then
    print_row ".bashrc loader" "${GREEN}✓ Present${NC}" "Custom Dotfiles Loader"
else
    print_row ".bashrc loader" "${RED}✗ Missing${NC}" "Loader block not in ~/.bashrc"
    missing_items+=("bashrc-loader")
fi

# --- Stow Symlinks (auto-discovered from filesystem) ---
print_header "Stow Symlinks"

for pkg_dir in "$DOTFILES_DIR"/*/; do
    pkg=$(basename "$pkg_dir")
    is_stow_skip "$pkg" && continue

    # Collect directories that stow may have folded into directory symlinks (any depth)
    folded_dirs=()
    while IFS= read -r -d '' entry; do
        relative="${entry#"$pkg_dir"}"
        relative="${relative%/}"
        target="$HOME/$relative"
        if [ -L "$target" ]; then
            actual=$(readlink -f "$target")
            expected=$(readlink -f "$entry")
            if [ "$actual" = "$expected" ]; then
                print_row "$relative/" "${GREEN}✓ Linked${NC}" "→ ${entry#"$HOME"/}"
                folded_dirs+=("$relative")
            fi
        fi
    done < <(find "$pkg_dir" -mindepth 1 -type d -print0 | sort -z)

    while IFS= read -r -d '' file; do
        relative="${file#"$pkg_dir"}"
        # Skip repo-only files and gitignored files (e.g. generated keys, known_hosts)
        [[ "$(basename "$relative")" == .gitignore ]] && continue
        git -C "$DOTFILES_DIR" check-ignore -q "$file" 2>/dev/null && continue
        # Skip files under directories already folded by stow
        skip=false
        for d in "${folded_dirs[@]+${folded_dirs[@]}}"; do
            [[ "$relative" == "$d/"* ]] && skip=true && break
        done
        $skip && continue
        target="$HOME/$relative"
        check_symlink "$relative" "$target" "$file" "stow-$pkg"
    done < <(find "$pkg_dir" -type f -print0 | sort -z)
done

# --- ~/bin scripts executable ---
print_header "Executable Scripts"

for script in "$HOME"/bin/*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    if [ -x "$script" ]; then
        print_row "$name" "${GREEN}✓ Executable${NC}" ""
    else
        print_row "$name" "${YELLOW}⚠ Not executable${NC}" ""
        missing_items+=("bin-exec")
    fi
done

# --- Global LLM Instructions ---
print_header "Global LLM Instructions"

GLOBAL_INSTRUCTIONS="$DOTFILES_DIR/agent/CONTRIBUTING.md"
check_symlink ".claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$GLOBAL_INSTRUCTIONS" "llm-global"
check_symlink ".codex/AGENTS.md" "$HOME/.codex/AGENTS.md" "$GLOBAL_INSTRUCTIONS" "llm-global"
check_symlink ".gemini/AGENTS.md" "$HOME/.gemini/AGENTS.md" "$GLOBAL_INSTRUCTIONS" "llm-global"
check_symlink ".gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md" "$GLOBAL_INSTRUCTIONS" "llm-global"

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

# Verify .age file matches the repo copy (same encrypted key on all machines)
if [ -f "$HOME/.ssh/id_ed25519.age" ] && [ -f "$DOTFILES_DIR/ssh/.ssh/id_ed25519.age" ]; then
    deployed_sum=$(sha256sum "$HOME/.ssh/id_ed25519.age" | cut -d' ' -f1)
    repo_sum=$(sha256sum "$DOTFILES_DIR/ssh/.ssh/id_ed25519.age" | cut -d' ' -f1)
    if [ "$deployed_sum" = "$repo_sum" ]; then
        print_row ".age matches repo" "${GREEN}✓ Match${NC}" "${deployed_sum:0:12}…"
    else
        print_row ".age matches repo" "${RED}✗ Mismatch${NC}" "Deployed .age differs from repo"
        missing_items+=("stow-ssh")
    fi
fi

# Verify public key matches private key
if [ -f "$HOME/.ssh/id_ed25519" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    priv_pub=$(ssh-keygen -y -f "$HOME/.ssh/id_ed25519" 2>/dev/null | cut -d' ' -f1,2)
    disk_pub=$(cut -d' ' -f1,2 "$HOME/.ssh/id_ed25519.pub" 2>/dev/null)
    if [ "$priv_pub" = "$disk_pub" ]; then
        print_row "Public key matches private" "${GREEN}✓ Match${NC}" ""
    else
        print_row "Public key matches private" "${RED}✗ Mismatch${NC}" "Regenerate with ssh-keygen -y"
        missing_items+=("ssh-regen-pub")
    fi
elif [ -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
    print_row "Public key" "${YELLOW}⚠ Missing${NC}" "Regenerate from private key"
    missing_items+=("ssh-regen-pub")
fi

check_perms ".ssh/ permissions" "$HOME/.ssh" "700" "ssh-dir-perms"
check_perms "Private key permissions" "$HOME/.ssh/id_ed25519" "600" "ssh-key-perms"
check_perms ".ssh/config permissions" "$HOME/.ssh/config" "644" "ssh-config-perms"

# --- Git ---
print_header "Git Configuration"

git_user=$(git config --global user.name 2>/dev/null || echo "")
git_email=$(git config --global user.email 2>/dev/null || echo "")
if [ -n "$git_user" ] && [ -n "$git_email" ]; then
    print_row "User identity" "${GREEN}✓ Set${NC}" "$git_user <$git_email>"
else
    print_row "User identity" "${YELLOW}⚠ Incomplete${NC}" "name='$git_user' email='$git_email'"
fi

# --- APT Packages ---
print_header "APT Packages"

for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ver=$(dpkg -s "$pkg" 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "$pkg" "${GREEN}✓ Installed${NC}" "$ver"
    else
        print_row "$pkg" "${RED}✗ Missing${NC}" ""
        missing_items+=("apt-$pkg")
    fi
done

# --- Dev Toolchains ---
print_header "Dev Toolchains"

if [[ "$INSTALL_RUST" == true ]]; then
    if command -v rustup >/dev/null 2>&1; then
        rust_ver=$(rustc --version 2>/dev/null | cut -d' ' -f2)
        print_row "Rust (rustup)" "${GREEN}✓ Installed${NC}" "$rust_ver"
    else
        print_row "Rust (rustup)" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-rust")
    fi
fi

if [[ "$INSTALL_NODE" == true ]]; then
    # Ensure fnm is on PATH for this check
    [[ -d "$HOME/.local/share/fnm" ]] && export PATH="$HOME/.local/share/fnm:$PATH" && eval "$(fnm env --shell bash 2>/dev/null)" 2>/dev/null
    if command -v fnm >/dev/null 2>&1; then
        print_row "fnm" "${GREEN}✓ Installed${NC}" "$(fnm --version 2>/dev/null)"
    else
        print_row "fnm" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-fnm")
    fi
    if command -v node >/dev/null 2>&1; then
        print_row "Node" "${GREEN}✓ Installed${NC}" "$(node --version 2>/dev/null)"
    else
        print_row "Node" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-node")
    fi
    if command -v vite >/dev/null 2>&1; then
        vite_ver=$(vite --version 2>/dev/null | tail -1)
        print_row "vite" "${GREEN}✓ Installed${NC}" "$vite_ver"
    else
        print_row "vite" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-vite")
    fi
fi

if [[ "$INSTALL_ICP" == true ]]; then
    if command -v dfx >/dev/null 2>&1; then
        dfx_ver=$(dfx --version 2>/dev/null || echo "unknown")
        print_row "dfx (dfxvm)" "${GREEN}✓ Installed${NC}" "$dfx_ver"
    else
        print_row "dfx (dfxvm)" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-icp")
    fi
    if command -v ic-admin >/dev/null 2>&1; then
        print_row "ic-admin" "${GREEN}✓ Installed${NC}" ""
    else
        print_row "ic-admin" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-ic-admin")
    fi
fi

if [[ "$INSTALL_PYTHON" == true ]]; then
    if command -v python3 >/dev/null 2>&1 && dpkg -s python3-venv >/dev/null 2>&1; then
        py_ver=$(python3 --version 2>/dev/null | cut -d' ' -f2)
        print_row "Python + venv" "${GREEN}✓ Installed${NC}" "$py_ver"
    else
        print_row "Python + venv" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-python")
    fi
fi

if [[ "$INSTALL_DOCKER" == true ]]; then
    if dpkg -s docker-compose-v2 >/dev/null 2>&1; then
        dc_ver=$(dpkg -s docker-compose-v2 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "Docker Compose" "${GREEN}✓ Installed${NC}" "$dc_ver"
    else
        print_row "Docker Compose" "${RED}✗ Missing${NC}" ""
        missing_items+=("install-docker")
    fi
    if id -nG "$USER" | grep -qw docker; then
        print_row "docker group" "${GREEN}✓ Member${NC}" "$USER"
    else
        print_row "docker group" "${RED}✗ Not a member${NC}" "$USER"
        missing_items+=("docker-group")
    fi
fi

# --- LLM Agents ---
if [[ "$INSTALL_CLAUDE" == true ]] || [[ "$INSTALL_GEMINI_CLI" == true ]]; then
    print_header "LLM Agents"
fi

if [[ "$INSTALL_CLAUDE" == true ]]; then
    if command -v claude >/dev/null 2>&1; then
        claude_ver=$(claude --version 2>/dev/null || echo "unknown")
        print_row "Claude Code CLI" "${GREEN}✓ Installed${NC}" "$claude_ver"
    else
        print_row "Claude Code CLI" "${RED}✗ Missing${NC}" ""
        missing_items+=("claude-cli")
    fi
fi

if [[ "$INSTALL_GEMINI_CLI" == true ]]; then
    if command -v gemini >/dev/null 2>&1; then
        gemini_ver=$(gemini --version 2>/dev/null || echo "unknown")
        print_row "Gemini CLI" "${GREEN}✓ Installed${NC}" "$gemini_ver"
    else
        print_row "Gemini CLI" "${RED}✗ Missing${NC}" ""
        missing_items+=("gemini-cli")
    fi
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
        dotfiles-ssh-remote)
            printf "\n  ${CYAN}# Switch dotfiles remote to SSH${NC}\n"
            echo "  git -C ~/dotfiles remote set-url origin $DOTFILES_SSH_REMOTE"
            ;;
    esac
done

# 3. Stow symlinks (auto-collected from fix IDs)
stow_packages=()
for item in "${unique_items[@]}"; do
    case "$item" in stow-*) stow_packages+=("${item#stow-}") ;; esac
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
            ssh-regen-pub)      echo "  ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub" ;;
            ssh-dir-perms)      echo "  chmod 700 ~/.ssh" ;;
            ssh-stow-dir-perms) echo "  chmod 700 ~/dotfiles/ssh/.ssh" ;;
            ssh-key-perms)      echo "  chmod 600 ~/.ssh/id_ed25519" ;;
            ssh-config-perms)   echo "  chmod 644 ~/.ssh/config" ;;
        esac
    done
fi

# 6. Global LLM instructions
for item in "${unique_items[@]}"; do
    case "$item" in
        llm-global)
            printf "\n  ${CYAN}# Link global LLM instructions${NC}\n"
            echo "  mkdir -p ~/.claude ~/.codex ~/.gemini && ln -sf ~/dotfiles/agent/CONTRIBUTING.md ~/.claude/CLAUDE.md && ln -sf ~/dotfiles/agent/CONTRIBUTING.md ~/.codex/AGENTS.md && ln -sf ~/dotfiles/agent/CONTRIBUTING.md ~/.gemini/AGENTS.md && ln -sf ~/dotfiles/agent/CONTRIBUTING.md ~/.gemini/GEMINI.md"
            break ;;
    esac
done

# 7. Executable scripts
for item in "${unique_items[@]}"; do
    case "$item" in
        bin-exec)
            printf "\n  ${CYAN}# Fix script permissions${NC}\n"
            echo "  chmod +x ~/bin/*.sh"
            break ;;
    esac
done

# 8. APT packages
apt_pkgs=()
for item in "${unique_items[@]}"; do
    case "$item" in apt-*) apt_pkgs+=("${item#apt-}") ;; esac
done
if [ ${#apt_pkgs[@]} -gt 0 ]; then
    printf "\n  ${CYAN}# Install packages${NC}\n"
    echo "  sudo apt update && sudo apt install -y ${apt_pkgs[*]}"
fi

# 9. Dev toolchains
for item in "${unique_items[@]}"; do
    case "$item" in
        install-rust)
            printf "\n  ${CYAN}# Install Rust${NC}\n"
            echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable -c clippy,rustfmt"
            ;;
        install-fnm)
            printf "\n  ${CYAN}# Install fnm${NC}\n"
            echo "  curl -fsSL https://fnm.vercel.app/install | bash"
            ;;
        install-node)
            printf "\n  ${CYAN}# Install Node LTS${NC}\n"
            echo "  export PATH=\"\$HOME/.local/share/fnm:\$PATH\" && eval \"\$(fnm env --shell bash)\" && fnm install --lts"
            ;;
        install-vite)
            printf "\n  ${CYAN}# Install vite${NC}\n"
            echo "  export PATH=\"\$HOME/.local/share/fnm:\$PATH\" && eval \"\$(fnm env --shell bash)\" && npm install -g vite"
            ;;
        install-icp)
            printf "\n  ${CYAN}# Install dfxvm (DFINITY SDK)${NC}\n"
            echo '  sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"'
            ;;
        install-ic-admin)
            printf "\n  ${CYAN}# Install ic-admin${NC}\n"
            echo '  curl -L "https://github.com/dfinity/ic/releases/latest/download/ic-admin-x86_64-linux.gz" -o - | gunzip > ic-admin && chmod 0755 ./ic-admin'
            ;;
        install-python)
            printf "\n  ${CYAN}# Install Python + venv${NC}\n"
            echo "  sudo apt update && sudo apt install -y python3 python3-venv"
            ;;
        install-docker)
            printf "\n  ${CYAN}# Install Docker Compose${NC}\n"
            echo "  sudo apt update && sudo apt install -y docker-compose-v2"
            ;;
        docker-group)
            printf "\n  ${CYAN}# Add user to docker group (logout/login to take effect)${NC}\n"
            echo "  sudo usermod -aG docker \$USER"
            ;;
    esac
done

# 10. LLM agents
for item in "${unique_items[@]}"; do
    case "$item" in
        claude-cli)
            printf "\n  ${CYAN}# Install Claude Code${NC}\n"
            echo "  curl -fsSL https://claude.ai/install.sh | bash"
            ;;
        gemini-cli)
            printf "\n  ${CYAN}# Install Gemini CLI${NC}\n"
            echo "  npm install -g @google/gemini-cli"
            ;;
    esac
done

echo ""
exit 1
