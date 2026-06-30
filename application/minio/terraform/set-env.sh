#!/usr/bin/env bash
# Sets the env vars Terraform needs to talk to Oxide.
# USAGE: source ./set-env.sh
# Don't run with `bash set-env.sh` - the exports wouldn't survive into your shell.

CREDS_FILE="$HOME/.config/oxide/credentials.toml"
PROFILE_NAME="employee-d1ce31bdc66a5171"
SILO_HOST="https://${PROFILE_NAME}.sys.r3.oxide-preview.com"

if [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: $CREDS_FILE not found. Run: oxide auth login --host $SILO_HOST"
  return 1 2>/dev/null || exit 1
fi

# === Approach A (recommended): use OXIDE_PROFILE ===
# The provider reads the profile from credentials.toml directly.
export OXIDE_PROFILE="$PROFILE_NAME"

# === Approach B (alternative): explicit host + token ===
# Uncomment if you want token-based auth instead of profile-based.
# Useful if you need to debug exactly which token TF is using.
#
# export OXIDE_HOST="$SILO_HOST"
# export OXIDE_TOKEN=$(awk -v profile="[profile.$PROFILE_NAME]" '
#   $0 == profile { in_profile = 1; next }
#   /^\[/ && in_profile { in_profile = 0 }
#   in_profile && /^token = / {
#     gsub(/^token = "|"$/, "")
#     print
#     exit
#   }
# ' "$CREDS_FILE")
# if [ -z "$OXIDE_TOKEN" ]; then
#   echo "ERROR: token for profile $PROFILE_NAME not found in $CREDS_FILE"
#   return 1 2>/dev/null || exit 1
# fi

# === Always set: failover credentials (the whole file dropped on LB VMs by cloud-init) ===
export TF_VAR_oxide_credentials_for_failover="$(cat "$CREDS_FILE")"

# === Always set: profile name for the LB watcher so the oxide CLI on the LB
# VMs knows which [profile.X] section to use from credentials.toml. Without
# this the CLI errors "No profile specified and no default profile" when
# credentials.toml has multiple profiles.
export TF_VAR_oxide_profile="$PROFILE_NAME"

# === Confirmation (sensitive values redacted) ===
echo "Terraform env set:"
echo "  OXIDE_PROFILE                          = ${OXIDE_PROFILE:-<unset>}"
echo "  OXIDE_HOST                             = ${OXIDE_HOST:-<unset, using profile>}"
echo "  OXIDE_TOKEN                            = ${OXIDE_TOKEN:+<set, ${#OXIDE_TOKEN} chars>}${OXIDE_TOKEN:-<unset, using profile>}"
echo "  TF_VAR_oxide_credentials_for_failover  = $(printf '%s' "$TF_VAR_oxide_credentials_for_failover" | wc -c | tr -d ' ') bytes"
echo "  TF_VAR_oxide_profile                   = ${TF_VAR_oxide_profile:-<unset>}"