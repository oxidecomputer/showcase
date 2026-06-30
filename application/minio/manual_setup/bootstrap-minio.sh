#!/usr/bin/env bash
set -euo pipefail

echo "=== Bootstrapping MinIO node $(hostname) ==="

# Update + packages
sudo apt update
sudo apt upgrade -y
sudo apt install -y xfsprogs curl jq chrony
sudo systemctl enable --now chrony

# minio user
if ! id minio >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /sbin/nologin minio
fi

# Format data disks (skip if already formatted)
for n in 1 2 3 4; do
  if ! sudo blkid /dev/nvme${n}n1 >/dev/null 2>&1; then
    sudo mkfs.xfs -f -L "disk${n}" /dev/nvme${n}n1
  fi
  sudo mkdir -p /mnt/disk${n}
done

# fstab entries by UUID (skip if already there)
for n in 1 2 3 4; do
  uuid=$(sudo blkid -s UUID -o value /dev/nvme${n}n1)
  if ! grep -q "$uuid" /etc/fstab; then
    echo "UUID=${uuid} /mnt/disk${n} xfs defaults,noatime,inode64 0 0" | sudo tee -a /etc/fstab
  fi
done
sudo systemctl daemon-reload
sudo mount -a

# MinIO data subdirectories
for n in 1 2 3 4; do
  sudo mkdir -p /mnt/disk${n}/minio
  sudo chown -R minio:minio /mnt/disk${n}
done

# MinIO binary
if [ ! -x /usr/local/bin/minio ]; then
  sudo curl -L https://dl.min.io/server/minio/release/linux-amd64/minio \
    -o /usr/local/bin/minio
  sudo chmod +x /usr/local/bin/minio
fi

# Environment file (placeholders, Phase 5 finalizes)
sudo tee /etc/default/minio >/dev/null <<'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minio-password
MINIO_VOLUMES=""
MINIO_OPTS="--address :9000 --console-address :9001"
EOF
sudo chown root:minio /etc/default/minio
sudo chmod 640 /etc/default/minio

# Systemd unit
sudo tee /etc/systemd/system/minio.service >/dev/null <<'EOF'
[Unit]
Description=MinIO
Documentation=https://min.io/docs/minio/linux/index.html
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/minio

[Service]
WorkingDirectory=/usr/local
User=minio
Group=minio
ProtectProc=invisible
EnvironmentFile=-/etc/default/minio
ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"MINIO_VOLUMES is not set in /etc/default/minio\"; exit 1; fi"
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
LimitNOFILE=1048576
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable minio

echo "=== Bootstrap complete on $(hostname) ==="
/usr/local/bin/minio --version
df -h /mnt/disk*