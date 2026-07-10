# ---------------------------------------------------------------------------
# DynamoDB Ops-Logs Table
#
# Stores structured operational log entries written by the automation scripts
# running on the EC2 instance. Each item represents one event.
#
# Key design:
#   Partition key — instance_id (String): groups events per instance.
#   Sort key      — log_timestamp (String, ISO 8601): enables time-range queries
#                   within a partition.
#
# PAY_PER_REQUEST billing: no capacity planning required; Free Tier compatible.
# TTL is enabled on the 'ttl' attribute so old entries expire automatically
# without manual cleanup. Scripts write a Unix epoch value 30 days in the future.
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
