#!/bin/bash
set -euo pipefail

# Retrieve instance metadata using IMDSv2.
# IMDSv2 requires a session token; the single hop-limit prevents SSRF
# from reaching the metadata endpoint.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

INSTANCE_ID=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

REGION=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/placement/region")

# Read the DynamoDB table name from SSM Parameter Store so it does not need
# to be hard-coded in the document or the script.
SSM_PATH=$(aws ssm get-parameter \
  --region "$REGION" \
  --name "/cloud-ops-lab/dev/config" \
  --query "Parameter.Value" \
  --output text)

DYNAMODB_TABLE=$(echo "$SSM_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin)['dynamodb_table'])")

LOG_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# TTL: 30 days from now
TTL=$(( $(date +%s) + 2592000 ))

# Collect health metrics.
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%id,' || echo "unknown")
LOAD_AVG=$(cut -d ' ' -f1 /proc/loadavg)
MEM_FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
DISK_ROOT=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')

STATUS="healthy"

aws dynamodb put-item \
  --region "$REGION" \
  --table-name "$DYNAMODB_TABLE" \
  --item "{
    \"instance_id\":    {\"S\": \"$INSTANCE_ID\"},
    \"log_timestamp\":  {\"S\": \"$LOG_TIMESTAMP\"},
    \"event_type\":     {\"S\": \"health_check\"},
    \"status\":         {\"S\": \"$STATUS\"},
    \"cpu_idle_pct\":   {\"S\": \"$CPU_IDLE\"},
    \"load_avg_1m\":    {\"S\": \"$LOAD_AVG\"},
    \"mem_free_kb\":    {\"S\": \"$MEM_FREE\"},
    \"disk_root_pct\":  {\"S\": \"$DISK_ROOT\"},
    \"ttl\":            {\"N\": \"$TTL\"}
  }"

echo "Health check logged: $STATUS at $LOG_TIMESTAMP"
