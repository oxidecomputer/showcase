#!/usr/bin/env bash
set -euo pipefail

# Generate strong random credentials
ROOT_USER="minio-admin-$(openssl rand -hex 3)"
ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

echo ""
echo "==============================================="
echo "  MinIO root credentials - SAVE THESE NOW"
echo "==============================================="
echo "  MINIO_ROOT_USER:     $ROOT_USER"
echo "  MINIO_ROOT_PASSWORD: $ROOT_PASSWORD"
echo "==============================================="
echo ""
echo "Store in 1Password, lastpass, or your team's secrets store."
echo "These are the root keys to the MinIO cluster - rotate them"
echo "before the POC handoff. mc admin user add can create lower-priv"
echo "service accounts for ongoing access."
echo ""
read -p "Have you saved them? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborting. Re-run when ready."
  exit 1
fi

# Save into a local env file we'll push to each node
cat > /tmp/minio-env.sh <<EOF
ROOT_USER='$ROOT_USER'
ROOT_PASSWORD='$ROOT_PASSWORD'
EOF
echo "Credentials staged at /tmp/minio-env.sh (DELETE after the build is done)."