#!/usr/bin/env bash
# Dispatch program for self-hosted Amp orbs on Oxide, one VM per thread.
# https://ampcode.com/docs/orbs/self-hosted#dispatch-contract
#
# Run with `amp orb provider /usr/local/bin/amp-orb-dispatch`. Needs the
# `oxide` CLI, authenticated with OXIDE_HOST and OXIDE_TOKEN or a profile, plus
# jq. ORB_IMAGE must name an Oxide image built from orb/.
#
# Oxide cannot save memory, and user data is fixed when an instance is created.
# So the orb's disk outlives its instance: pause deletes the instance and keeps
# the disk, and spawn creates a new instance on that disk with user data that
# carries the new ORB_TOKEN and starts `amp orb bootstrap`. Cloud-init sees a
# new instance ID on each spawn, so it runs the user data again.
#
# ORB_SNAPSHOT_ID is ignored, so every new thread runs .agents/setup.
set -euo pipefail

: "${OXIDE_ORB_PROJECT:?set OXIDE_ORB_PROJECT to the Oxide project for orbs}"
ip_pool="${OXIDE_ORB_IP_POOL:-public}"
ncpus="${OXIDE_ORB_NCPUS:-4}"
memory=$((${OXIDE_ORB_MEMORY_GIB:-8} * 1024 * 1024 * 1024))
disk_size=$((${OXIDE_ORB_DISK_GIB:-20} * 1024 * 1024 * 1024))

# ORB_ID looks like amp-<uuid>. Oxide names must be lowercase, so make sure.
name="${ORB_ID,,}"
project=(--project "$OXIDE_ORB_PROJECT")

# Prints the instance's run state, or nothing if it does not exist.
instance_state() {
	local out
	if out=$(oxide instance view "${project[@]}" --instance "$name" 2>&1); then
		jq -r .run_state <<<"$out"
	elif ! grep -q ObjectNotFound <<<"$out"; then
		echo "$out" >&2
		return 1
	fi
}

disk_exists() {
	local out
	if out=$(oxide disk view "${project[@]}" --disk "$name" 2>&1); then
		return 0
	elif ! grep -q ObjectNotFound <<<"$out"; then
		echo "$out" >&2
		exit 1
	fi
	return 1
}

# Stops and deletes the instance if it exists. Its boot disk is kept.
remove_instance() {
	local state
	state=$(instance_state)
	[[ -n "$state" ]] || return 0
	if [[ "$state" != stopped && "$state" != failed ]]; then
		echo "Stopping instance $name ($state)"
		[[ "$state" == stopping ]] || oxide instance stop "${project[@]}" --instance "$name" >/dev/null
		for _ in $(seq 120); do
			state=$(instance_state)
			[[ "$state" == stopped || "$state" == failed ]] && break
			sleep 1
		done
	fi
	echo "Deleting instance $name"
	oxide instance delete "${project[@]}" --instance "$name" >/dev/null
}

image_id() {
	oxide image view "${project[@]}" --image "$ORB_IMAGE" 2>/dev/null ||
		oxide image view --image "$ORB_IMAGE"
}

user_data() {
	local env=(--setenv=ORB_TOKEN="$ORB_TOKEN")
	[[ -z "${AMP_URL:-}" ]] || env+=(--setenv=AMP_URL="$AMP_URL")
	printf '#!/bin/bash\n'
	printf '%q ' systemd-run --unit=amp-orb-bootstrap --uid=user --gid=user \
		--working-directory=/home/user --setenv=HOME=/home/user --setenv=USER=user \
		"${env[@]}" /bin/bash -lc 'exec amp orb bootstrap'
	printf '\n'
}

spawn() {
	remove_instance

	local boot_disk
	if disk_exists; then
		echo "Resuming orb $name from its disk"
		boot_disk=$(jq -n --arg name "$name" '{type: "attach", name: $name}')
	else
		echo "Creating orb $name from image $ORB_IMAGE"
		boot_disk=$(jq -n --arg name "$name" --arg image "$(image_id | jq -r .id)" \
			--argjson size "$disk_size" '{
				type: "create", name: $name, description: "Amp orb disk", size: $size,
				disk_backend: {type: "distributed", disk_source: {type: "image", image_id: $image}}
			}')
	fi

	jq -n --arg name "$name" --arg pool "$ip_pool" --argjson ncpus "$ncpus" \
		--argjson memory "$memory" --argjson boot_disk "$boot_disk" \
		--arg user_data "$(user_data | base64 -w0)" '{
			name: $name, hostname: $name, description: "Amp orb",
			ncpus: $ncpus, memory: $memory, boot_disk: $boot_disk,
			network_interfaces: {type: "default_ipv4"},
			external_ips: [{type: "ephemeral", pool_selector: {type: "explicit", pool: $pool}}],
			ssh_public_keys: [], user_data: $user_data
		}' | oxide instance create "${project[@]}" --json-body /dev/stdin >/dev/null
	echo "Started instance $name; it starts amp orb bootstrap on boot"
}

case "$ORB_OPERATION" in
spawn) spawn ;;
pause) remove_instance ;;
delete)
	remove_instance
	if disk_exists; then
		echo "Deleting disk $name"
		oxide disk delete "${project[@]}" --disk "$name" >/dev/null
	fi
	;;
*)
	echo "unknown ORB_OPERATION: $ORB_OPERATION" >&2
	exit 1
	;;
esac
