#!/bin/bash

# Install the setup prerequisites if missing
command -v git >/dev/null && command -v curl >/dev/null && command -v stow >/dev/null && command -v age >/dev/null || { sudo apt update && sudo apt install -y git curl stow age; }

# Clone the repo if we aren't already in it
if [ ! -d "$HOME/dotfiles" ]; then
    echo "Cloning dotfiles..."
    cd "$HOME" && git clone https://github.com/perdrizat/dotfiles.git
    cd "$HOME/dotfiles"
else
    cd "$HOME/dotfiles"
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

# Add the dotfiles
echo "Linking dotfiles with Stow..."
cd "$HOME/dotfiles"
mkdir -p ~/.claude  # must exist as real dir before stow (Claude Code writes other files here)
stow --adopt bash
stow --adopt bin
stow --adopt claude
stow --adopt git
stow --adopt ssh
if [ ! -d ~/.agent ]; then # Antigravity doesn't like ~/.agent as a symlink
    mkdir ~/.agent
fi
ln -sf ~/dotfiles/agent/.agent/skills ~/.agent/skills
ln -sf ~/dotfiles/agent/.agent/workflows ~/.agent/workflows

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
dpkg -s build-essential python3-venv docker-compose-v2 >/dev/null 2>&1 || sudo apt install -y build-essential python3-venv docker-compose-v2

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
