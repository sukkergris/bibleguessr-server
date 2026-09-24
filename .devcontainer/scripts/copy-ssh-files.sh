#!/usr/bin/env bash
set -Eeuo pipefail
# Prerequisite: The .ssh files must be mounted to ~/.sshtemplate before running this script.
#  "source=${localEnv:HOME}/.ssh,target=/home/container-user/.sshtemplate,type=bind,readonly,consistency=cached"
# Copy all SSH files from template to ~/.ssh and set permissions
if [ -d "$HOME/.sshtemplate" ]; then
  mkdir -p "$HOME/.ssh"
  rsync -a --exclude 'agent/' "$HOME/.sshtemplate/." "$HOME/.ssh/"
  chmod 700 "$HOME/.ssh"
  chmod 600 "$HOME/.ssh/"* 2>/dev/null || true
  echo "SSH files copied from .sshtemplate."
fi
