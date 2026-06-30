#!/usr/bin/env bash

n=2

oxide instance stop --project minio-poc --instance minio-inst-${n}

sleep 15

# Wait a few seconds for stop to complete, then:
oxide instance delete --project minio-poc --instance minio-inst-${n}

# Check whether disks were auto-deleted with the instance:
oxide disk list --project minio-poc | grep minio-inst-${n}

# If any minio-inst-2-* disks still exist, delete them:
for d in os dd1 dd2 dd3 dd4; do
  oxide disk delete --project minio-poc --disk "minio-inst-${n}-${d}" 2>/dev/null || true
done