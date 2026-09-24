#!/bin/bash
# Docker Compose v2 CLI plugin installer for ARM64 Linux (Ubuntu 24.04+)
set -Eeuo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib-bash/header.sh"

COMPOSE_VERSION="v2.35.1"  # Update to latest if needed
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-aarch64"
PLUGIN_DIR="/usr/lib/docker/cli-plugins"
PLUGIN_BIN="${PLUGIN_DIR}/docker-compose"

DOCKER_CMD=""

refresh_shell_path() {
  export PATH="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  hash -r
}

resolve_docker_cmd() {
  local candidate=""

  candidate="$(command -v docker 2>/dev/null || true)"
  if [[ -n "${candidate}" ]]; then
    DOCKER_CMD="${candidate}"
    return 0
  fi

  for candidate in /usr/bin/docker /usr/local/bin/docker /bin/docker; do
    if [[ -x "${candidate}" ]]; then
      DOCKER_CMD="${candidate}"
      return 0
    fi
  done

  return 1
}

has_docker() {
  resolve_docker_cmd
}

ensure_docker() {
  if has_docker; then
    return 0
  fi

  log::warn "docker command not found. Attempting to install Docker runtime and CLI packages."

  local -a installer=()
  if [[ "${EUID}" -eq 0 ]]; then
    installer=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    installer=(sudo apt-get)
  else
    log::error "docker is missing and sudo is not available; cannot install docker.io automatically."
    return 1
  fi

  "${installer[@]}" update
  # Debian trixie can split the docker client into docker-cli.
  "${installer[@]}" install -y docker.io docker-cli

  refresh_shell_path

  if ! has_docker; then
    if command -v dpkg-query >/dev/null 2>&1; then
      dpkg-query -L docker.io 2>/dev/null | grep '/docker$' || true
      dpkg-query -L docker-cli 2>/dev/null | grep '/docker$' || true
    fi
    log::error "Docker runtime/CLI installation completed but docker is still not available in PATH."
    return 1
  fi
}

refresh_shell_path
ensure_docker

if has_docker && "${DOCKER_CMD}" compose version 2>/dev/null | grep -qF "${COMPOSE_VERSION}"; then
  log::info "Docker Compose ${COMPOSE_VERSION} already installed, skipping."
  exit 0
fi

log::info "Installing Docker Compose ${COMPOSE_VERSION} from GitHub"
mkdir -p "${PLUGIN_DIR}"
curl -sSL -o "${PLUGIN_BIN}" "${COMPOSE_URL}"
chmod +x "${PLUGIN_BIN}"

"${DOCKER_CMD}" compose version
