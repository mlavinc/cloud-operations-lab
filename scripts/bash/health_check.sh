#!/bin/bash
# Cloud Operations Lab - Operational Health Check
#
# Collects CPU, memory, and disk utilization and writes a structured record
# to the DynamoDB ops-logs table.
#
# Deployed via SSM Run Command: {{ TableName }} is substituted by SSM before
# execution. For direct execution set TABLE_NAME in your environment:
#   export TABLE_NAME=cloud-ops-lab-dev-ops-logs
#   bash health_check.sh

set -euo pipefail

# {{ TableName }} is substituted by the SSM document parameter before execution.
# The ${TABLE_NAME:-...} form means: use the env var if set, else use the SSM value.
TABLE_NAME="${TABLE_NAME:-{{ TableName }}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TTL=$(( $(date +%s) + 2592000 ))

# Retrieve instance identity using IMDSv2 (token-based, required on modern EC2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# CPU utilization from /proc/stat (instantaneous snapshot)
CPU_PERCENT=$(grep '^cpu ' /proc/stat | awk '{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; printf "%.1f", (total-idle)*100/total}')

# Memory utilization from /proc/meminfo
MEM_TOTAL=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($MEM_TOTAL - $MEM_AVAIL) * 100 / $MEM_TOTAL}")

# Root disk utilization
DISK_PERCENT=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')

echo "Instance: $INSTANCE_ID | CPU: ${CPU_PERCENT}% | Memory: ${MEM_PERCENT}% | Disk: ${DISK_PERCENT}%"

# Write DynamoDB item to a temp file to avoid quoting issues with --item inline
printf '{"instance_id":{"S":"%s"},"log_timestamp":{"S":"%s"},"event_type":{"S":"health_check"},"cpu_percent":{"S":"%s"},"memory_percent":{"S":"%s"},"disk_percent":{"S":"%s"},"ttl":{"N":"%s"}}' \
  "$INSTANCE_ID" "$TIMESTAMP" "$CPU_PERCENT" "$MEM_PERCENT" "$DISK_PERCENT" "$TTL" > /tmp/ops_health_item.json

aws dynamodb put-item --region "$REGION" --table-name "$TABLE_NAME" --item file:///tmp/ops_health_item.json

echo "Health check record written to $TABLE_NAME at $TIMESTAMP"
rm -f /tmp/ops_health_item.json
