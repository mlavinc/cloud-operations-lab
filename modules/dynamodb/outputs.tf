output "table_name" {
  description = "Name of the DynamoDB ops-logs table. Stored in SSM Parameter Store so scripts can read it without hardcoding."
  value       = aws_dynamodb_table.ops_logs.name
}

output "table_arn" {
  description = "ARN of the DynamoDB ops-logs table. Used to scope the EC2 IAM policy to this table only."
  value       = aws_dynamodb_table.ops_logs.arn
}
