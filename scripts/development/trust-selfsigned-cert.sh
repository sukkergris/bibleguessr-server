#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib-bash/header.sh"

load_module certs
load_module os-detection

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
	local cert_file

	domain="$(resolve_domain "${1:-}")"
	cert_file="${2:-${PROJECT_ROOT}/certs/live/${domain}/fullchain.pem}"

	trust_dev_cert "${cert_file}" "${domain}"
	printf '[OK] Added %s to local trust store using %s\n' "${domain}" "${cert_file}"
}

main "$@"
