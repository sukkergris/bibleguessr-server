#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

main() {
	local domain="${1:-}"
	local ip_address="${2:-127.0.0.1}"
	local days="${3:-825}"

	"${SCRIPT_DIR}/create-selfsigned-cert.sh" "${domain}" "${days}"
	"${SCRIPT_DIR}/trust-selfsigned-cert.sh" "${domain}"
	"${SCRIPT_DIR}/add-to-host.sh" "${domain}" "${ip_address}"

	printf '[OK] Local domain setup complete. domain=%s ip=%s days=%s\n' "${domain:-from-env}" "${ip_address}" "${days}"
}

main "$@"
