#!/usr/bin/env bash
set -euo pipefail

FIP="45.154.216.154"
INST1_IP="45.154.216.180"
LB2_PRIV=$(oxide instance nic list --project minio-poc --instance lb-2 | jq -r '.[] | .ip_stack.value.v4.ip')

OXIDE_CLI_URL="https://github.com/oxidecomputer/oxide.rs/releases/download/v0.16.0+2026032500.0.0/oxide-cli-x86_64-unknown-linux-gnu.tar.xz"

cat > /tmp/install-oxide.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /tmp
curl -fLsS "$OXIDE_CLI_URL" -o oxide.tar.xz
mkdir -p oxide-extract
tar -xJf oxide.tar.xz -C oxide-extract
BIN=\$(find oxide-extract -name oxide -type f -executable | head -1)
echo "Found binary at: \$BIN"
sudo install -m 755 "\$BIN" /usr/local/bin/oxide
oxide version
rm -rf oxide.tar.xz oxide-extract
EOF

echo "=== lb-1 ==="
scp /tmp/install-oxide.sh ubuntu@$FIP:/tmp/
ssh ubuntu@$FIP "bash /tmp/install-oxide.sh"

echo ""
echo "=== lb-2 ==="
scp -o ProxyJump=ubuntu@$INST1_IP /tmp/install-oxide.sh ubuntu@$LB2_PRIV:/tmp/
ssh -o ProxyJump=ubuntu@$INST1_IP ubuntu@$LB2_PRIV "bash /tmp/install-oxide.sh"

rm /tmp/install-oxide.sh