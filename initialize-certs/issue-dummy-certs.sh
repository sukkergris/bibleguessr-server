#!/usr/bin/env bash
# issue-dummy-certs.sh
#
# Creates nginx/ssl/dummy.crt + dummy.key so the catch-all server block
# (00-globals.conf) can start before real certs exist.

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/header.sh"

load_module certs

_ssl_dir="${PROJECT_ROOT}/nginx/ssl"

if [[ -f "${_ssl_dir}/dummy.crt" ]] && [[ -f "${_ssl_dir}/dummy.key" ]]; then
  printf '[SKIP] Dummy cert already exists (%s)\n' "${_ssl_dir}"
  exit 0
fi

create_dummy_cert
printf '[OK] Dummy cert created in %s\n' "${_ssl_dir}"
