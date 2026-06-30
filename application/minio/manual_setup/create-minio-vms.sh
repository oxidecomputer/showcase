#!/usr/bin/env bash
set -euo pipefail

# === Fill these in from step 1 ===
# get image id using, oxide image list --project minio-poc
IMAGE_ID="9c6ece68-b835-49dc-b642-3f4f33aa7969"
# get ssh key name using, oxide current-user ssh-key list
SSH_KEY_NAME="jatinder-workstation"   # or your registered key name

PROJECT="minio-poc"
#external_ip_pool="default"
#as default pool ran out of Ip addresses, we link eng-vpn pool to continue the work
external_ip_pool="eng-vpn"

for n in 2; do
  echo "=== Creating minio-inst-${n} ==="

 cat > /tmp/minio-inst-${n}.json <<EOF
{
  "name": "minio-inst-${n}",
  "hostname": "minio-inst-${n}",
  "description": "MinIO node ${n} of 4",
  "ncpus": 4,
  "memory": 17179869184,
  "start": true,
  "boot_disk": {
    "type": "create",
    "name": "minio-inst-${n}-os",
    "description": "Boot disk for minio-inst-${n}",
    "size": 32212254720,
    "disk_backend": {"type": "distributed",
    "disk_source": {
      "type": "image",
      "image_id": "${IMAGE_ID}"
     }
    }
  },
  "disks": [
    {"type":"create","name":"minio-inst-${n}-dd1","description":"Data disk 1","size":107374182400,"disk_backend":{"type":"local"},"disk_source":{"type":"blank","block_size":4096}},
    {"type":"create","name":"minio-inst-${n}-dd2","description":"Data disk 2","size":107374182400,"disk_backend":{"type":"local"},"disk_source":{"type":"blank","block_size":4096}},
    {"type":"create","name":"minio-inst-${n}-dd3","description":"Data disk 3","size":107374182400,"disk_backend":{"type":"local"},"disk_source":{"type":"blank","block_size":4096}},
    {"type":"create","name":"minio-inst-${n}-dd4","description":"Data disk 4","size":107374182400,"disk_backend":{"type":"local"},"disk_source":{"type":"blank","block_size":4096}}
  ],
  "network_interfaces": {
    "type": "create",
    "params": [
      {
        "name": "minio-inst-${n}-nic",
        "description": "Primary NIC in minio-vpc",
        "vpc_name": "minio-vpc",
        "subnet_name": "minio-subnet"
      }
    ]
  },
  "external_ips": [
    {"type":"ephemeral",
    "pool": "eng-vpn"}
  ],
  "ssh_public_keys": ["${SSH_KEY_NAME}"],
  "anti_affinity_groups": ["minio-spread"]
}
EOF

# Background the create so we don't block on the HTTP wait
  oxide api \
    --method POST "/v1/instances?project=${PROJECT}" \
    --input /tmp/minio-inst-${n}.json &
done

wait
echo "All submissions complete (timeouts are normal, check status with: oxide instance list)"