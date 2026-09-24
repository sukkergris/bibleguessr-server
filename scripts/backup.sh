#!/usr/bin/env bash
set -u

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/header.sh"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/ktk}"
COMPOSE_PROJECT="ktk-server"
NETWORK="${COMPOSE_PROJECT}_ktk-network"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

log_info "Backup startet: ${BACKUP_PATH}"
mkdir -p "${BACKUP_PATH}/mongo"

log_info "Tager backup af MongoDB (ktk-mongo_data)..."
docker run --rm \
  --network "${NETWORK}" \
  -v "${BACKUP_PATH}/mongo:/backup" \
  mongo:6 \
  mongodump --host mongo --out /backup
log_ok "MongoDB backup gemt: ${BACKUP_PATH}/mongo"

log_info "Tager backup af Squidex assets (ktk-squidex_assets)..."
docker run --rm \
  -v ktk-squidex_assets:/data:ro \
  -v "${BACKUP_PATH}:/backup" \
  alpine \
  tar -czf /backup/squidex-assets.tar.gz -C /data .
log_ok "Assets backup gemt: ${BACKUP_PATH}/squidex-assets.tar.gz"

log_ok "Backup fuldført: ${BACKUP_PATH}"
