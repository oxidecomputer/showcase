#!/bin/sh
set -eu

# Launches the orb provider on a stock Debian instance in the same project as
# its orbs. The user-data installs Amp and the Oxide CLI, writes the provider's
# files and configuration, and starts its service.

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <config.env>" >&2
  exit 2
fi

CONFIG_FILE="$1"
PROJECT="$(sed -n 's/^OXIDE_ORB_PROJECT=//p' "$CONFIG_FILE" | tail -n 1)"
: "${PROJECT:?OXIDE_ORB_PROJECT unset in $CONFIG_FILE}"

# The settings in config.env apply to orbs. These apply to the provider
# instance.
IMAGE="${IMAGE:-debian-13}"
NAME="${NAME:-amp-orb-provider}"
VPC_NAME="${VPC_NAME:-default}"
SUBNET_NAME="${SUBNET_NAME:-default}"
IP_POOL="${IP_POOL:-}"
SSH_KEY_ID="${SSH_KEY_ID:-}"
NCPUS="${NCPUS:-2}"
MEMORY_GIB="${MEMORY_GIB:-4}"
DISK_GIB="${DISK_GIB:-20}"

dir="$(cd "$(dirname "$0")" && pwd)"

# Look for the image in the project first, then in the silo.
IMAGE_ID="$( (oxide image view --project "$PROJECT" --image "$IMAGE" 2>/dev/null \
  || oxide image view --image "$IMAGE") | jq -r .id)"

user_data="$(jq -n \
  --rawfile config "$CONFIG_FILE" \
  --rawfile dispatch "$dir/dispatch.sh" \
  --rawfile provider_service "$dir/amp-orb-provider.service" \
  --rawfile install_oxide "$dir/install-oxide.sh" \
  'def file($path; $mode; $content):
    {path: $path, permissions: $mode, owner: "root:root", content: $content};
  {
    package_update: true,
    packages: ["ca-certificates", "curl", "jq", "xz-utils"],
    write_files: [
      file("/etc/amp-orb-provider/config.env"; "0640"; $config),
      file("/usr/local/bin/amp-orb-dispatch"; "0755"; $dispatch),
      file("/etc/systemd/system/amp-orb-provider.service"; "0644"; $provider_service),
      file("/usr/local/sbin/install-oxide"; "0755"; $install_oxide)
    ],
    runcmd: [
      "useradd --system --create-home --home-dir /var/lib/amp-orb-provider --shell /usr/sbin/nologin amp-orb-provider",
      "chgrp -R amp-orb-provider /etc/amp-orb-provider",
      "chmod 0750 /etc/amp-orb-provider",
      "/usr/local/sbin/install-oxide",
      "runuser -u amp-orb-provider -- env HOME=/var/lib/amp-orb-provider bash -c \"curl -fsSL https://ampcode.com/install.sh | bash\"",
      "ln -sf /var/lib/amp-orb-provider/.amp/bin/amp /usr/local/bin/amp",
      "systemctl daemon-reload",
      "systemctl enable --now amp-orb-provider.service",
      "rm -f /var/lib/cloud/instances/*/user-data.txt* /var/lib/cloud/instances/*/cloud-config.txt"
    ]
  }')"
user_data="$(printf '#cloud-config\n%s\n' "$user_data")"

if [ "$(printf '%s\n' "$user_data" | wc -c)" -gt 32768 ]; then
  echo "user-data exceeds Oxide's 32 KiB limit" >&2
  exit 1
fi

jq -n \
  --arg name "$NAME" \
  --arg image_id "$IMAGE_ID" \
  --arg vpc "$VPC_NAME" \
  --arg subnet "$SUBNET_NAME" \
  --arg ip_pool "$IP_POOL" \
  --arg ssh_key_id "$SSH_KEY_ID" \
  --arg user_data "$(printf '%s\n' "$user_data" | base64 -w0)" \
  --argjson ncpus "$NCPUS" \
  --argjson memory "$((MEMORY_GIB * 1024 * 1024 * 1024))" \
  --argjson disk_size "$((DISK_GIB * 1024 * 1024 * 1024))" \
  '{
    name: $name,
    description: "Amp orb provider.",
    hostname: $name,
    ncpus: $ncpus,
    memory: $memory,
    start: true,
    auto_restart_policy: "best_effort",
    boot_disk: {
      type: "create",
      name: $name,
      description: "Amp orb provider boot disk.",
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
        description: "Amp orb provider network interface.",
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
  }' | oxide instance create --project "$PROJECT" --json-body /dev/stdin
