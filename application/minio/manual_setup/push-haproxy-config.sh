#!/usr/bin/env bash
set -euo pipefail

cat > /tmp/haproxy.cfg <<'EOF'
global
    daemon
    maxconn 4096
    log /dev/log local0
    log /dev/log local1 notice
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-bind-ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option forwardfor
    option http-server-close
    timeout connect 10s
    timeout client  5m
    timeout server  5m
    timeout http-request 30s
    timeout http-keep-alive 30s
    timeout queue 1m
    timeout tunnel 10m

listen stats
    bind 127.0.0.1:8404
    stats enable
    stats uri /
    stats refresh 5s

frontend minio_https
    bind :443 ssl crt /etc/haproxy/certs/minio-lb.pem alpn http/1.1
    default_backend minio_backend

backend minio_backend
    balance roundrobin
    option httpchk
    http-check send meth GET uri /minio/health/live ver HTTP/1.1 hdr Host minio.local
    http-check expect status 200
    default-server check inter 5s rise 2 fall 3 maxconn 1000
    server minio-inst-1 minio-inst-1:9000
    server minio-inst-2 minio-inst-2:9000
    server minio-inst-3 minio-inst-3:9000
    server minio-inst-4 minio-inst-4:9000
EOF

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

echo "=== lb-1 ==="
scp /tmp/haproxy.cfg ubuntu@$FIP:/tmp/
ssh ubuntu@$FIP "sudo install -o root -g root -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && rm /tmp/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"

echo ""
echo "=== lb-2 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/haproxy.cfg ubuntu@$LB2_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo install -o root -g root -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && rm /tmp/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"

rm /tmp/haproxy.cfg

# Wait for health checks to converge
echo ""
echo "Waiting 10 seconds for health checks to mark backends UP..."
sleep 10

echo ""
echo "=== Recent HAProxy events on lb-1 ==="
ssh ubuntu@$FIP "sudo journalctl -u haproxy --no-pager --since '30 seconds ago' | grep -E 'is UP|is DOWN|NOTICE' | tail -10"