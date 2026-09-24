#!/usr/bin/env bash
# github-test-ssh-access.sh
# This script tests SSH access to GitHub using a specific SSH key and port 443.
# It starts a temporary ssh-agent, adds the key, tests the connection, and cleans up.

set -u

KEY_PATH="${HOME}/.ssh/id_ed25519_github"
GITHUB_HOST="ssh.github.com"
GITHUB_USER="git"
GITHUB_PORT=443

# Run everything in a subshell so ssh-agent env is preserved
(
  echo "Starting temporary ssh-agent..."
  eval "$(ssh-agent -s)"
  echo "Adding SSH key to agent: $KEY_PATH"
  ssh-add "$KEY_PATH"
  echo "Testing SSH connection to GitHub..."
  ssh -T -p "$GITHUB_PORT" -i "$KEY_PATH" "$GITHUB_USER@$GITHUB_HOST"
  echo "Killing ssh-agent..."
  ssh-agent -k
)
