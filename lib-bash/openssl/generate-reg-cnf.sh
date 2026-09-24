#!/usr/bin/env bash
set -u

[[ -n "${_GENERATE_REG_CNF_LOADED:-}" ]] && return 0
_GENERATE_REG_CNF_LOADED=1

generate_reg_cnf() {
    local domain="$1"
    local src
    src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    local template="${src}/reg.cnf.template"
    local output="${src}/reg.cnf"

    sed -e "s/{DOMAIN}/${domain}/g" "${template}" > "${output}"
}
