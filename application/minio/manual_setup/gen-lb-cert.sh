#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
WORKDIR=/tmp/lb-cert
mkdir -p $WORKDIR
cd $WORKDIR

echo "=== Generating self-signed cert for FIP $FIP ==="

# Private key
openssl genrsa -out minio-lb.key 2048

# Self-signed certificate with SAN
openssl req -new -x509 -key minio-lb.key -out minio-lb.crt -days 365 \
  -subj "/CN=minio-s3-endpoint" \
  -addext "subjectAltName=IP:$FIP,DNS:s3.minio-poc.local,DNS:minio-s3-endpoint"

# Combine into a single PEM (HAProxy expects cert + key in one file)
cat minio-lb.crt minio-lb.key > minio-lb.pem
chmod 600 minio-lb.pem

# Sanity check
echo ""
echo "=== Cert details ==="
openssl x509 -in minio-lb.crt -noout -subject -issuer -dates
echo ""
openssl x509 -in minio-lb.crt -noout -text | grep -A1 "Subject Alternative Name"

echo ""
echo "=== Pushing to LBs ==="

# lb-1 via FIP
echo "--- lb-1 ---"
ssh ubuntu@$FIP "sudo mkdir -p /etc/haproxy/certs && sudo chmod 750 /etc/haproxy/certs"
scp minio-lb.pem ubuntu@$FIP:/tmp/
ssh ubuntu@$FIP "sudo install -o root -g root -m 600 /tmp/minio-lb.pem /etc/haproxy/certs/ && rm /tmp/minio-lb.pem && sudo ls -la /etc/haproxy/certs/"

# lb-2 via ProxyJump
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')
echo ""
echo "--- lb-2 ---"
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo mkdir -p /etc/haproxy/certs && sudo chmod 750 /etc/haproxy/certs"
scp -o ProxyJump=ubuntu@$INST1_IP minio-lb.pem ubuntu@$LB2_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "sudo install -o root -g root -m 600 /tmp/minio-lb.pem /etc/haproxy/certs/ && rm /tmp/minio-lb.pem && sudo ls -la /etc/haproxy/certs/"

echo ""
echo "=== Done. Local copy in $WORKDIR (delete after Phase 7 when real certs replace it). ==="