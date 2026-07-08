variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which to create the security group"
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet in which to launch the EC2 instance"
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Defaults to t3.micro (Free Tier eligible in most regions)."
  type        = string
  default     = "t3.micro"
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group the agent will ship logs to"
  type        = string
}
