#!/bin/bash
# setup.sh — Bootstrap a fresh machine with dotfiles
#
# Must be self-contained: curl-piped before the repo exists.
# validate_setup.sh sources this file for the shared variables below.

DOTFILES_DIR="$HOME/dotfiles"

# --- Shared variables (also used by validate_setup.sh) ---
PREREQS=(git curl stow age)
APT_PACKAGES=(build-essential python3-venv docker-compose-v2)
STOW_SKIP=(.git agent gemini)

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
for pkg_dir in "$DOTFILES_DIR"/*/; do
    pkg=$(basename "$pkg_dir")
    skip=false
    for s in "${STOW_SKIP[@]}"; do
        [[ "$pkg" == "$s" ]] && skip=true && break
    done
    $skip && continue
    stow --adopt "$pkg"
done

# Gemini/Antigravity symlinks (not stow-managed — ~/.gemini must be a real directory)
mkdir -p ~/.gemini
ln -sf "$DOTFILES_DIR/gemini/.gemini/skills" ~/.gemini/skills
ln -sf "$DOTFILES_DIR/gemini/.gemini/workflows" ~/.gemini/workflows

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
    age --decrypt -o ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.age
    chmod 600 ~/.ssh/id_ed25519
fi
echo "Fixing remaining SSH permissions..."
chmod 700 ~/dotfiles/ssh/.ssh
[ -f ~/.ssh/config ] && chmod 644 ~/.ssh/config

# Update & install remaining utilities if not already present
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
dpkg -s "${APT_PACKAGES[@]}" >/dev/null 2>&1 || sudo apt install -y "${APT_PACKAGES[@]}"

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
