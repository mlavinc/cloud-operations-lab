output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

output "instance_id" {
  description = "ID of the EC2 instance. Use this to start an SSM Session Manager session."
  value       = module.ec2.instance_id
}

output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = module.ec2.public_ip
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.cloudwatch.log_group_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alarm notification topic"
  value       = module.cloudwatch.sns_topic_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB ops-logs table"
  value       = module.dynamodb.table_name
}

output "ssm_health_check_document" {
  description = "Name of the SSM health check Run Command document"
  value       = module.ssm.health_check_document_name
}

output "ssm_log_event_document" {
  description = "Name of the SSM log event Run Command document"
  value       = module.ssm.log_event_document_name
}
