#!/usr/bin/env bash
set -euo pipefail

cat > /tmp/minio-fip-failover.sh <<'OUTER'
#!/usr/bin/env bash
# /usr/local/bin/minio-fip-failover.sh
# Move the MinIO S3 floating IP to this LB instance.
# Designed to be invoked by keepalived's notify_master or by hand.

set -euo pipefail

OXIDE_HOST="https://employee-d1ce31bdc66a5171.sys.r3.oxide-preview.com"
PROJECT="minio-poc"
FIP_NAME="minio-s3-endpoint"
PROFILE="employee-d1ce31bdc66a5171"
THIS_INSTANCE="$(hostname)"

export OXIDE_HOST

logger -t minio-failover "Starting failover; target instance = $THIS_INSTANCE"

# Read current FIP attachment (instance_id, may be empty if detached)
CURRENT=$(oxide floating-ip view \
  --project "$PROJECT" \
  --floating-ip "$FIP_NAME" \
  --profile "$PROFILE" \
  | jq -r '.instance_id // empty')

# Read this instance's UUID
THIS_INSTANCE_ID=$(oxide instance view \
  --project "$PROJECT" \
  --instance "$THIS_INSTANCE" \
  --profile "$PROFILE" \
  | jq -r '.id')

logger -t minio-failover "Current FIP holder: ${CURRENT:-<detached>}; target: $THIS_INSTANCE_ID"

if [ "$CURRENT" = "$THIS_INSTANCE_ID" ]; then
  logger -t minio-failover "FIP already attached to $THIS_INSTANCE, nothing to do"
  exit 0
fi

# Detach from whoever has it now (if anyone)
if [ -n "$CURRENT" ]; then
  logger -t minio-failover "Detaching FIP from current holder"
  oxide floating-ip detach \
    --project "$PROJECT" \
    --floating-ip "$FIP_NAME" \
    --profile "$PROFILE"
fi

# Attach to this instance
logger -t minio-failover "Attaching FIP to $THIS_INSTANCE"
oxide floating-ip attach \
  --project "$PROJECT" \
  --floating-ip "$FIP_NAME" \
  --kind instance \
  --parent "$THIS_INSTANCE" \
  --profile "$PROFILE"

logger -t minio-failover "Failover complete"
OUTER

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

push() {
  local TARGET=$1
  local OPTS=$2
  echo "=== Pushing to $TARGET ==="
  scp $OPTS /tmp/minio-fip-failover.sh ubuntu@$TARGET:/tmp/
  ssh $OPTS ubuntu@$TARGET "sudo install -o root -g root -m 755 /tmp/minio-fip-failover.sh /usr/local/bin/ && rm /tmp/minio-fip-failover.sh && ls -la /usr/local/bin/minio-fip-failover.sh"
}

push "$FIP" ""
push "$LB2_PRIV" "-o ProxyJump=ubuntu@$INST1_IP"

rm /tmp/minio-fip-failover.sh
echo ""
echo "=== Done. Script installed at /usr/local/bin/minio-fip-failover.sh on both LBs ==="