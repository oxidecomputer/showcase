#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: PROJECT=<project> $0 <image-id> <user-data-file>" >&2
  exit 2
fi

: "${PROJECT:?PROJECT unset}"
IMAGE_ID="$1"
USER_DATA_FILE="$2"
NAME="${NAME:-claude-self-hosted-orchestrator}"
VPC_NAME="${VPC_NAME:-default}"
SUBNET_NAME="${SUBNET_NAME:-default}"
IP_POOL="${IP_POOL:-}"
SSH_KEY_ID="${SSH_KEY_ID:-}"
NCPUS="${NCPUS:-2}"
MEMORY_GIB="${MEMORY_GIB:-4}"
DISK_GIB="${DISK_GIB:-20}"

USER_DATA_B64="$(base64 -w0 < "$USER_DATA_FILE")"

body="$(mktemp)"
trap 'rm -f "$body"' EXIT INT TERM

jq -n \
  --arg name "$NAME" \
  --arg image_id "$IMAGE_ID" \
  --arg vpc "$VPC_NAME" \
  --arg subnet "$SUBNET_NAME" \
  --arg ip_pool "$IP_POOL" \
  --arg ssh_key_id "$SSH_KEY_ID" \
  --arg user_data "$USER_DATA_B64" \
  --argjson ncpus "$NCPUS" \
  --argjson memory "$((MEMORY_GIB * 1024 * 1024 * 1024))" \
  --argjson disk_size "$((DISK_GIB * 1024 * 1024 * 1024))" \
  '{
    name: $name,
    description: "Claude self-hosted environment orchestrator.",
    hostname: $name,
    ncpus: $ncpus,
    memory: $memory,
    start: true,
    auto_restart_policy: "best_effort",
    boot_disk: {
      type: "create",
      name: $name,
      description: "Claude self-hosted environment orchestrator boot disk.",
      size: $disk_size,
      disk_backend: {
        type: "distributed",
        disk_source: {type: "image", image_id: $image_id}
      }
    },
    network_interfaces: {
      type: "create",
      params: [{
        name: "net0",
        description: "Claude self-hosted environment orchestrator network interface.",
        vpc_name: $vpc,
        subnet_name: $subnet
      }]
    },
    external_ips: (if $ip_pool == "" then [] else [{
      type: "ephemeral",
      pool_selector: {type: "explicit", pool: $ip_pool}
    }] end),
    ssh_public_keys: (if $ssh_key_id == "" then [] else [$ssh_key_id] end),
    user_data: $user_data
  }' > "$body"

oxide instance create --project "$PROJECT" --json-body "$body"
