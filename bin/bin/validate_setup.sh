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
            print_row "$label" "${YELLOW}~ Wrong target${NC}" "→ $actual"
            missing_items+=("$fix_id")
        fi
    elif [ -e "$link" ]; then
        print_row "$label" "${YELLOW}~ Not a symlink${NC}" "$link is a regular file"
        missing_items+=("$fix_id")
    else
        print_row "$label" "${RED}x Missing${NC}" "$link"
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
            print_row "$label" "${YELLOW}~ $actual${NC}" "expected $expected"
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
#  UPDATE MODE
# ==========================================

if [[ "${1:-}" == "-u" || "${1:-}" == "--update" ]]; then
    echo ""
    printf "${BOLD}Updating packages and toolchains${NC}\n"

    # 1. APT packages first (dependencies for other tools)
    printf "\n${CYAN}Updating apt packages${NC}\n"
    sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

    # 2. Dev toolchains
    if [[ "$INSTALL_RUST" == true ]] && command -v rustup >/dev/null 2>&1; then
        printf "\n${CYAN}Updating Rust${NC}\n"
        rustup update
    fi

    if [[ "$INSTALL_NODE" == true ]] && command -v fnm >/dev/null 2>&1; then
        printf "\n${CYAN}Updating Node LTS${NC}\n"
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env --shell bash 2>/dev/null)" 2>/dev/null
        fnm install --lts
    fi

    if [[ "$INSTALL_ICP" == true ]] && command -v dfxvm >/dev/null 2>&1; then
        printf "\n${CYAN}Updating dfx (DFINITY SDK)${NC}\n"
        dfxvm update || true
    fi

    echo ""
    printf "${GREEN}${BOLD}Updates complete!${NC}\n\n"
    exit 0
fi

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
        print_row "$cmd" "${RED}x Missing${NC}" ""
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
        print_row "dotfiles repo" "${YELLOW}~ Out of sync${NC}" "${behind} behind, ${ahead} ahead"
        missing_items+=("dotfiles-sync")
    else
        print_row "dotfiles repo" "${GREEN}✓ Up to date${NC}" "~/dotfiles"
    fi
else
    print_row "dotfiles repo" "${RED}x Missing${NC}" "~/dotfiles"
    missing_items+=("dotfiles-clone")
fi

# Check remote is SSH (not HTTPS)
if [ -d "$DOTFILES_DIR/.git" ]; then
    current_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)
    if [ "$current_remote" = "$DOTFILES_SSH_REMOTE" ]; then
        print_row "Remote URL" "${GREEN}✓ SSH${NC}" "$current_remote"
    else
        print_row "Remote URL" "${YELLOW}~ Not SSH${NC}" "$current_remote"
        missing_items+=("dotfiles-ssh-remote")
    fi
fi

# --- System Configuration ---
print_header "System Configuration"

# Check that Ubuntu Pro apt_news is disabled (silences apt advertisements)
if command -v pro >/dev/null 2>&1; then
    apt_news=$(pro config show 2>/dev/null | awk '$1=="apt_news" {print tolower($NF)}')
    if [ "$apt_news" = "false" ]; then
        print_row "Pro apt_news" "${GREEN}✓ Disabled${NC}" ""
    else
        print_row "Pro apt_news" "${YELLOW}~ Enabled${NC}" "apt advertisements shown"
        missing_items+=("pro-apt-news")
    fi

    # Check that apt-news / esm-cache services are masked (belt-and-suspenders)
    masked_count=0
    for svc in apt-news.service esm-cache.service; do
        load_state=$(systemctl show "$svc" --property=LoadState --value 2>/dev/null)
        [ "$load_state" = "masked" ] && masked_count=$((masked_count+1))
    done
    if [ "$masked_count" -eq 2 ]; then
        print_row "apt-news / esm-cache" "${GREEN}✓ Masked${NC}" ""
    else
        print_row "apt-news / esm-cache" "${YELLOW}~ Not masked${NC}" "may run during apt operations"
        missing_items+=("pro-mask-services")
    fi
fi

# --- Shell Configuration ---
print_header "Shell Configuration"

if grep -q "Custom Dotfiles Loader" "$HOME/.bashrc" 2>/dev/null; then
    print_row ".bashrc loader" "${GREEN}✓ Present${NC}" "Custom Dotfiles Loader"
else
    print_row ".bashrc loader" "${RED}x Missing${NC}" "Loader block not in ~/.bashrc"
    missing_items+=("bashrc-loader")
fi

# --- Machine Config (.setup.conf vs template) ---
print_header "Machine Config"

TEMPLATE_FILE="$DOTFILES_DIR/.setup.conf.template"
if [ -f "$TEMPLATE_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    conf_missing_keys=()
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        key="${line%%=*}"
        grep -q "^${key}=" "$CONFIG_FILE" || conf_missing_keys+=("$key")
    done < "$TEMPLATE_FILE"

    if [ ${#conf_missing_keys[@]} -eq 0 ]; then
        print_row ".setup.conf" "${GREEN}✓ Up to date${NC}" "all template keys present"
    else
        print_row ".setup.conf" "${YELLOW}~ Missing keys${NC}" "${conf_missing_keys[*]}"
        for k in "${conf_missing_keys[@]}"; do missing_items+=("conf-key-$k"); done
    fi
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
        # Subtrees excluded from stow (gemini/.stow-local-ignore) must never appear as folded links
        [[ "$relative" == *antigravity-cli* ]] && continue
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
        # Skip stow ignore lists (repo-only, never stowed)
        [[ "$(basename "$relative")" == .stow-local-ignore ]] && continue
        # Skip subtrees excluded from stow via gemini/.stow-local-ignore
        [[ "$relative" == *antigravity-cli* ]] && continue
        # Skip settings.json (deployed from template, not via stow)
        [[ "$(basename "$relative")" == settings.json ]] && continue
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
        print_row "$name" "${YELLOW}~ Not executable${NC}" ""
        missing_items+=("bin-exec")
    fi
done

# --- Global LLM Instructions ---
print_header "Global LLM Instructions"

GLOBAL_INSTRUCTIONS="$DOTFILES_DIR/agents/AGENTS.md"
check_symlink ".claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$GLOBAL_INSTRUCTIONS" "llm-global"
check_symlink ".codex/AGENTS.md" "$HOME/.codex/AGENTS.md" "$GLOBAL_INSTRUCTIONS" "llm-global"
check_symlink ".gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md" "$GLOBAL_INSTRUCTIONS" "llm-global"

# --- Claude Code Settings ---
# Only when Claude is enabled — a disabled machine has no Claude settings to check (the
# always-on ~/.claude/CLAUDE.md global-instructions symlink is validated separately above).
if [[ "$INSTALL_CLAUDE" == true ]]; then
print_header "Claude Code Configuration"

if [ -L "$HOME/.claude/settings.json" ]; then
    # Symlink detected — settings should be a copy, not a symlink
    target=$(readlink "$HOME/.claude/settings.json")
    print_row ".claude/settings.json" "${YELLOW}~ Is a symlink${NC}" "→ $target (should be a copy)"
    missing_items+=("claude-settings-symlink")
elif [ -f "$HOME/.claude/settings.json" ]; then
    # Check for required top-level keys (except model, which is user-configurable)
    local_settings="$HOME/.claude/settings.json"
    required_keys=("permissions" "hooks" "statusLine" "terminalTitleFromRename" "autoMemoryEnabled" "remoteControlAtStartup")
    missing_keys=()

    for key in "${required_keys[@]}"; do
        if ! jq -e ".$key" "$local_settings" >/dev/null 2>&1; then
            missing_keys+=("$key")
        fi
    done

    if [ ${#missing_keys[@]} -eq 0 ]; then
        print_row ".claude/settings.json" "${GREEN}✓ Complete${NC}" "all required keys present"
    else
        print_row ".claude/settings.json" "${YELLOW}~ Missing keys${NC}" "${missing_keys[*]}"
        missing_items+=("claude-settings")
    fi

    # Check for untracked permissions
    untracked_cmds=$(jq -r -s '([.[0].permissions.allow[]?] - [.[1].permissions.allow[]?]) | if length > 0 then join(", ") else empty end' "$local_settings" "$DOTFILES_DIR/claude/.claude/settings.json" 2>/dev/null)
    if [ -n "$untracked_cmds" ]; then
        print_row ".claude/settings.json" "${YELLOW}~ Untracked allows${NC}" "+ $untracked_cmds"
        missing_items+=("claude-untracked-allows")
    fi

    # Check the reverse: template allows missing locally (forward-sync gap)
    behind_cmds=$(jq -r -s '([.[1].permissions.allow[]?] - [.[0].permissions.allow[]?]) | if length > 0 then join(", ") else empty end' "$local_settings" "$DOTFILES_DIR/claude/.claude/settings.json" 2>/dev/null)
    if [ -n "$behind_cmds" ]; then
        print_row ".claude/settings.json" "${YELLOW}~ Behind template${NC}" "- $behind_cmds"
        missing_items+=("claude-template-allows")
    fi
else
    print_row ".claude/settings.json" "${RED}x Missing${NC}" "run setup.sh to create from template"
    missing_items+=("claude-settings")
fi
fi

# --- Antigravity Configuration ---
# Only when agy is enabled — a disabled machine has no agy config to check (the gemini stow
# package is likewise skipped via STOW_SKIP in setup.sh).
if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
print_header "Antigravity Configuration"

AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
if [ -L "$HOME/.gemini/antigravity-cli" ]; then
    # Folded stow symlink: agy writes runtime state (settings, oauth token, logs) into the repo
    print_row "agy config dir" "${RED}x Stow symlink${NC}" "agy writes into the repo — run setup.sh to unfold"
    missing_items+=("agy-settings")
elif [ -L "$AGY_SETTINGS" ]; then
    target=$(readlink "$AGY_SETTINGS")
    print_row "agy settings.json" "${YELLOW}~ Is a symlink${NC}" "→ $target (should be a copy)"
    missing_items+=("agy-settings-symlink")
elif [ -f "$AGY_SETTINGS" ]; then
    required_keys=("permissions" "statusLine" "hooks" "title")
    missing_keys=()

    for key in "${required_keys[@]}"; do
        if ! jq -e ".$key" "$AGY_SETTINGS" >/dev/null 2>&1; then
            missing_keys+=("$key")
        fi
    done

    if [ ${#missing_keys[@]} -eq 0 ]; then
        print_row "agy settings.json" "${GREEN}✓ Complete${NC}" "all required keys present"
    else
        print_row "agy settings.json" "${YELLOW}~ Missing keys${NC}" "${missing_keys[*]}"
        missing_items+=("agy-settings")
    fi

    # Check for untracked permissions
    untracked_cmds=$(jq -r -s '([.[0].permissions.allow[]?] - [.[1].permissions.allow[]?]) | if length > 0 then join(", ") else empty end' "$AGY_SETTINGS" "$DOTFILES_DIR/gemini/.gemini/antigravity-cli/settings.json" 2>/dev/null)
    if [ -n "$untracked_cmds" ]; then
        print_row "agy settings.json" "${YELLOW}~ Untracked allows${NC}" "+ $untracked_cmds"
        missing_items+=("agy-untracked-allows")
    fi

    # Check the reverse: template allows missing locally (forward-sync gap)
    behind_cmds=$(jq -r -s '([.[1].permissions.allow[]?] - [.[0].permissions.allow[]?]) | if length > 0 then join(", ") else empty end' "$AGY_SETTINGS" "$DOTFILES_DIR/gemini/.gemini/antigravity-cli/settings.json" 2>/dev/null)
    if [ -n "$behind_cmds" ]; then
        print_row "agy settings.json" "${YELLOW}~ Behind template${NC}" "- $behind_cmds"
        missing_items+=("agy-template-allows")
    fi
else
    print_row "agy settings.json" "${RED}x Missing${NC}" "run setup.sh to create/merge from template"
    missing_items+=("agy-settings")
fi
fi

# --- SSH ---
print_header "SSH"

if [ -f "$HOME/.ssh/id_ed25519" ]; then
    print_row "SSH private key" "${GREEN}✓ Decrypted${NC}" "~/.ssh/id_ed25519"
elif [ -f "$HOME/.ssh/id_ed25519.age" ]; then
    print_row "SSH private key" "${YELLOW}~ Encrypted${NC}" "Needs age decryption"
    missing_items+=("ssh-decrypt")
else
    print_row "SSH private key" "${RED}x Missing${NC}" "No key or .age file"
fi

# Verify .age file matches the repo copy (same encrypted key on all machines)
if [ -f "$HOME/.ssh/id_ed25519.age" ] && [ -f "$DOTFILES_DIR/ssh/.ssh/id_ed25519.age" ]; then
    deployed_sum=$(sha256sum "$HOME/.ssh/id_ed25519.age" | cut -d' ' -f1)
    repo_sum=$(sha256sum "$DOTFILES_DIR/ssh/.ssh/id_ed25519.age" | cut -d' ' -f1)
    if [ "$deployed_sum" = "$repo_sum" ]; then
        print_row ".age matches repo" "${GREEN}✓ Match${NC}" "${deployed_sum:0:12}…"
    else
        print_row ".age matches repo" "${RED}x Mismatch${NC}" "Deployed .age differs from repo"
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
        print_row "Public key matches private" "${RED}x Mismatch${NC}" "Regenerate with ssh-keygen -y"
        missing_items+=("ssh-regen-pub")
    fi
elif [ -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
    print_row "Public key" "${YELLOW}~ Missing${NC}" "Regenerate from private key"
    missing_items+=("ssh-regen-pub")
fi

check_perms ".ssh/ permissions" "$HOME/.ssh" "700" "ssh-dir-perms"
check_perms "Private key permissions" "$HOME/.ssh/id_ed25519" "600" "ssh-key-perms"
check_perms ".ssh/config permissions" "$HOME/.ssh/config" "644" "ssh-config-perms"

# --- SSH Agent Relay (YubiKey) — WSL relays the Windows ssh-agent over a socket ---
# Diagnostic only: any failure points at wsl_ssh_agent.sh, the idempotent fix.
if [[ "$SSH_YUBIKEY" == true ]]; then
    print_header "SSH Agent Relay (YubiKey)"
    relay_env="$HOME/.config/dotfiles/ssh_agent.env"

    # socat (the WSL-side relay tool)
    if command -v socat >/dev/null 2>&1; then
        print_row "socat" "${GREEN}✓ Installed${NC}" ""
    else
        print_row "socat" "${RED}x Missing${NC}" ""
        missing_items+=("ssh-yubikey-relay")
    fi

    # npiperelay.exe (recorded in the generated env file)
    npiperelay_path=""
    [ -f "$relay_env" ] && npiperelay_path=$(. "$relay_env" 2>/dev/null; echo "${NPIPERELAY:-}")
    if [ -n "$npiperelay_path" ] && [ -e "$npiperelay_path" ]; then
        print_row "npiperelay.exe" "${GREEN}✓ Present${NC}" "${npiperelay_path}"
    else
        print_row "npiperelay.exe" "${RED}x Missing${NC}" "not provisioned (no env file or binary)"
        missing_items+=("ssh-yubikey-relay")
    fi

    # Relay live: SSH_AUTH_SOCK is a live socket and the agent serves the sk key
    if [ -S "${SSH_AUTH_SOCK:-}" ] && ssh-add -l 2>/dev/null | grep -q 'ED25519-SK\|ECDSA-SK'; then
        print_row "Agent relay" "${GREEN}✓ Live${NC}" "sk key reachable via SSH_AUTH_SOCK"
    else
        print_row "Agent relay" "${RED}x Down${NC}" "no sk key via SSH_AUTH_SOCK"
        missing_items+=("ssh-yubikey-relay")
    fi
fi

# --- WSL config ---
# Regression guard: a [boot] command that pins a static IPv6 address blackholes under
# mirrored networking (retired 2026-06-11). Its presence is now the fault, not its absence.
if grep -qi microsoft /proc/version 2>/dev/null; then
    print_header "WSL Configuration"
    if grep -qE '^[[:space:]]*command[[:space:]]*=.*ip -6 addr' /etc/wsl.conf 2>/dev/null; then
        print_row "IPv6 addr pin" "${RED}x Present${NC}" "blackholes under mirrored networking — remove it (see check_ipv6.sh)"
        missing_items+=("wsl-ipv6-pin")
    else
        print_row "IPv6 addr pin" "${GREEN}✓ None${NC}" "no static pin to blackhole"
    fi
fi

# --- Git ---
print_header "Git Configuration"

git_user=$(git config --global user.name 2>/dev/null || echo "")
git_email=$(git config --global user.email 2>/dev/null || echo "")
if [ -n "$git_user" ] && [ -n "$git_email" ]; then
    print_row "User identity" "${GREEN}✓ Set${NC}" "$git_user <$git_email>"
else
    print_row "User identity" "${YELLOW}~ Incomplete${NC}" "name='$git_user' email='$git_email'"
fi

# --- APT Packages ---
print_header "APT Packages"

for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ver=$(dpkg -s "$pkg" 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "$pkg" "${GREEN}✓ Installed${NC}" "$ver"
    else
        print_row "$pkg" "${RED}x Missing${NC}" ""
        missing_items+=("apt-$pkg")
    fi
done

# Check locally-specific packages from .setup.conf
if [ -n "$MORE_APT_PACKAGES" ]; then
    read -ra more_pkgs <<< "$MORE_APT_PACKAGES"
    for pkg in "${more_pkgs[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ver=$(dpkg -s "$pkg" 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
            print_row "$pkg (local)" "${GREEN}✓ Installed${NC}" "$ver"
        else
            print_row "$pkg (local)" "${RED}x Missing${NC}" ""
            missing_items+=("apt-$pkg")
        fi
    done
fi

# Check glow (from Charm apt repo)
if dpkg -s glow >/dev/null 2>&1; then
    ver=$(dpkg -s glow 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
    print_row "glow (charm)" "${GREEN}✓ Installed${NC}" "$ver"
else
    print_row "glow (charm)" "${RED}x Missing${NC}" ""
    missing_items+=("install-glow")
fi

# Check gh (GitHub CLI from GitHub apt repo)
if dpkg -s gh >/dev/null 2>&1; then
    ver=$(dpkg -s gh 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
    print_row "gh (github cli)" "${GREEN}✓ Installed${NC}" "$ver"
else
    print_row "gh (github cli)" "${RED}x Missing${NC}" ""
    missing_items+=("install-gh")
fi

# --- Dev Toolchains ---
print_header "Dev Toolchains"

if [[ "$INSTALL_RUST" == true ]]; then
    if command -v rustup >/dev/null 2>&1; then
        rust_ver=$(rustc --version 2>/dev/null | cut -d' ' -f2)
        print_row "Rust (rustup)" "${GREEN}✓ Installed${NC}" "$rust_ver"
    else
        print_row "Rust (rustup)" "${RED}x Missing${NC}" ""
        missing_items+=("install-rust")
    fi
fi

if [[ "$INSTALL_NODE" == true ]]; then
    # Ensure fnm is on PATH for this check
    [[ -d "$HOME/.local/share/fnm" ]] && export PATH="$HOME/.local/share/fnm:$PATH" && eval "$(fnm env --shell bash 2>/dev/null)" 2>/dev/null
    if command -v fnm >/dev/null 2>&1; then
        print_row "fnm" "${GREEN}✓ Installed${NC}" "$(fnm --version 2>/dev/null)"
    else
        print_row "fnm" "${RED}x Missing${NC}" ""
        missing_items+=("install-fnm")
    fi
    # Node and npm both come from fnm — must be present and runnable
    if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1; then
        print_row "Node" "${GREEN}✓ Installed${NC}" "$(node --version 2>/dev/null)"
    else
        print_row "Node" "${RED}x Missing${NC}" "no active Node version"
        missing_items+=("install-node")
    fi
    if command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
        print_row "npm" "${GREEN}✓ Installed${NC}" "$(npm --version 2>/dev/null)"
    else
        print_row "npm" "${RED}x Missing${NC}" ""
        missing_items+=("install-node")
    fi
    if command -v vite >/dev/null 2>&1; then
        vite_ver=$(vite --version 2>/dev/null | tail -1)
        print_row "vite" "${GREEN}✓ Installed${NC}" "$vite_ver"
    else
        print_row "vite" "${RED}x Missing${NC}" ""
        missing_items+=("install-vite")
    fi
    if command -v pnpm >/dev/null 2>&1 && pnpm --version >/dev/null 2>&1; then
        print_row "pnpm" "${GREEN}✓ Installed${NC}" "$(pnpm --version 2>/dev/null)"
    else
        print_row "pnpm" "${RED}x Missing${NC}" ""
        missing_items+=("install-pnpm")
    fi
fi

if [[ "$INSTALL_ICP" == true ]]; then
    if command -v dfx >/dev/null 2>&1; then
        dfx_ver=$(dfx --version 2>/dev/null || echo "unknown")
        print_row "dfx (dfxvm)" "${GREEN}✓ Installed${NC}" "$dfx_ver"
    else
        print_row "dfx (dfxvm)" "${RED}x Missing${NC}" ""
        missing_items+=("install-icp")
    fi
    if command -v ic-admin >/dev/null 2>&1; then
        print_row "ic-admin" "${GREEN}✓ Installed${NC}" ""
    else
        print_row "ic-admin" "${RED}x Missing${NC}" ""
        missing_items+=("install-ic-admin")
    fi
fi

if [[ "$INSTALL_PYTHON" == true ]]; then
    if command -v python3 >/dev/null 2>&1 && dpkg -s python3-pip >/dev/null 2>&1 && dpkg -s python3-venv >/dev/null 2>&1; then
        py_ver=$(python3 --version 2>/dev/null | cut -d' ' -f2)
        print_row "Python + pip + venv" "${GREEN}✓ Installed${NC}" "$py_ver"
    else
        print_row "Python + pip + venv" "${RED}x Missing${NC}" ""
        missing_items+=("install-python")
    fi
fi

# For now either Firefox toggle installs & checks both the latest and ESR builds.
if [[ "$INSTALL_FF" == true || "$INSTALL_FF_ESR" == true ]]; then
    ff_ver=$(dpkg-query -W -f='${Version}' firefox 2>/dev/null)
    if [ -z "$ff_ver" ]; then
        print_row "Firefox (latest)" "${RED}x Missing${NC}" ""
        missing_items+=("install-ff")
    elif printf '%s' "$ff_ver" | grep -q snap; then
        print_row "Firefox (latest)" "${RED}x Snap stub${NC}" "$ff_ver (want Mozilla deb)"
        missing_items+=("install-ff")
    else
        print_row "Firefox (latest)" "${GREEN}✓ Installed${NC}" "$ff_ver"
    fi
    if dpkg -s firefox-esr >/dev/null 2>&1; then
        ver=$(dpkg -s firefox-esr 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "Firefox ESR" "${GREEN}✓ Installed${NC}" "$ver"
    else
        print_row "Firefox ESR" "${RED}x Missing${NC}" ""
        missing_items+=("install-ffesr")
    fi
fi

if [[ "$INSTALL_DOCKER" == true ]]; then
    if dpkg -s docker-compose-v2 >/dev/null 2>&1; then
        dc_ver=$(dpkg -s docker-compose-v2 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
        print_row "Docker Compose" "${GREEN}✓ Installed${NC}" "$dc_ver"
    else
        print_row "Docker Compose" "${RED}x Missing${NC}" ""
        missing_items+=("install-docker")
    fi
    if id -nG "$USER" | grep -qw docker; then
        print_row "docker group" "${GREEN}✓ Member${NC}" "$USER"
    else
        print_row "docker group" "${RED}x Not a member${NC}" "$USER"
        missing_items+=("docker-group")
    fi
fi

# --- LLM Agents ---
if [[ "$INSTALL_CLAUDE" == true ]] || [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
    print_header "LLM Agents"
fi

if [[ "$INSTALL_CLAUDE" == true ]]; then
    if command -v claude >/dev/null 2>&1; then
        claude_ver=$(claude --version 2>/dev/null || echo "unknown")
        print_row "Claude Code CLI" "${GREEN}✓ Installed${NC}" "$claude_ver"
    else
        print_row "Claude Code CLI" "${RED}x Missing${NC}" ""
        missing_items+=("claude-cli")
    fi
fi

if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
    if command -v agy >/dev/null 2>&1; then
        agy_ver=$(agy --version 2>/dev/null || echo "unknown")
        print_row "Antigravity CLI" "${GREEN}✓ Installed${NC}" "$agy_ver"
    else
        print_row "Antigravity CLI" "${RED}x Missing${NC}" ""
        missing_items+=("antigravity-cli")
    fi
fi

# Migration: Gemini CLI is retired (stops serving 2026-06-18), replaced by Antigravity CLI.
# Flag a leftover `gemini` binary or an obsolete INSTALL_GEMINI_CLI key in .setup.conf.
gemini_leftover=false
command -v gemini >/dev/null 2>&1 && gemini_leftover=true
grep -q '^INSTALL_GEMINI_CLI=' "$CONFIG_FILE" 2>/dev/null && gemini_leftover=true
if $gemini_leftover; then
    [[ "$INSTALL_CLAUDE" == true ]] || [[ "$INSTALL_ANTIGRAVITY" == true ]] || print_header "LLM Agents"
    print_row "Gemini CLI" "${YELLOW}~ Retired${NC}" "migrate INSTALL_GEMINI_CLI → INSTALL_ANTIGRAVITY"
    missing_items+=("gemini-migrate")
fi

# --- Project Agent Files (~/dotfiles CLAUDE/AGENTS/GEMINI symlinks) ---
# The dotfiles repo follows its own validate_project.sh contract: each agent file is a
# symlink to the repo-root CONTRIBUTING.md. Checked natively here (rather than shelling
# out to validate_project.sh, whose differently-styled output broke the flow) — the fix
# is a single `bash setup.sh`, which recreates any missing links.
print_header "Project Agent Files (~/dotfiles)"
PROJECT_CONTRIBUTING="$DOTFILES_DIR/CONTRIBUTING.md"
for agent_file in CLAUDE.md AGENTS.md; do
    check_symlink "$agent_file" "$DOTFILES_DIR/$agent_file" "$PROJECT_CONTRIBUTING" "project-agent-symlinks"
done

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

# Split findings: setup.sh is idempotent and remediates almost everything it provisions,
# so all such items collapse into a single "re-run setup.sh" fix. Targeted commands remain
# only for what setup.sh cannot do (repo clone/sync, YubiKey relay, Claude settings deploy).
setup_items=()
manual_items=()
for item in "${unique_items[@]}"; do
    case "$item" in
        prereq-*|pro-apt-news|pro-mask-services|dotfiles-ssh-remote|conf-key-*|stow-*|bashrc-loader|ssh-decrypt|ssh-regen-pub|ssh-dir-perms|ssh-key-perms|ssh-config-perms|llm-global|project-agent-symlinks|bin-exec|apt-*|install-*|docker-group|claude-cli|antigravity-cli|agy-settings|gemini-migrate|claude-untracked-allows|agy-untracked-allows|claude-template-allows|agy-template-allows)
            setup_items+=("$item") ;;
        *)
            manual_items+=("$item") ;;
    esac
done

# 1. Dotfiles repo first — every other fix assumes an up-to-date clone
for item in "${manual_items[@]+${manual_items[@]}}"; do
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

# 2. One idempotent setup.sh run covers everything it provisions
if [ ${#setup_items[@]} -gt 0 ]; then
    printf "\n  ${CYAN}# Re-run setup.sh (idempotent) — fixes: %s${NC}\n" "${setup_items[*]}"
    echo "  ( cd ~/dotfiles && bash setup.sh )"
fi

# 3. Targeted fixes for what setup.sh can't do
for item in "${manual_items[@]+${manual_items[@]}}"; do
    case "$item" in
        ssh-yubikey-relay)
            printf "\n  ${CYAN}# Provision/repair the Windows ssh-agent (YubiKey) relay${NC}\n"
            echo "  wsl_ssh_agent.sh"
            ;;
        wsl-ipv6-pin)
            printf "\n  ${CYAN}# Remove the static IPv6 pin from /etc/wsl.conf, then: wsl.exe --shutdown${NC}\n"
            echo "  sudo sed -i '/ip -6 addr/d' /etc/wsl.conf  # then reopen the shell"
            ;;
        claude-settings)
            printf "\n  ${CYAN}# Deploy Claude Code settings${NC}\n"
            echo "  cp ~/dotfiles/claude/.claude/settings.json ~/.claude/settings.json"
            ;;
        claude-settings-symlink)
            printf "\n  ${CYAN}# Convert settings.json from symlink to copy${NC}\n"
            echo "  rm ~/.claude/settings.json && cp ~/dotfiles/claude/.claude/settings.json ~/.claude/settings.json"
            ;;
        agy-settings-symlink)
            printf "\n  ${CYAN}# Convert agy settings.json from symlink to local file${NC}\n"
            echo "  rm ~/.gemini/antigravity-cli/settings.json && ( cd ~/dotfiles && bash setup.sh )"
            ;;
    esac
done

echo ""
exit 1
