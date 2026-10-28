#!/bin/sh
set -eu

# Deletes the provider, then every orb instance and disk left in the project
# from config.env. With DELETE_IMAGES=1, also deletes the orb images built in
# that project.

if [ "$#" -ne 1 ]; then
  echo "usage: [DELETE_IMAGES=1] $0 <config.env>" >&2
  exit 2
fi

CONFIG_FILE="$1"
PROJECT="$(sed -n 's/^OXIDE_ORB_PROJECT=//p' "$CONFIG_FILE" | tail -n 1)"
: "${PROJECT:?OXIDE_ORB_PROJECT unset in $CONFIG_FILE}"
NAME="${NAME:-amp-orb-provider}"
DELETE_IMAGES="${DELETE_IMAGES:-0}"

# Prints the names of resources of the given type that start with a prefix.
names() {
  oxide "$1" list --project "$PROJECT" \
    | jq -r --arg p "$2" '.[] | select(.name | startswith($p)) | .name'
}

# Prints the instance's run state, or nothing if it does not exist.
instance_state() {
  if out="$(oxide instance view --project "$PROJECT" --instance "$1" 2>&1)"; then
    printf '%s' "$out" | jq -r .run_state
  elif ! printf '%s' "$out" | grep -q ObjectNotFound; then
    printf '%s\n' "$out" >&2
    return 1
  fi
}

# Stops and deletes the instance if it exists.
remove_instance() {
  state="$(instance_state "$1")"
  [ -n "$state" ] || return 0
  case "$state" in
    stopped | failed | stopping) ;;
    *)
      echo "Stopping instance $1"
      oxide instance stop --project "$PROJECT" --instance "$1" >/dev/null
      ;;
  esac
  i=0
  while [ "$state" != stopped ] && [ "$state" != failed ]; do
    i=$((i + 1))
    if [ "$i" -gt 120 ]; then
      echo "timed out waiting for $1 to stop" >&2
      exit 1
    fi
    sleep 1
    state="$(instance_state "$1")"
  done
  echo "Deleting instance $1"
  oxide instance delete --project "$PROJECT" --instance "$1" >/dev/null
}

# Remove the provider first so it cannot spawn orbs during cleanup.
remove_instance "$NAME"

# Orb instances and disks are named amp-<uuid>.
for name in $(names instance amp-); do
  remove_instance "$name"
done

for name in $(names disk amp-); do
  echo "Deleting disk $name"
  oxide disk delete --project "$PROJECT" --disk "$name" >/dev/null
done

if [ "$DELETE_IMAGES" = 1 ]; then
  for name in $(names image amp-orb-); do
    echo "Deleting image $name"
    oxide image delete --project "$PROJECT" --image "$name" >/dev/null
  done
fi
