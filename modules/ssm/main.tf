# ---------------------------------------------------------------------------
# Parameter Store
# Operational configuration stored centrally. Scripts retrieve these values
# at runtime so no configuration is hardcoded in the scripts themselves.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "dynamodb_table_name" {
  name  = "/${var.project_name}/${var.environment}/dynamodb-table-name"
  type  = "String"
  value = var.dynamodb_table_name

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-table-name"
  }
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "/${var.project_name}/${var.environment}/aws-region"
  type  = "String"
  value = var.aws_region

  tags = {
    Name = "${var.project_name}-${var.environment}-aws-region"
  }
}

# ---------------------------------------------------------------------------
# SSM Run Command Documents
#
# Each document reads its script content from the scripts/bash/ directory
# using file(). This keeps the bash files as the single source of truth —
# updating a script automatically updates the SSM document on next apply.
#
# replace() normalises CRLF (\r\n) to LF (\n) before splitting. Without this,
# scripts authored on Windows carry \r on every line, producing #!/bin/bash\r
# as the shebang on Linux, which the kernel cannot resolve (exit 127).
#
# The SSM agent combines the runCommand array into a single script file and
# executes it, so the shebang and blank lines are preserved correctly.
# ---------------------------------------------------------------------------

resource "aws_ssm_document" "health_check" {
  name            = "${var.project_name}-${var.environment}-health-check"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Collect CPU, memory, and disk metrics and write a record to the DynamoDB ops-logs table."
    parameters = {
      TableName = {
        type        = "String"
        description = "DynamoDB ops-logs table name"
        default     = var.dynamodb_table_name
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "runHealthCheck"
        inputs = {
          runCommand = split("\n", trimspace(replace(file("${path.module}/../../scripts/bash/health_check.sh"), "\r\n", "\n")))
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-health-check"
  }
}

resource "aws_ssm_document" "log_event" {
  name            = "${var.project_name}-${var.environment}-log-event"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Write a custom operational event record to the DynamoDB ops-logs table."
    parameters = {
      TableName = {
        type        = "String"
        description = "DynamoDB ops-logs table name"
        default     = var.dynamodb_table_name
      }
      EventType = {
        type        = "String"
        description = "Type of operational event (e.g. deployment, patch, config_change)"
        default     = "manual_event"
      }
      Message = {
        type        = "String"
        description = "Event message to record"
        default     = "Operational log entry"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "runLogEvent"
        inputs = {
          runCommand = split("\n", trimspace(replace(file("${path.module}/../../scripts/bash/log_event.sh"), "\r\n", "\n")))
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-log-event"
  }
}
