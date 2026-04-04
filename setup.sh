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
DOTFILES_SSH_REMOTE="git@github.com:perdrizat/dotfiles.git"

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

# Gemini/Antigravity symlinks (not stow-managed — ~/.gemini must be a real directory)
mkdir -p ~/.gemini
ln -sf "$DOTFILES_DIR/gemini/.gemini/skills" ~/.gemini/skills

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
# Regenerate public key from private key (pub key is not tracked in git)
if [ -f ~/.ssh/id_ed25519 ]; then
    echo "Regenerating public key from private key..."
    ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
fi
echo "Fixing remaining SSH permissions..."
chmod 700 ~/dotfiles/ssh/.ssh
[ -f ~/.ssh/config ] && chmod 644 ~/.ssh/config

# Switch dotfiles remote from HTTPS to SSH now that keys are in place
current_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)
if [ "$current_remote" != "$DOTFILES_SSH_REMOTE" ]; then
    echo "Switching dotfiles remote to SSH..."
    git -C "$DOTFILES_DIR" remote set-url origin "$DOTFILES_SSH_REMOTE"
fi

# Update & install remaining utilities if not already present
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
dpkg -s "${APT_PACKAGES[@]}" >/dev/null 2>&1 || sudo apt install -y "${APT_PACKAGES[@]}"

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
