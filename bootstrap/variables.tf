variable "aws_region" {
  description = "AWS region where the backend resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "cloud-ops-lab"
}

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket that stores Terraform state. S3 bucket names are global across all AWS accounts, so this has no default - you must supply a unique value."
  type        = string
}

variable "lock_table_name" {
  description = "Name for the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "cloud-ops-lab-tf-locks"
}
