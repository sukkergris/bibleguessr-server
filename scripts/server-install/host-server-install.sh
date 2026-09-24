#!/usr/bin/env bash
# Host Server Install Script

set -euo pipefail

enable_unit_if_present() {
	local unit="$1"

	if systemctl list-unit-files "$unit" --no-legend >/dev/null 2>&1; then
		systemctl enable --now "$unit"
	else
		echo "Skipping ${unit}: unit not found on this host"
	fi
}


"$(dirname "$0")/../programs/docker-compose.installer.sh"

# Optional: Enable and start key services
enable_unit_if_present ssh.service
enable_unit_if_present ufw.service

# Optional: Set up firewall (example)
# ufw allow OpenSSH
# ufw enable

# Optional: Install additional configuration or dotfiles here
# ...

enable_unit_if_present certbot.timer
systemctl status certbot.timer --no-pager || true

echo "Site Fleet CMS server base install complete"

