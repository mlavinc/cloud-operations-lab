#!/bin/bash
# Cloud Operations Lab - Operational Event Logger
#
# Writes a custom operational event record to the DynamoDB ops-logs table.
# Use this to record any significant operational action (deployments, patches,
# config changes, manual interventions).
#
# Deployed via SSM Run Command: {{ TableName }}, {{ EventType }}, {{ Message }}
# are substituted by SSM before execution. For direct execution:
#   export TABLE_NAME=cloud-ops-lab-dev-ops-logs
#   export EVENT_TYPE=manual_test
#   export MESSAGE="Direct execution test"
#   bash log_event.sh

set -euo pipefail

TABLE_NAME="${TABLE_NAME:-{{ TableName }}}"
EVENT_TYPE="${EVENT_TYPE:-{{ EventType }}}"
MESSAGE="${MESSAGE:-{{ Message }}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TTL=$(( $(date +%s) + 2592000 ))

# Retrieve instance identity using IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

printf '{"instance_id":{"S":"%s"},"log_timestamp":{"S":"%s"},"event_type":{"S":"%s"},"message":{"S":"%s"},"ttl":{"N":"%s"}}' \
  "$INSTANCE_ID" "$TIMESTAMP" "$EVENT_TYPE" "$MESSAGE" "$TTL" > /tmp/ops_event_item.json

aws dynamodb put-item --region "$REGION" --table-name "$TABLE_NAME" --item file:///tmp/ops_event_item.json

echo "Event [$EVENT_TYPE] written to $TABLE_NAME: $MESSAGE"
rm -f /tmp/ops_event_item.json
