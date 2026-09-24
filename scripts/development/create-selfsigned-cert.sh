#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib-bash/header.sh"

load_module certs

resolve_domain() {
  local arg_domain="${1:-}"
  local nginx_env_file="${PROJECT_ROOT}/env/nginx.env"

  if [[ -n "${arg_domain}" ]]; then
    printf '%s\n' "${arg_domain}"
    return 0
  fi

  if [[ -f "${nginx_env_file}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${nginx_env_file}"
    set +a
  fi

  if [[ -z "${DOMAIN:-}" ]]; then
    printf '[ERROR] DOMAIN is required. Pass it as an argument or set DOMAIN in env/nginx.env.\n' >&2
    return 1
  fi

  printf '%s\n' "${DOMAIN}"
}

main() {
  local domain
  local days="${2:-825}"
  local cert_dir

  domain="$(resolve_domain "${1:-}")"
  cert_dir="${PROJECT_ROOT}/certs/live/${domain}"

  create_selfsigned_cert "${domain}" "${days}" "${cert_dir}"

  cp "${cert_dir}/${domain}.crt" "${cert_dir}/fullchain.pem"
  cp "${cert_dir}/${domain}.key" "${cert_dir}/privkey.pem"

  printf '[OK] Self-signed cert created in %s\n' "${cert_dir}"
}

main "$@"