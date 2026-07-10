variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "enable_ops_automation" {
  description = "When true, attach the inline ops-automation policy that allows the instance to write to DynamoDB and read from SSM Parameter Store. Set to true when the dynamodb and ssm modules are deployed."
  type        = bool
  default     = false
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB ops-logs table. Used to scope the PutItem permission. Required when enable_ops_automation is true."
  type        = string
  default     = null
}
