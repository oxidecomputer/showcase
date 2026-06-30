#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB1_PRIV=$(oxide instance nic list --project minio-poc --instance lb-1 | jq -r '.[] | .ip_stack.value.v4.ip')
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')
echo "lb-1 private: $LB1_PRIV"
echo "lb-2 private: $LB2_PRIV"

# Stop and disable keepalived first - replacing it
echo ""
echo "=== Stopping keepalived (replaced by watcher) ==="
ssh ubuntu@$FIP "sudo systemctl stop keepalived && sudo systemctl disable keepalived"
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo systemctl stop keepalived && sudo systemctl disable keepalived"

# Watcher script (same on both LBs)
cat > /tmp/minio-lb-watcher.sh <<'OUTER'
#!/usr/bin/env bash
# /usr/local/bin/minio-lb-watcher.sh
# Polls peer LB. If peer's HAProxy is unreachable for N consecutive checks,
# fires the failover script (which is idempotent).

set -uo pipefail

PEER_HOST="${1:?Usage: $0 <peer-ip-or-hostname>}"
PEER_PORT="${2:-443}"
CHECK_INTERVAL="${3:-2}"
FAIL_THRESHOLD="${4:-3}"

logger -t minio-lb-watcher "Starting; peer=$PEER_HOST:$PEER_PORT, threshold=$FAIL_THRESHOLD, interval=${CHECK_INTERVAL}s"

failures=0
last_state="init"

while true; do
  if nc -z -w2 "$PEER_HOST" "$PEER_PORT" 2>/dev/null; then
    if [ "$last_state" != "up" ]; then
      logger -t minio-lb-watcher "Peer $PEER_HOST is UP"
      last_state="up"
    fi
    failures=0
  else
    failures=$((failures + 1))
    logger -t minio-lb-watcher "Peer $PEER_HOST check FAILED ($failures/$FAIL_THRESHOLD)"
    if [ "$failures" -ge "$FAIL_THRESHOLD" ] && [ "$last_state" != "down" ]; then
      logger -t minio-lb-watcher "Peer $PEER_HOST DOWN, invoking failover"
      /usr/local/bin/minio-fip-failover.sh || logger -t minio-lb-watcher "Failover script returned non-zero"
      last_state="down"
    fi
  fi
  sleep "$CHECK_INTERVAL"
done
OUTER

# Build a systemd unit per LB (each LB watches the OTHER LB's IP)
make_unit() {
  local PEER_IP="$1"
  cat <<UNIT
[Unit]
Description=MinIO LB watcher (TCP-polling FIP failover)
After=network-online.target haproxy.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/minio-lb-watcher.sh $PEER_IP 443 2 3
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNIT
}

make_unit "$LB2_PRIV" > /tmp/minio-lb-watcher.service.lb-1
make_unit "$LB1_PRIV" > /tmp/minio-lb-watcher.service.lb-2

# Push to lb-1
echo ""
echo "=== lb-1 ==="
scp /tmp/minio-lb-watcher.sh ubuntu@$FIP:/tmp/
scp /tmp/minio-lb-watcher.service.lb-1 ubuntu@$FIP:/tmp/minio-lb-watcher.service
ssh ubuntu@$FIP "
  sudo install -o root -g root -m 755 /tmp/minio-lb-watcher.sh /usr/local/bin/
  sudo install -o root -g root -m 644 /tmp/minio-lb-watcher.service /etc/systemd/system/
  rm /tmp/minio-lb-watcher.sh /tmp/minio-lb-watcher.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now minio-lb-watcher
  sudo systemctl status minio-lb-watcher --no-pager | head -10
"

# Push to lb-2
echo ""
echo "=== lb-2 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/minio-lb-watcher.sh ubuntu@$LB2_PRIV:/tmp/
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/minio-lb-watcher.service.lb-2 ubuntu@$LB2_PRIV:/tmp/minio-lb-watcher.service
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "
  sudo install -o root -g root -m 755 /tmp/minio-lb-watcher.sh /usr/local/bin/
  sudo install -o root -g root -m 644 /tmp/minio-lb-watcher.service /etc/systemd/system/
  rm /tmp/minio-lb-watcher.sh /tmp/minio-lb-watcher.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now minio-lb-watcher
  sudo systemctl status minio-lb-watcher --no-pager | head -10
"

rm /tmp/minio-lb-watcher.sh /tmp/minio-lb-watcher.service.lb-1 /tmp/minio-lb-watcher.service.lb-2

echo ""
echo "=== Watcher startup logs ==="
ssh ubuntu@$FIP "sudo journalctl -t minio-lb-watcher --no-pager --since '30 seconds ago' | tail -5"
echo ""
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo journalctl -t minio-lb-watcher --no-pager --since '30 seconds ago' | tail -5"