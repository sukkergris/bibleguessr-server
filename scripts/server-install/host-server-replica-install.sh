#!/usr/bin/env bash
# Host Server Replica Install Script
set -u

# The workspace mount is often owned by a different UID than container-user,
# which makes git refuse to operate on it ("detected dubious ownership").
git config --global --add safe.directory /xyz

echo "Host server REPLICA install complete"