#!/bin/bash
set -euo pipefail

# Usage: log_event.sh <event_type> <message>
# Example: log_event.sh "deployment" "Application updated to v2.1"

EVENT_TYPE="${1:-manual_event}"
MESSAGE="${2:-no message provided}"

# Retrieve instance metadata using IMDSv2.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

INSTANCE_ID=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

REGION=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/placement/region")

# Read the DynamoDB table name from SSM Parameter Store.
SSM_PATH=$(aws ssm get-parameter \
  --region "$REGION" \
  --name "/cloud-ops-lab/dev/config" \
  --query "Parameter.Value" \
  --output text)

DYNAMODB_TABLE=$(echo "$SSM_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin)['dynamodb_table'])")

LOG_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TTL=$(( $(date +%s) + 2592000 ))

aws dynamodb put-item \
  --region "$REGION" \
  --table-name "$DYNAMODB_TABLE" \
  --item "{
    \"instance_id\":   {\"S\": \"$INSTANCE_ID\"},
    \"log_timestamp\": {\"S\": \"$LOG_TIMESTAMP\"},
    \"event_type\":    {\"S\": \"$EVENT_TYPE\"},
    \"message\":       {\"S\": \"$MESSAGE\"},
    \"ttl\":           {\"N\": \"$TTL\"}
  }"

echo "Event logged: [$EVENT_TYPE] $MESSAGE at $LOG_TIMESTAMP"
