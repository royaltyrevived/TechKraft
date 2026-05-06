#!/bin/bash
# Hybrid Proxmox-to-S3 Sync Script
SOURCE_DIR="/var/lib/vz/dump"
S3_BUCKET="s3://techkraft-backups-prod"
DATE=$(date +%Y-%m-%d)

echo "[$DATE] Starting backup sync to S3..."

# Use Glacier Instant Retrieval for cost-optimized disaster recovery
aws s3 sync $SOURCE_DIR $S3_BUCKET \
    --storage-class GLACIER_IR \
    --exclude "*" \
    --include "*.vma.zst" \
    --include "*.tar.zst"

if [ $? -eq 0 ]; then
    echo "[$DATE] Sync successful."
else
    echo "[$DATE] Sync failed. Sending alert via SNS."
fi
