#!/usr/bin/env bash

set -u

# Prepare ACME challenge directory for Let's Encrypt
mkdir -p /var/www/letsencrypt_challenges
chown www-data:www-data /var/www/letsencrypt_challenges

apt update
apt install -y \
  curl \
  gpg \
  gettext \
  stow \
  tree \
  docker.io \
  docker-cli \
  certbot \
  openssh-server

"$(dirname "$0")/../programs/task.arm.installer.sh"

"$(dirname "$0")/../programs/neovim.installer.sh"

# Initialize environment variable files for all services
"$(dirname "$0")/../env-init.sh"