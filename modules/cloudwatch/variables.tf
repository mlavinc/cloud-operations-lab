variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
}

variable "instance_id" {
  description = "ID of the EC2 instance to monitor"
  type        = string
}

variable "alarm_email" {
  description = "Email address to notify when a CloudWatch alarm fires"
  type        = string
}

variable "log_group_name" {
  description = "Name for the CloudWatch log group"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the CloudWatch log group"
  type        = number
  default     = 7
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization percentage that triggers the alarm"
  type        = number
  default     = 80
}
