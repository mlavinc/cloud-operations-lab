output "table_name" {
  description = "Name of the DynamoDB ops-logs table"
  value       = aws_dynamodb_table.ops_logs.name
}

output "table_arn" {
  description = "ARN of the DynamoDB ops-logs table. Used to scope IAM write permissions."
  value       = aws_dynamodb_table.ops_logs.arn
}
