variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "enable_ops_automation" {
  description = "Set to true to create the scoped inline policy for DynamoDB and SSM access. Must be a literal value (not computed) because it controls resource count."
  type        = bool
  default     = false
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB ops-logs table. Required when enable_ops_automation is true."
  type        = string
  default     = null
}
