#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/header.sh"
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/root-loader.sh"

NGINX_ENV_FILE="${PROJECT_ROOT}/env/nginx.env"

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
    exit 1
fi

CERT_FILE="${PROJECT_ROOT}/certs/live/${DOMAIN}/fullchain.pem"

log_info "Verifying dev certificate for ${DOMAIN}"

if [[ ! -f "${CERT_FILE}" ]]; then
    log_error "Missing cert file: ${CERT_FILE}"
    exit 1
fi
log_ok "Cert file present: ${CERT_FILE}"

if ! openssl x509 -in "${CERT_FILE}" -noout -checkend 0 2>/dev/null; then
    log_error "Certificate is expired or invalid"
    exit 1
fi
log_info "Expiry: $(openssl x509 -in "${CERT_FILE}" -noout -enddate)"
log_ok "Certificate is valid"

log_info "SANs: $(openssl x509 -in "${CERT_FILE}" -noout -ext subjectAltName 2>/dev/null)"

case "${OS}" in
    macos)
        if security find-certificate -c "${DOMAIN}" /Library/Keychains/System.keychain >/dev/null 2>&1; then
            log_ok "Found in macOS System keychain"
        else
            log_warn "Not found in macOS System keychain"
        fi
        ;;
    linux|wsl)
        STORE="/usr/local/share/ca-certificates/${DOMAIN}.crt"
        if [[ -f "${STORE}" ]]; then
            log_ok "Found at ${STORE}"
        else
            log_warn "Not found at ${STORE}"
        fi
        ;;
    *)
        log_warn "No trust store check implemented for OS=${OS}"
        ;;
esac
