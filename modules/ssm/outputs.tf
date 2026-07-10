output "health_check_document_name" {
  description = "Name of the SSM health check Run Command document"
  value       = aws_ssm_document.health_check.name
}

output "log_event_document_name" {
  description = "Name of the SSM log event Run Command document"
  value       = aws_ssm_document.log_event.name
}

output "parameter_path_prefix" {
  description = "SSM Parameter Store path prefix used by this environment"
  value       = "/${var.project_name}/${var.environment}"
}
