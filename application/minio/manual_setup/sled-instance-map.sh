#!/usr/bin/env bash
# Map MinIO instances to sleds
echo "=== Sled placement for MinIO cluster ==="

for sled_id in $(oxide system hardware sled list --profile oxide | jq -r '.[].id'); do
  matches=$(oxide system hardware sled instance-list \
    --profile oxide \
    --sled-id "$sled_id" 2>/dev/null \
    | jq -r '.[] | select(.name | startswith("minio-inst-")) | .name' 2>/dev/null)

  if [ -n "$matches" ]; then
    echo ""
    echo "Sled $sled_id:"
    echo "$matches" | sed 's/^/  - /'
  fi
done

for sled_id in $(oxide system hardware sled list --profile oxide | jq -r '.[].id'); do
  matches=$(oxide system hardware sled instance-list \
    --profile oxide \
    --sled-id "$sled_id" 2>/dev/null \
    | jq -r '.[] | select(.name | startswith("lb-")) | .name' 2>/dev/null)

  if [ -n "$matches" ]; then
    echo ""
    echo "Sled $sled_id:"
    echo "$matches" | sed 's/^/  - /'
  fi
done