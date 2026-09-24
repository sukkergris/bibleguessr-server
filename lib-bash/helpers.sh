#!/usr/bin/env bash
set -u

[[ -n "${_HELPERS_LOADED:-}" ]] && return 0
_HELPERS_LOADED=1

load_env_file() {
  local env_file="$1"

# Turns on Bash auto-export mode.
# Any variable created or changed after this point is automatically marked for export to child processes
  set -a
  # shellcheck source=/dev/null
  . "$env_file" # equivalent to: source "$env_file"
  set +a
}

load_env_files() {
  local env_folder="$1"

  for f in "${env_folder}"/*.env; do
    [ -f "${f}" ]
    load_env_file "${f}"
  done
}
