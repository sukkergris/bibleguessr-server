#!/usr/bin/env bash
set -eu

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The workspace mount is often owned by a different UID than container-user,
# which makes git refuse to operate on it ("detected dubious ownership").
git config --global --add safe.directory /xyz

SCRIPTS_DIR="${dir}/../scripts"

COPY_SSH_SCRIPT="$SCRIPTS_DIR/copy-ssh-files.sh"
if [[ ! -f "$COPY_SSH_SCRIPT" ]]; then
  echo "ERROR: Script not found: $COPY_SSH_SCRIPT" >&2
  exit 1
fi

bash "$COPY_SSH_SCRIPT"

SCRIPT="$SCRIPTS_DIR/remove-userkeychain.sh"
if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: Script not found: $SCRIPT" >&2
  exit 1
fi

bash "$SCRIPT" ~/.ssh/config

claude --print "." > /dev/null 2>&1 || true

echo "Post container install script done running"
