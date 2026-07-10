# ---------------------------------------------------------------------------
# Operational Logs Table
#
# Stores structured records written by automation scripts running on the
# EC2 instance. Not application data — operational telemetry and events.
#
# Schema:
#   PK  instance_id    (String) — partitions records by EC2 instance
#   SK  log_timestamp  (String) — ISO8601; lexicographic = chronological sort
#   TTL ttl            (Number) — Unix epoch; DynamoDB auto-deletes expired items
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "ops_logs" {
  name         = "${var.project_name}-${var.environment}-ops-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "instance_id"
  range_key    = "log_timestamp"

  attribute {
    name = "instance_id"
    type = "S"
  }

  attribute {
    name = "log_timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ops-logs"
  }
}
