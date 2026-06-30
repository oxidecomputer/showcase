#!/usr/bin/env bash
set -euo pipefail

echo "=== Bootstrapping LB node $(hostname) ==="

# Update + packages
sudo apt update
sudo apt upgrade -y
sudo apt install -y haproxy keepalived curl jq chrony
sudo systemctl enable --now chrony

# Stop and disable both services for now - Phase 6 will configure and enable them
sudo systemctl stop haproxy 2>/dev/null || true
sudo systemctl disable haproxy 2>/dev/null || true
sudo systemctl stop keepalived 2>/dev/null || true
sudo systemctl disable keepalived 2>/dev/null || true

echo "=== LB bootstrap complete on $(hostname) ==="
haproxy -v
keepalived -v
chronyc tracking | head -3