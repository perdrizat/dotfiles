#!/bin/bash

# Ensure sudo is available
if ! command -v sudo &> /dev/null; then
    echo "Sudo not found. Please run as root or install sudo."
    exit 1
fi

# Install the setup prerequisites
sudo apt update
sudo apt install -y git curl stow age

# Clone the repo if we aren't already in it
if [ ! -d "$HOME/dotfiles" ]; then
    echo "Cloning dotfiles..."
    git clone https://github.com/perdrizat/dotfiles.git "$HOME/dotfiles"
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

# Run Stow
# Assuming your dotfiles are in ~/dotfiles and *not* organized into folders
echo "Linking dotfiles with Stow..."
cd ~/dotfiles
stow agy
stow bash
stow git
stow ssh

# sort out SSH
if [ -f ~/dotfiles/ssh/id_ed25519.age ]; then
    echo "Decrypting SSH key..."
    age --decrypt -o ~/.ssh/id_ed25519 ~/dotfiles/ssh/id_ed25519.age
    chmod 600 ~/.ssh/id_ed25519
fi
echo "Fixing remaining SSH permissions..."
chmod 700 ~/dotfiles/ssh/.ssh
[ -f ~/.ssh/config ] && chmod 644 ~/.ssh/config

# Install remaining utilities
sudo apt install build-essential python3-venv  docker-compose-v2

echo "Setup complete! Restart your shell or run"
echo '. ~/.bashrc'
