#!/usr/bin/env bash
set -euo pipefail

INST1_IP="45.154.216.180"   # use a MinIO node as jumphost since FIP will move mid-drill
LB1_PRIV=$(oxide instance nic list --project minio-poc --instance lb-1 | jq -r '.[] | .ip_stack.value.v4.ip')
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

LB1_UUID=$(oxide instance view --project minio-poc --instance lb-1 | jq -r '.id')
LB2_UUID=$(oxide instance view --project minio-poc --instance lb-2 | jq -r '.id')

echo "=== Pre-drill state ==="
echo "lb-1 UUID: $LB1_UUID"
echo "lb-2 UUID: $LB2_UUID"
echo "FIP holder: $(oxide floating-ip view --project minio-poc --floating-ip minio-s3-endpoint | jq -r '.instance_id')"

echo ""
echo "=== T0: killing HAProxy on lb-1 at $(date +%H:%M:%S) ==="
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB1_PRIV "sudo systemctl stop haproxy"

echo ""
echo "Waiting 15 seconds for watcher to detect and fail over..."
sleep 15

echo ""
echo "=== Post-drill state at $(date +%H:%M:%S) ==="
echo "FIP holder: $(oxide floating-ip view --project minio-poc --floating-ip minio-s3-endpoint | jq -r '.instance_id')"
echo "(should now be lb-2 UUID = $LB2_UUID)"

echo ""
echo "=== lb-2 watcher log ==="
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo journalctl -t minio-lb-watcher --no-pager --since '30 seconds ago' | tail -10"

echo ""
echo "=== lb-2 failover script log ==="
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo journalctl -t minio-failover --no-pager --since '30 seconds ago' | tail -10"

echo ""
echo "=== Client view: does mc still work through the FIP? ==="
mc --insecure admin info minio-poc