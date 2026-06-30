#!/usr/bin/env bash
set -euo pipefail

echo "=== Looking up MinIO private IPs ==="
NODE1_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-1 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE2_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-2 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE3_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-3 | jq -r '.[] | .ip_stack.value.v4.ip')
NODE4_IP=$(oxide instance nic list --project minio-poc --instance minio-inst-4 | jq -r '.[] | .ip_stack.value.v4.ip')
echo "minio-inst-1 -> $NODE1_IP"
echo "minio-inst-2 -> $NODE2_IP"
echo "minio-inst-3 -> $NODE3_IP"
echo "minio-inst-4 -> $NODE4_IP"

cat > /tmp/minio-hosts-block <<EOF
# === MinIO cluster nodes (managed by Phase 5 setup) ===
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

for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  echo ""
  echo "=== minio-inst-$n ($ext_ip) ==="
  scp -o StrictHostKeyChecking=accept-new /tmp/minio-hosts-block /tmp/update-hosts.sh ubuntu@$ext_ip:/tmp/
  ssh ubuntu@$ext_ip "bash /tmp/update-hosts.sh"
done

echo ""
echo "=== Verification: each node resolves all 4 peers ==="
for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  echo ""
  echo "--- from minio-inst-$n ---"
  ssh ubuntu@$ext_ip 'for peer in 1 2 3 4; do getent hosts minio-inst-$peer; done'
done