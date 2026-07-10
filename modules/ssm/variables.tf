variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region, stored as a Parameter Store value for scripts to retrieve"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB ops-logs table, stored in Parameter Store so scripts do not hardcode it"
  type        = string
}
