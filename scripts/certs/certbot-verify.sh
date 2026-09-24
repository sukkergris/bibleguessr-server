#!/usr/bin/env bash
set -eu

domains=(
  "kforkode.dk"
  "habibi-vip-taxi.com"
  "carstens-vinduespolering.dk"
)

for domain in "${domains[@]}"; do
  live_dir="/etc/letsencrypt/live/${domain}"

  if ! sudo test -d "${live_dir}"; then
    echo "Missing certificate directory: ${live_dir}"
    exit 1
  fi

  if ! sudo test -f "${live_dir}/fullchain.pem"; then
    echo "Missing fullchain.pem for ${domain}"
    exit 1
  fi

  if ! sudo test -f "${live_dir}/privkey.pem"; then
    echo "Missing privkey.pem for ${domain}"
    exit 1
  fi

  echo "OK: ${domain}"
done

echo "All expected certificates are present."
