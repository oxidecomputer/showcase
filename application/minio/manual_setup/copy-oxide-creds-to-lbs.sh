#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

CREDS_DIR="${HOME}/.config/oxide"
if [ ! -f "$CREDS_DIR/credentials.toml" ]; then
  echo "credentials.toml not found at $CREDS_DIR - adjust CREDS_DIR in the script"
  exit 1
fi

push_creds() {
  local TARGET="$1"
  local SSH_OPTS="$2"
  echo ""
  echo "=== Copying to $TARGET ==="
  scp $SSH_OPTS "$CREDS_DIR/credentials.toml" ubuntu@$TARGET:/tmp/
  [ -f "$CREDS_DIR/config.toml" ] && scp $SSH_OPTS "$CREDS_DIR/config.toml" ubuntu@$TARGET:/tmp/
  ssh $SSH_OPTS ubuntu@$TARGET "
    sudo mkdir -p /root/.config/oxide
    sudo install -o root -g root -m 600 /tmp/credentials.toml /root/.config/oxide/
    [ -f /tmp/config.toml ] && sudo install -o root -g root -m 600 /tmp/config.toml /root/.config/oxide/ || true
    rm -f /tmp/credentials.toml /tmp/config.toml
    sudo ls -la /root/.config/oxide/
  "
  echo "Verifying oxide CLI as root on $TARGET..."
  ssh $SSH_OPTS ubuntu@$TARGET "sudo OXIDE_HOST=https://employee-d1ce31bdc66a5171.sys.r3.oxide-preview.com oxide project list --profile employee-d1ce31bdc66a5171 | head -10"
}

push_creds "$FIP" ""
push_creds "$LB2_PRIV" "-o ProxyJump=ubuntu@$INST1_IP"