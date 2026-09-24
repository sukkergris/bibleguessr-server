#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/header.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/root-loader.sh"

NGINX_ENV_FILE="${PROJECT_ROOT}/env/nginx.env"
CERT_DIR_ROOT="${PROJECT_ROOT}/certs"

if [[ ! -f "${NGINX_ENV_FILE}" ]]; then
    log_error "Missing nginx env file: ${NGINX_ENV_FILE}"
    exit 1
fi

set -a
# shellcheck source=../env/nginx.env
source "${NGINX_ENV_FILE}"
set +a

if [[ -z "${DOMAIN:-}" ]]; then
    log_error "DOMAIN is not set in ${NGINX_ENV_FILE}"
    log_error "Run scripts/env-init.sh to initialise environment files, then set DOMAIN."
    exit 1
fi

log_info "Removing dev certificate for ${DOMAIN}"

case "${OS}" in
    macos)
        if sudo security delete-certificate -c "${DOMAIN}" \
                /Library/Keychains/System.keychain 2>/dev/null; then
            log_ok "Removed ${DOMAIN} from macOS System keychain"
        else
            log_warn "No certificate found for ${DOMAIN} in macOS System keychain"
        fi
        ;;
    linux|wsl)
        CERT_FILE="/usr/local/share/ca-certificates/${DOMAIN}.crt"
        if [[ -f "${CERT_FILE}" ]]; then
            sudo rm -f "${CERT_FILE}"
            sudo update-ca-certificates
            log_ok "Removed ${DOMAIN} from Linux trust store"
        else
            log_warn "No certificate found for ${DOMAIN} in Linux trust store"
        fi
        ;;
    *)
        log_warn "No trust store cleanup implemented for OS=${OS}"
        ;;
esac

CERT_DIR="${CERT_DIR_ROOT}/live/${DOMAIN}"
if [[ -d "${CERT_DIR}" ]]; then
    rm -rf "${CERT_DIR}"
    log_ok "Deleted cert files: ${CERT_DIR}"
else
    log_warn "No cert files found at ${CERT_DIR}"
fi

log_ok "Cleanup complete for ${DOMAIN}"
