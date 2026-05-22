#!/bin/bash
# setup.sh — Bootstrap a fresh machine with dotfiles
#
# Must be self-contained: curl-piped before the repo exists.
# validate_setup.sh sources this file for the shared variables below.

DOTFILES_DIR="$HOME/dotfiles"

# --- Shared variables (also used by validate_setup.sh) ---
PREREQS=(git curl stow age unzip)
APT_PACKAGES=(build-essential jq)
STOW_SKIP=(.git agent claude)
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
CONFIG_FILE="$DOTFILES_DIR/.setup.conf"
[ ! -f "$CONFIG_FILE" ] && cp "$DOTFILES_DIR/.setup.conf.template" "$CONFIG_FILE"

#############################################################################################
#                                                                                           #
# you can stop copy-pasting and just run the dotfiles/setup.sh script to continue from here #
#                                                                                           #
#############################################################################################

# Defaults — overridden by .setup.conf; keeps all toggles bound even on partial configs
INSTALL_RUST=false; INSTALL_NODE=false; INSTALL_ICP=false; INSTALL_PYTHON=false
INSTALL_DOCKER=false; INSTALL_FF_ESR=false; INSTALL_CLAUDE=false; INSTALL_GEMINI_CLI=false
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
mkdir -p ~/.gemini
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
GLOBAL_INSTRUCTIONS="$DOTFILES_DIR/agent/CONTRIBUTING.md"
mkdir -p ~/.claude ~/.codex ~/.gemini
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.claude/CLAUDE.md
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.codex/AGENTS.md
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.gemini/AGENTS.md
ln -sf "$GLOBAL_INSTRUCTIONS" ~/.gemini/GEMINI.md

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

# --- Firefox ESR (Mozilla apt repo) ---
if [[ "$INSTALL_FF_ESR" == true ]] && ! dpkg -s firefox-esr >/dev/null 2>&1; then
    echo "Setting up Mozilla apt repo for Firefox ESR..."
    sudo install -d -m 0755 /etc/apt/keyrings
    [ -f /etc/apt/keyrings/packages.mozilla.org.asc ] || curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
    [ -f /etc/apt/sources.list.d/mozilla.list ] || echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
    [ -f /etc/apt/preferences.d/mozilla ] || printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' | sudo tee /etc/apt/preferences.d/mozilla
    sudo apt-get -qq update && sudo apt-get -qq install -y firefox-esr
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
    fnm install --lts
    npm install -g vite
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

if [[ "$INSTALL_GEMINI_CLI" == true ]] && ! command -v gemini >/dev/null 2>&1; then
    echo "Installing Gemini CLI..."
    npm install -g @google/gemini-cli
fi

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
echo ""
echo "To update packages and toolchains, run:"
echo "  validate_setup.sh -u"
