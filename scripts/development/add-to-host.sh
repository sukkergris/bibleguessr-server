#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib-bash/header.sh"

load_module add-domain-to-hosts

main() {
	local domain
	local ip_address="${2:-127.0.0.1}"

	domain="$(resolve_domain "${1:-}")"
	add_domain_to_hosts "${domain}" "${ip_address}"
}

main "$@"
