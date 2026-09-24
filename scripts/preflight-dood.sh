#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file env/nginx.env --env-file env/letsencrypt.env --env-file env/webapi.env -f docker-compose.yml -p site-fleet-cms-server)

read_env_value() {
  local file="$1"
  local key="$2"
  local value
  value="$(grep -E "^${key}=" "$file" | tail -n1 | cut -d'=' -f2- || true)"
  printf '%s' "$value"
}

DOMAIN="$(read_env_value env/nginx.env DOMAIN)"
LETSENCRYPT_DIR="$(read_env_value env/letsencrypt.env LETSENCRYPT_DIR)"
LETSENCRYPT_CHALLENGES_DIR="$(read_env_value env/letsencrypt.env LETSENCRYPT_CHALLENGES_DIR)"
NGINX_DIR="$(read_env_value env/nginx.env NGINX_DIR)"

if [[ -z "$DOMAIN" ]]; then
  echo "[ERROR] DOMAIN is missing in env/nginx.env"
  exit 1
fi
if [[ -z "$LETSENCRYPT_DIR" ]]; then
  echo "[ERROR] LETSENCRYPT_DIR is missing in env/letsencrypt.env"
  exit 1
fi
if [[ -z "$LETSENCRYPT_CHALLENGES_DIR" ]]; then
  echo "[ERROR] LETSENCRYPT_CHALLENGES_DIR is missing in env/letsencrypt.env"
  exit 1
fi
if [[ -z "$NGINX_DIR" ]]; then
  echo "[ERROR] NGINX_DIR is missing in env/nginx.env"
  exit 1
fi

echo "[INFO] Rendering compose config with current env files"
"${COMPOSE[@]}" config >/dev/null

echo "[INFO] Probing nginx service mounts via docker compose run"
"${COMPOSE[@]}" run --rm --no-deps nginx sh -ec '
  test -d /etc/nginx/conf.d
  test -d /etc/nginx/includes
  test -d /etc/letsencrypt/live
  test -d /var/www/letsencrypt_challenges
  test -r "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  test -r "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
'

echo "[OK] Preflight passed: compose env interpolation, mounts, and cert files are ready"
