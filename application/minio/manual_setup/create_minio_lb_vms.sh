#!/usr/bin/env bash
# create-lb-vms.sh
# NO set -e - the HTTP timeout is expected; the operation continues in background

IMAGE_ID="9c6ece68-b835-49dc-b642-3f4f33aa7969"
SSH_KEY_NAME="jatinder-workstation"
PROJECT="minio-poc"

for n in 1 2; do
  echo "=== Submitting create for lb-${n} ==="

  cat > /tmp/lb-${n}.json <<EOF
{
  "name": "lb-${n}",
  "hostname": "lb-${n}",
  "description": "HAProxy LB ${n} of 2",
  "ncpus": 2,
  "memory": 4294967296,
  "start": true,
  "boot_disk": {
    "type": "create",
    "name": "lb-${n}-os",
    "description": "Boot disk for lb-${n}",
    "size": 21474836480,
    "disk_backend": {"type": "distributed",
    "disk_source": {
      "type": "image",
      "image_id": "${IMAGE_ID}"
     }
    }
  },
  "disks": [],
  "network_interfaces": {
    "type": "create",
    "params": [
      {
        "name": "minio-lb-${n}-nic",
        "description": "Primary NIC in minio-vpc",
        "vpc_name": "minio-vpc",
        "subnet_name": "minio-subnet"
      }
    ]
  },
  "external_ips": [],
  "ssh_public_keys": ["${SSH_KEY_NAME}"],
  "anti_affinity_groups": ["lb-spread"]
}
EOF

  oxide api \
    --method POST "/v1/instances?project=${PROJECT}" \
    --input /tmp/lb-${n}.json &
done

wait
echo "All submissions complete. Check status with: oxide instance list --project minio-poc"