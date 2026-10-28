#!/bin/sh
set -eu

# Launches the orchestrator on a stock Debian instance in the same project,
# VPC, and subnet as its runners. The user-data installs Claude Code and the
# Oxide CLI, writes the orchestrator's files and configuration, and starts its
# services.

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <config.env>" >&2
  exit 2
fi

CONFIG_FILE="$1"
config_value() {
  sed -n "s/^$1=//p" "$CONFIG_FILE" | tail -n 1
}
PROJECT="$(config_value PROJECT)"
: "${PROJECT:?PROJECT unset in $CONFIG_FILE}"
VPC_NAME="$(config_value VPC_NAME)"
VPC_NAME="${VPC_NAME:-default}"
SUBNET_NAME="$(config_value SUBNET_NAME)"
SUBNET_NAME="${SUBNET_NAME:-default}"

# The remaining settings in config.env apply to runners. These apply to the
# orchestrator instance.
IMAGE="${IMAGE:-debian-13}"
NAME="${NAME:-claude-self-hosted-orchestrator}"
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
  --rawfile spawn_runner "$dir/hooks/spawn-runner" \
  --rawfile reaper "$dir/bin/claude-self-hosted-reaper" \
  --rawfile orchestrator_service "$dir/claude-self-hosted-orchestrator.service" \
  --rawfile reaper_service "$dir/claude-self-hosted-reaper.service" \
  --rawfile reaper_timer "$dir/claude-self-hosted-reaper.timer" \
  --rawfile install_oxide "$dir/install-oxide.sh" \
  --rawfile install_claude "$dir/../runner/install-claude.sh" \
  'def file($path; $mode; $content):
    {path: $path, permissions: $mode, owner: "root:root", content: $content};
  {
    package_update: true,
    packages: ["ca-certificates", "curl", "gnupg", "jq", "xz-utils"],
    write_files: [
      file("/etc/claude-self-hosted/config.env"; "0640"; $config),
      file("/etc/claude-self-hosted/hooks/spawn-runner"; "0755"; $spawn_runner),
      file("/usr/local/bin/claude-self-hosted-reaper"; "0755"; $reaper),
      file("/etc/systemd/system/claude-self-hosted-orchestrator.service"; "0644"; $orchestrator_service),
      file("/etc/systemd/system/claude-self-hosted-reaper.service"; "0644"; $reaper_service),
      file("/etc/systemd/system/claude-self-hosted-reaper.timer"; "0644"; $reaper_timer),
      file("/usr/local/sbin/install-oxide"; "0755"; $install_oxide),
      file("/usr/local/sbin/install-claude"; "0755"; $install_claude)
    ],
    runcmd: [
      "useradd --system --create-home --home-dir /var/lib/claude-self-hosted --shell /usr/sbin/nologin claude-self-hosted",
      "chgrp -R claude-self-hosted /etc/claude-self-hosted",
      "chmod 0750 /etc/claude-self-hosted /etc/claude-self-hosted/hooks",
      "/usr/local/sbin/install-oxide",
      "(set -a && . /etc/claude-self-hosted/config.env && exec /usr/local/sbin/install-claude)",
      "systemctl daemon-reload",
      "systemctl enable --now claude-self-hosted-orchestrator.service claude-self-hosted-reaper.timer",
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
  }' | oxide instance create --project "$PROJECT" --json-body /dev/stdin
