#!/usr/bin/env bash

set -u

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "DIR: ${dir}"

APP_ENV_FILE="${dir}/../../env/app.env"

if [[ ! -f "${APP_ENV_FILE}" ]]; then
  echo "Missing required file: ${APP_ENV_FILE}"
  echo "Create env/app.env before running this installer."
  exit 1
fi

# shellcheck source=/dev/null
source "${APP_ENV_FILE}"

if [[ -z "${HOST_ENVIRONMENT:-}" ]]; then
  echo "HOST_ENVIRONMENT is not set in ${APP_ENV_FILE}"
  echo "Set HOST_ENVIRONMENT to production or development."
  exit 1
fi

# shellcheck source=/dev/null
source "${dir}/server-install-common.sh"

if [[ "${HOST_ENVIRONMENT}" == "production" ]]; then
  echo "Running production server install script..."
  "${dir}/host-server-install.sh"
else
  echo "Running development server install script..."
  "${dir}/host-server-replica-install.sh"
fi
