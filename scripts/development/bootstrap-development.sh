#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/../../lib-bash/header.sh"

load_module "env-substitution"

ENV_FILES="${PROJECT_ROOT}/env"

process_templates "${PROJECT_ROOT}/nginx" "${ENV_FILES}"

# shellcheck source=/dev/null
# shellcheck disable=SC2153
. "${SCRIPTS_DIR}"/development/cert-issue.sh
