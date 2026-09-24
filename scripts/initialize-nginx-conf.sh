#!/bin/bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

source "${ROOT_DIR}"/lib-bash/header.sh

load_module "env-substitution"

process_templates "${ROOT_DIR}/nginx/conf.d" "${ROOT_DIR}/env"