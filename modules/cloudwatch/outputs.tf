output "log_group_name" {
  description = "Name of the CloudWatch log group. Passed to the EC2 module for CloudWatch agent configuration."
  value       = aws_cloudwatch_log_group.ops.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for alarm notifications"
  value       = aws_sns_topic.ops_alerts.arn
}
