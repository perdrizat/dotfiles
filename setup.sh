#!/bin/bash
# setup.sh — Bootstrap a fresh machine with dotfiles
#
# Must be self-contained: curl-piped before the repo exists.
# validate_setup.sh sources this file for the shared variables below.

DOTFILES_DIR="$HOME/dotfiles"

# --- Shared variables (also used by validate_setup.sh) ---
PREREQS=(git curl stow age unzip)
APT_PACKAGES=(build-essential jq)
STOW_SKIP=(.git agents claude)
DOTFILES_SSH_REMOTE="git@github.com:perdrizat/dotfiles.git"

# Install the setup prerequisites if missing (apt update only in -update mode)
_need_prereqs=false
for _cmd in "${PREREQS[@]}"; do command -v "$_cmd" >/dev/null 2>&1 || { _need_prereqs=true; break; }; done
$_need_prereqs && echo "Installing prerequisites: ${PREREQS[*]}" && sudo apt-get -qq update && sudo apt-get -qq install -y "${PREREQS[@]}"

# Clone the repo if we aren't already in it
if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Cloning dotfiles..."
    cd "$HOME" && git clone https://github.com/perdrizat/dotfiles.git
    cp "$DOTFILES_DIR/.setup.conf.template" "$DOTFILES_DIR/.setup.conf"
    echo "Customize $DOTFILES_DIR/.setup.conf, then run: bash ~/dotfiles/setup.sh"
fi
cd "$DOTFILES_DIR"

# --- Prepare machine-specific config ---
# Path is overridable via DOTFILES_CONFIG so tests can drive toggles from a temp config.
CONFIG_FILE="${DOTFILES_CONFIG:-$DOTFILES_DIR/.setup.conf}"
[ ! -f "$CONFIG_FILE" ] && cp "$DOTFILES_DIR/.setup.conf.template" "$CONFIG_FILE"

#############################################################################################
#                                                                                           #
# you can stop copy-pasting and just run the dotfiles/setup.sh script to continue from here #
#                                                                                           #
#############################################################################################

# Self-heal the machine config before sourcing it — executed runs only, so that
# validate_setup.sh (which sources this file for shared variables) stays read-only.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Migrate the retired Gemini CLI toggle, preserving its value
    if grep -q '^INSTALL_GEMINI_CLI=' "$CONFIG_FILE"; then
        _gem=$(grep '^INSTALL_GEMINI_CLI=' "$CONFIG_FILE" | tail -1 | cut -d= -f2 | awk '{print $1}')
        _gem=${_gem:-false}
        sed -i '/^INSTALL_GEMINI_CLI=/d' "$CONFIG_FILE"
        if grep -q '^INSTALL_ANTIGRAVITY=' "$CONFIG_FILE"; then
            [ "$_gem" = "true" ] && sed -i 's/^INSTALL_ANTIGRAVITY=.*/INSTALL_ANTIGRAVITY=true/' "$CONFIG_FILE"
        else
            echo "INSTALL_ANTIGRAVITY=$_gem" >> "$CONFIG_FILE"
        fi
        echo "Migrated config: INSTALL_GEMINI_CLI → INSTALL_ANTIGRAVITY=$_gem"
    fi
    # Append template keys missing from the machine config (with their defaults)
    while IFS= read -r _line; do
        [[ "$_line" =~ ^[[:space:]]*# || -z "${_line// }" ]] && continue
        _key="${_line%%=*}"
        if ! grep -q "^${_key}=" "$CONFIG_FILE"; then
            echo "$_line" >> "$CONFIG_FILE"
            echo "Added missing config key: $_key"
        fi
    done < "$DOTFILES_DIR/.setup.conf.template"
fi

# Defaults — overridden by .setup.conf; keeps all toggles bound even on partial configs
INSTALL_RUST=false; INSTALL_NODE=false; INSTALL_ICP=false; INSTALL_PYTHON=false
INSTALL_DOCKER=false; INSTALL_FF=false; INSTALL_FF_ESR=false; INSTALL_CLAUDE=false; INSTALL_ANTIGRAVITY=false
SSH_YUBIKEY=false
MORE_APT_PACKAGES=""
source "$CONFIG_FILE"

# When sourced by validate_setup.sh, stop here
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

# Disable Ubuntu Pro apt advertisements (keep the package, just silence it)
if command -v pro >/dev/null 2>&1; then
    sudo pro config set apt_news=false 2>/dev/null || true
    sudo systemctl mask apt-news.service esm-cache.service 2>/dev/null || true
fi

# Create the sourcing snippet
# We use a heredoc to define what needs to be added to .bashrc
BASHDOT=$(cat <<EOF

# --- Custom Dotfiles Loader ---
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
if [ -f ~/.bash_extra ]; then
    . ~/.bash_extra
fi
EOF
)

# Inject into .bashrc (carefully)
# We grep for a unique string to avoid double-appending if you run the script twice
if ! grep -q "Custom Dotfiles Loader" ~/.bashrc; then
    echo "Appending custom loader to ~/.bashrc..."
    echo "$BASHDOT" >> ~/.bashrc
else
    echo "Custom loader already exists in .bashrc, skipping..."
fi

# Auto-discover and link stow packages
echo "Linking dotfiles with Stow..."
mkdir -p ~/.claude  # must exist as real dir before stow (Claude Code writes other files here)
mkdir -p ~/.ssh && chmod 700 ~/.ssh # prevent stow from folding .ssh into a symlink (generated files must not land in repo)
mkdir -p ~/.gemini/config  # real dir so stow folds skills at ~/.gemini/config/skills (agy writes other config here)
for pkg_dir in "$DOTFILES_DIR"/*/; do
    pkg=$(basename "$pkg_dir")
    skip=false
    for s in "${STOW_SKIP[@]}"; do
        [[ "$pkg" == "$s" ]] && skip=true && break
    done
    $skip && continue
    stow --adopt "$pkg"
done

# Ensure ~/bin scripts are executable
chmod +x "$HOME"/bin/*.sh 2>/dev/null || true

# Deploy settings.json from template (not via stow to allow local customization)
if [ ! -f ~/.claude/settings.json ]; then
    cp "$DOTFILES_DIR/claude/.claude/settings.json" ~/.claude/settings.json
    echo "Deployed settings.json template to ~/.claude/settings.json"
fi

# Global LLM instructions — single source of truth symlinked into each agent's config dir
GLOBAL_INSTRUCTIONS="$DOTFILES_DIR/agents/AGENTS.md"
mkdir -p ~/.claude ~/.codex ~/.gemini
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.claude/CLAUDE.md
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.codex/AGENTS.md
# Antigravity (agy) reads its global instructions from ~/.gemini/GEMINI.md only
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.gemini/GEMINI.md

# Project-level agent symlinks at the dotfiles repo root (per validate_project.sh contract).
# Created only when absent so we never replace a user's customization.
for _agent in CLAUDE.md AGENTS.md; do
    if [ ! -e "$DOTFILES_DIR/$_agent" ] && [ ! -L "$DOTFILES_DIR/$_agent" ]; then
        ln -s CONTRIBUTING.md "$DOTFILES_DIR/$_agent"
    fi
done

# Remove retired symlinks from earlier layouts (idempotent; only ever removes symlinks, never real files).
# stow doesn't prune links whose source we've since moved/renamed, so clean them explicitly:
#   ~/.gemini/AGENTS.md          — global agy config is now GEMINI.md
#   ~/.gemini/skills[.inactive]  — skills moved under ~/.gemini/config/
#   repo-root GEMINI.md          — project agent files are CLAUDE.md / AGENTS.md only
for _retired in ~/.gemini/AGENTS.md ~/.gemini/skills ~/.gemini/skills.inactive "$DOTFILES_DIR/GEMINI.md"; do
    [ -L "$_retired" ] && rm -f "$_retired"
done

# sort out SSH
# Decrypt SSH key if it doesn't already exist
if [ -f ~/.ssh/id_ed25519.age ] && [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Decrypting SSH key..."
    touch ~/.ssh/id_ed25519 && chmod 600 ~/.ssh/id_ed25519
    age --decrypt -o ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.age
fi
# Regenerate public key from private key (pub key is not tracked in git)
if [ -f ~/.ssh/id_ed25519 ]; then
    echo "Regenerating public key from private key..."
    ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
fi
echo "Fixing remaining SSH permissions..."
chmod 700 ~/.ssh
[ -f ~/.ssh/id_ed25519 ] && chmod 600 ~/.ssh/id_ed25519
[ -f ~/.ssh/config ] && chmod 644 ~/.ssh/config

# Switch dotfiles remote from HTTPS to SSH now that keys are in place
current_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)
if [ "$current_remote" != "$DOTFILES_SSH_REMOTE" ]; then
    echo "Switching dotfiles remote to SSH..."
    git -C "$DOTFILES_DIR" remote set-url origin "$DOTFILES_SSH_REMOTE"
fi

# --- WSL config (host-specific) ---
if [ "$(hostname)" = "bequiet" ]; then
    WSL_BOOT='[boot]
command = "bash -c '"'"'ip -6 addr change 2a02:16a:b205:0:3e6a:d2ff:fe7a:6a81/64 dev eth0 preferred_lft forever valid_lft forever; ip -6 addr del 2a02:16a:b205:1:3e6a:d2ff:fe7a:6a81/64 dev eth0 2>/dev/null; true'"'"'"'
    if ! grep -q '2a02:16a:b205:0:3e6a:d2ff:fe7a:6a81' /etc/wsl.conf 2>/dev/null; then
        echo "Adding IPv6 boot command to /etc/wsl.conf..."
        printf '\n%s\n' "$WSL_BOOT" | sudo tee -a /etc/wsl.conf >/dev/null
    fi
fi

# --- System packages ---
# (apt update only in -update mode to avoid slowdown; apt is fast enough without it for initial setup)

# Collect apt packages based on toggles and config
apt_install=("${APT_PACKAGES[@]}")
[[ "$INSTALL_PYTHON" == true ]] && apt_install+=(python3 python3-pip python3-venv)
[[ "$INSTALL_DOCKER" == true ]] && apt_install+=(docker-compose-v2)
[[ "$SSH_YUBIKEY" == true ]] && apt_install+=(socat)
# Add machine-specific packages from config
if [ -n "$MORE_APT_PACKAGES" ]; then
    read -ra more_pkgs <<< "$MORE_APT_PACKAGES"
    apt_install+=("${more_pkgs[@]}")
fi

dpkg -s "${apt_install[@]}" >/dev/null 2>&1 || { echo "Installing APT packages: ${apt_install[*]}" && sudo apt-get -qq install -y "${apt_install[@]}"; }

# --- Glow (markdown pager from Charm apt repo) ---
if ! command -v glow >/dev/null 2>&1; then
    echo "Setting up Charm apt repo for glow..."
    sudo mkdir -p /etc/apt/keyrings
    [ -f /etc/apt/keyrings/charm.gpg ] || curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    [ -f /etc/apt/sources.list.d/charm.list ] || echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt-get -qq update && sudo apt-get -qq install -y glow  # apt update needed: new repo just added
fi

# --- GitHub CLI (from GitHub apt repo) ---
if ! command -v gh >/dev/null 2>&1; then
    echo "Setting up GitHub apt repo for gh..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    [ -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ] || curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    [ -f /etc/apt/sources.list.d/github-cli.list ] || echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get -qq update && sudo apt-get -qq install -y gh  # apt update needed: new repo just added
fi

# --- Firefox (Mozilla apt repo) ---
# For now either toggle installs both the latest and ESR builds from the Mozilla repo.
if [[ "$INSTALL_FF" == true || "$INSTALL_FF_ESR" == true ]]; then
    ff_pkgs=()
    dpkg -s firefox     >/dev/null 2>&1 || ff_pkgs+=(firefox)
    dpkg -s firefox-esr >/dev/null 2>&1 || ff_pkgs+=(firefox-esr)
    if [ ${#ff_pkgs[@]} -gt 0 ]; then
        echo "Setting up Mozilla apt repo for Firefox: ${ff_pkgs[*]}..."
        sudo install -d -m 0755 /etc/apt/keyrings
        [ -f /etc/apt/keyrings/packages.mozilla.org.asc ] || curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
        [ -f /etc/apt/sources.list.d/mozilla.list ] || echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
        [ -f /etc/apt/preferences.d/mozilla ] || printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' | sudo tee /etc/apt/preferences.d/mozilla
        sudo apt-get -qq update && sudo apt-get -qq install -y "${ff_pkgs[@]}"
    fi
fi

# Add current user to docker group (requires logout/login to take effect)
if [[ "$INSTALL_DOCKER" == true ]] && ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
fi

# --- Dev toolchains (curl-based, idempotent) ---

if [[ "$INSTALL_RUST" == true ]] && ! command -v rustup >/dev/null 2>&1; then
    echo "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable -c clippy,rustfmt
    source "$HOME/.cargo/env"
fi

if [[ "$INSTALL_NODE" == true ]]; then
    if ! command -v fnm >/dev/null 2>&1; then
        echo "Installing fnm (Fast Node Manager)..."
        curl -fsSL https://fnm.vercel.app/install | bash
    fi
    # Make fnm available in this script (bashrc guard blocks source in non-interactive shells)
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env --shell bash)"
    # Install LTS only when no Node is present yet; upgrades happen via `validate_setup.sh -u`
    if ! fnm ls 2>/dev/null | grep -qE 'v[0-9]+\.'; then
        echo "Installing Node LTS via fnm..."
        fnm install --lts
    fi
    # Install only the global npm tools that are missing
    node_globals_missing=()
    command -v vite >/dev/null 2>&1 || node_globals_missing+=(vite)
    command -v pnpm >/dev/null 2>&1 || node_globals_missing+=(pnpm)
    if [ ${#node_globals_missing[@]} -gt 0 ]; then
        echo "Installing global npm tools: ${node_globals_missing[*]}"
        npm install -g "${node_globals_missing[@]}"
    fi
    mkdir -p ~/.local/share/bash-completion/completions
    fnm completions --shell bash > ~/.local/share/bash-completion/completions/fnm
fi

if [[ "$INSTALL_ICP" == true ]]; then
    if ! command -v dfxvm >/dev/null 2>&1; then
        echo "Installing dfxvm (DFINITY SDK version manager)..."
        sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
    fi
    if ! command -v ic-admin >/dev/null 2>&1; then
        echo "Installing ic-admin..."
        mkdir -p ~/.local/bin
        curl -L "https://github.com/dfinity/ic/releases/latest/download/ic-admin-x86_64-linux.gz" -o - | gunzip > ~/.local/bin/ic-admin && chmod 0755 ~/.local/bin/ic-admin
    fi
fi

# --- LLM agents ---
if [[ "$INSTALL_CLAUDE" == true ]] && ! command -v claude >/dev/null 2>&1; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
    if ! command -v agy >/dev/null 2>&1; then
        echo "Installing Antigravity CLI..."
        curl -fsSL https://antigravity.google/cli/install.sh | bash
    fi
    # Deploy/merge agy settings
    mkdir -p ~/.gemini/antigravity-cli
    AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
    AGY_TEMPLATE="$DOTFILES_DIR/gemini/.gemini/antigravity-cli/settings.json"
    if [[ -f "$AGY_SETTINGS" ]]; then
        jq -s '.[0] * {statusLine: .[1].statusLine, hooks: .[1].hooks, permissions: {allow: ((.[0].permissions.allow // []) + .[1].permissions.allow | unique)}}' "$AGY_SETTINGS" "$AGY_TEMPLATE" > "${AGY_SETTINGS}.tmp" && mv "${AGY_SETTINGS}.tmp" "$AGY_SETTINGS"
        echo "Merged settings.json template into ~/.gemini/antigravity-cli/settings.json"
    else
        cp "$AGY_TEMPLATE" "$AGY_SETTINGS"
        echo "Deployed settings.json template to ~/.gemini/antigravity-cli/settings.json"
    fi
fi

# Uninstall the retired Gemini CLI (replaced by Antigravity; stops serving 2026-06-18)
if command -v gemini >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    echo "Uninstalling retired Gemini CLI..."
    npm uninstall -g @google/gemini-cli
fi

# --- WSL ssh-agent relay (YubiKey) ---
# Idempotent; only prompts (UAC / YubiKey touch) for pieces that are missing.
if [[ "$SSH_YUBIKEY" == true ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Configuring Windows ssh-agent (YubiKey) relay..."
    bash "$DOTFILES_DIR/bin/bin/wsl_ssh_agent.sh" || echo "wsl_ssh_agent.sh reported issues — run it manually to finish."
fi

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
echo ""
echo "To update packages and toolchains, run:"
echo "  validate_setup.sh -u"
