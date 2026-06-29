#!/usr/bin/env bash
set -euo pipefail

# 1. Firewall rule for TCP 9443 (full ruleset replacement, same dance as Phase 1)
cat > /tmp/firewall-rules.json <<'EOF'
{
  "rules": [
    {
      "name": "allow-icmp",
      "description": "allow inbound ICMP traffic from anywhere",
      "priority": 65534, "action": "allow", "direction": "inbound", "status": "enabled",
      "targets": [{ "type": "vpc", "value": "minio-vpc" }],
      "filters": { "protocols": [{ "type": "icmp" }] }
    },
    {
      "name": "allow-internal-inbound",
      "description": "allow inbound traffic to all instances within the VPC if originated within the VPC",
      "priority": 65534, "action": "allow", "direction": "inbound", "status": "enabled",
      "targets": [{ "type": "vpc", "value": "minio-vpc" }],
      "filters": { "hosts": [{ "type": "vpc", "value": "minio-vpc" }] }
    },
    {
      "name": "allow-ssh",
      "description": "allow inbound TCP connections on port 22 from anywhere",
      "priority": 65534, "action": "allow", "direction": "inbound", "status": "enabled",
      "targets": [{ "type": "vpc", "value": "minio-vpc" }],
      "filters": { "ports": ["22"], "protocols": [{ "type": "tcp" }] }
    },
    {
      "name": "allow-https-inbound",
      "description": "Allow TCP 443 inbound for MinIO S3 endpoint",
      "priority": 100, "action": "allow", "direction": "inbound", "status": "enabled",
      "targets": [{ "type": "vpc", "value": "minio-vpc" }],
      "filters": { "ports": ["443"], "protocols": [{ "type": "tcp" }] }
    },
    {
      "name": "allow-https-console-inbound",
      "description": "Allow TCP 9443 inbound for themed MinIO Console via Floating IP",
      "priority": 100, "action": "allow", "direction": "inbound", "status": "enabled",
      "targets": [{ "type": "vpc", "value": "minio-vpc" }],
      "filters": { "ports": ["9443"], "protocols": [{ "type": "tcp" }] }
    }
  ]
}
EOF

oxide vpc firewall-rules update --project minio-poc --vpc minio-vpc --json-body /tmp/firewall-rules.json > /dev/null
echo "Firewall updated. Rules:"
oxide vpc firewall-rules view --project minio-poc --vpc minio-vpc | jq '.rules[] | .name'

# 2. Updated HAProxy config: keep existing S3 frontend, add Console frontend on 9443
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

frontend minio_console_https
    bind :9443 ssl crt /etc/haproxy/certs/minio-lb.pem alpn http/1.1
    default_backend minio_console_backend

backend minio_console_backend
    balance roundrobin
    default-server check inter 5s rise 2 fall 3 maxconn 1000
    server minio-inst-1 minio-inst-1:9001
    server minio-inst-2 minio-inst-2:9001
    server minio-inst-3 minio-inst-3:9001
    server minio-inst-4 minio-inst-4:9001
EOF

# 3. Push to both LBs and reload
FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB1_PRIV=$(oxide instance nic list --project minio-poc --instance lb-1 | jq -r '.[] | .ip_stack.value.v4.ip')
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

# Note: FIP is sticky on lb-2 after the failover drill. SSH to whichever LB has the FIP via FIP, the other via ProxyJump
# For safety, use ProxyJump through inst-1 for both LBs
echo ""
echo "=== lb-1 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/haproxy.cfg ubuntu@$LB1_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB1_PRIV "sudo install -o root -g root -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && rm /tmp/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"

echo ""
echo "=== lb-2 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/haproxy.cfg ubuntu@$LB2_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo install -o root -g root -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && rm /tmp/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"

rm /tmp/haproxy.cfg /tmp/firewall-rules.json

echo ""
echo "=== Done. Test in browser: https://$FIP:9443 ==="
echo "Self-signed cert warning is expected. Log in with the MinIO root creds."