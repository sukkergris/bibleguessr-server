#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib-bash/root-loader.sh"

# SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ensure_letsencrypt_live_dir() {
  local domain="$1"
  local letsencrypt_live_dir="/etc/letsencrypt/live/${domain}"

  sudo mkdir -p "${letsencrypt_live_dir}"
}

copy_local_cert_to_letsencrypt_live() {
  local domain="$1"
  local source_cert_dir="${PROJECT_ROOT}/development/letsencrypt/live/${domain}"
  local target_cert_dir="/etc/letsencrypt/live/${domain}"

  if [[ ! -f "${source_cert_dir}/fullchain.pem" ]] || [[ ! -f "${source_cert_dir}/privkey.pem" ]]; then
    printf '[ERROR] Missing local cert files in %s\n' "${source_cert_dir}" >&2
    return 1
  fi

  sudo cp "${source_cert_dir}/fullchain.pem" "${target_cert_dir}/fullchain.pem"
  sudo cp "${source_cert_dir}/privkey.pem" "${target_cert_dir}/privkey.pem"
}

setup::run() {
  local domain="${1:-}"

  ensure_letsencrypt_live_dir "${domain}"
  copy_local_cert_to_letsencrypt_live "${domain}"

  printf '[OK] Local cert flow complete and copied to /etc/letsencrypt/live/%s/\n' "${domain}"
}

setup::run "bibleguessr.srv"
setup::run "vault.bibleguessr.srv"
