variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources are deployed. Written into the SSM parameter so scripts can reference it without calling the metadata service again."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB ops-logs table. Written into the SSM parameter so scripts can look it up at runtime without hard-coding the table name."
  type        = string
}
