#!/usr/bin/env bash
set -eu

TOKEN="task-acme-test-$$"
ACME_DIR="/var/www/letsencrypt_challenges/.well-known/acme-challenge"
DOMAIN="${1:-bibleguessr.uk}"

cleanup() {
  sudo rm -f "$ACME_DIR/$TOKEN"
}
trap cleanup EXIT

sudo mkdir -p "$ACME_DIR"
echo "acme-ok" | sudo tee "$ACME_DIR/$TOKEN" >/dev/null
curl -fsS -H "Host: $DOMAIN" "http://127.0.0.1/.well-known/acme-challenge/$TOKEN"
echo ""
echo "ACME challenge path OK"
