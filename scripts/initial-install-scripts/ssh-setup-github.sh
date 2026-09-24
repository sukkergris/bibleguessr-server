#!/bin/bash
# KTK SSH Key Setup Script for GitHub
set -u

KEY_COMMENT="github-$(hostname)-$(date +%Y%m%d)"
KEY_PATH="$HOME/.ssh/id_ed25519_github"
CONFIG_FILE="$HOME/.ssh/config"

echo "Generating a new SSH key for GitHub..."
ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$KEY_PATH" -N ""

echo "Configuring SSH to use Port 443 and the custom IdentityFile..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Append configuration block to ~/.ssh/config
cat <<EOF >> "$CONFIG_FILE"

Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    IdentityFile $KEY_PATH
EOF

chmod 600 "$CONFIG_FILE"

echo "Adding the key to ssh-agent..."
eval "$(ssh-agent -s)"
ssh-add "$KEY_PATH"

echo -e "\nPublic key for GitHub (copy and add to https://github.com/settings/keys):\n"
cat "$KEY_PATH.pub"

echo -e "\nDone. Test with: ssh -T git@github.com"