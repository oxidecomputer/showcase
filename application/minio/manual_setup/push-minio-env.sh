#!/usr/bin/env bash
set -euo pipefail

# Load credentials from step 5.2
source /tmp/minio-env.sh

# Build the final env file locally
cat > /tmp/minio-env-file <<EOF
# MinIO environment - Phase 5 finalized
MINIO_ROOT_USER=$ROOT_USER
MINIO_ROOT_PASSWORD=$ROOT_PASSWORD
MINIO_VOLUMES="http://minio-inst-{1...4}/mnt/disk{1...4}/minio"
MINIO_OPTS="--address :9000 --console-address :9001"
EOF

# Push and install on each node with root:minio ownership and 640 perms
for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  echo ""
  echo "=== minio-inst-$n ($ext_ip) ==="
  scp -o StrictHostKeyChecking=accept-new /tmp/minio-env-file ubuntu@$ext_ip:/tmp/
  ssh ubuntu@$ext_ip "
    sudo install -o root -g minio -m 640 /tmp/minio-env-file /etc/default/minio
    rm /tmp/minio-env-file
    ls -la /etc/default/minio
    sudo grep -E '^(MINIO_VOLUMES|MINIO_OPTS|MINIO_ROOT_USER)=' /etc/default/minio
  "
done

# Clean up local temp file (contains the password)
rm /tmp/minio-env-file
echo ""
echo "=== /etc/default/minio updated on all 4 nodes ==="