#!/usr/bin/env bash
set -euo pipefail

echo "=== Starting MinIO on all 4 nodes simultaneously ==="
for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  echo "Starting on minio-inst-$n ($ext_ip)..."
  ssh ubuntu@$ext_ip "sudo systemctl start minio" &
done
wait
echo "Start commands dispatched. Waiting 15 seconds for cluster formation..."
sleep 15

echo ""
echo "=== Per-node status ==="
for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  echo ""
  echo "--- minio-inst-$n ---"
  ssh ubuntu@$ext_ip "sudo systemctl is-active minio; echo '---logs---'; sudo journalctl -u minio --since '30 seconds ago' --no-pager | tail -20"
done

echo ""
echo "=== Health check ==="
for n in 1 2 3 4; do
  ext_ip=$(oxide instance external-ip list --project minio-poc --instance minio-inst-$n \
           | jq -r '.items[] | select(.kind=="ephemeral") | .ip')
  result=$(ssh ubuntu@$ext_ip "curl -s -o /dev/null -w '%{http_code}' http://localhost:9000/minio/health/live")
  echo "minio-inst-$n health: HTTP $result (200 = healthy)"
done