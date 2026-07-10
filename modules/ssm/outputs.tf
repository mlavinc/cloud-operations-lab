output "config_parameter_name" {
  description = "Name of the SSM parameter that stores runtime configuration"
  value       = aws_ssm_parameter.config.name
}

output "health_check_document_name" {
  description = "Name of the SSM Run Command document for the health check script"
  value       = aws_ssm_document.health_check.name
}

output "log_event_document_name" {
  description = "Name of the SSM Run Command document for the log event script"
  value       = aws_ssm_document.log_event.name
}
