#!/usr/bin/env bash
set -u

CERT_FILE="${1}"
DOMAIN="${2}"

if [[ -z "${CERT_FILE}" ]] || [[ -z "${DOMAIN}" ]]; then
    echo "Usage: $0 <certificate-file> <domain>" >&2
    exit 1
fi

if [[ ! -f "${CERT_FILE}" ]]; then
    echo "Certificate file not found: ${CERT_FILE}" >&2
    exit 1
fi

sudo security delete-certificate -c "${DOMAIN}" /Library/Keychains/System.keychain 2>/dev/null || true

sudo security add-trusted-cert \
    -d \
    -r trustRoot \
    -k /Library/Keychains/System.keychain \
    "${CERT_FILE}"
