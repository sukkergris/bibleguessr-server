#!/usr/bin/env bash

set -u

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"${dir}/scripts/server-install/server-install.sh" "$@"