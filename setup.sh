#!/bin/bash
# setup.sh — Bootstrap a fresh machine with dotfiles
#
# Must be self-contained: curl-piped before the repo exists.
# validate_setup.sh sources this file for the shared variables below.

DOTFILES_DIR="$HOME/dotfiles"

# --- Shared variables (also used by validate_setup.sh) ---
PREREQS=(git curl stow age unzip jq)
APT_PACKAGES=(build-essential)
STOW_SKIP=(.git agent)
DOTFILES_SSH_REMOTE="git@github.com:perdrizat/dotfiles.git"

# --- Dev toolchain toggles (set false to skip, overridable via env) ---
# echo INSTALL_RUST=true; echo INSTALL_NODE=false; echo INSTALL_ICP=true; echo INSTALL_PYTHON=false; echo INSTALL_DOCKER=false # ICP
INSTALL_RUST=${INSTALL_RUST:-false}	# rustup → cargo, rustc, rustfmt, clippy
INSTALL_NODE=${INSTALL_NODE:-true}	# fnm → latest LTS Node + npm
INSTALL_ICP=${INSTALL_ICP:-false}	# dfxvm → dfx + ic-admin
INSTALL_PYTHON=${INSTALL_PYTHON:-false}	# apt python3 + python3-venv
INSTALL_DOCKER=${INSTALL_DOCKER:-true}	# apt docker-compose-v2

# --- LLM agent toggles (set false to skip, overridable via env) ---
INSTALL_CLAUDE=${INSTALL_CLAUDE:-true}	# Claude Code CLI
INSTALL_GEMINI_CLI=${INSTALL_GEMINI_CLI:-false}	# Gemini CLI (npm: @google/gemini-cli)

# When sourced by validate_setup.sh, stop here
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

# Install the setup prerequisites if missing
command -v git >/dev/null && command -v curl >/dev/null && command -v stow >/dev/null && command -v age >/dev/null || { sudo apt update && sudo apt install -y "${PREREQS[@]}"; }

# Clone the repo if we aren't already in it
if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Cloning dotfiles..."
    cd "$HOME" && git clone https://github.com/perdrizat/dotfiles.git
fi
cd "$DOTFILES_DIR"

#############################################################################################
#                                                                                           #
# you can stop copy-pasting and just run the dotfiles/setup.sh script to continue from here #
#                                                                                           #
#############################################################################################

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

# --- System packages ---
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

# Collect apt packages based on toggles
apt_install=("${APT_PACKAGES[@]}")
[[ "$INSTALL_PYTHON" == true ]] && apt_install+=(python3 python3-venv)
[[ "$INSTALL_DOCKER" == true ]] && apt_install+=(docker-compose-v2)

dpkg -s "${apt_install[@]}" >/dev/null 2>&1 || sudo apt install -y "${apt_install[@]}"

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
	curl -L "https://github.com/dfinity/ic/releases/latest/download/ic-admin-x86_64-linux.gz" -o - | gunzip > ic-admin && chmod 0755 ./ic-admin
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
