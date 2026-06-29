#!/usr/bin/env bash
set -euo pipefail

# Get private IPs of all MinIO nodes
NODE1_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-1 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE2_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-2 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE3_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-3 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE4_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-4 | jq -r '.[] | .ip_stack.value.v4.ip')

cat > /tmp/minio-hosts-block <<EOF
# === MinIO cluster nodes (managed by Phase 6 setup) ===
$NODE1_IP minio-inst-1
$NODE2_IP minio-inst-2
$NODE3_IP minio-inst-3
$NODE4_IP minio-inst-4
# === end MinIO cluster nodes ===
EOF

cat > /tmp/update-hosts.sh <<'OUTER'
#!/usr/bin/env bash
set -euo pipefail
sudo sed -i '/=== MinIO cluster nodes/,/=== end MinIO cluster nodes/d' /etc/hosts
sudo tee -a /etc/hosts < /tmp/minio-hosts-block > /dev/null
echo "Updated /etc/hosts on $(hostname):"
grep -A 5 "MinIO cluster nodes" /etc/hosts
OUTER

# lb-1 reachable directly via the Floating IP (sshd listens on 22 even though HAProxy isn't running)
FIP="45.154.216.154"
echo "=== lb-1 (via FIP $FIP) ==="
scp -o StrictHostKeyChecking=accept-new /tmp/minio-hosts-block /tmp/update-hosts.sh ubuntu@$FIP:/tmp/
ssh ubuntu@$FIP "bash /tmp/update-hosts.sh"

# lb-2 reachable via ProxyJump through inst-1
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')
echo ""
echo "=== lb-2 (private $LB2_PRIV via ProxyJump through inst-1) ==="
scp -o StrictHostKeyChecking=accept-new -o ProxyJump=ubuntu@$INST1_IP /tmp/minio-hosts-block /tmp/update-hosts.sh ubuntu@$LB2_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "bash /tmp/update-hosts.sh"

# Verify resolution on both LBs
echo ""
echo "=== Verification ==="
echo "--- lb-1 ---"
ssh ubuntu@$FIP 'for peer in 1 2 3 4; do getent hosts minio-inst-$peer; done'
echo ""
echo "--- lb-2 ---"
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV 'for peer in 1 2 3 4; do getent hosts minio-inst-$peer; done'