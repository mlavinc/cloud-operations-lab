# ---------------------------------------------------------------------------
# SSM Parameter Store — runtime configuration
#
# Scripts running on the EC2 instance query this parameter to discover the
# DynamoDB table name and region without hard-coding values. This means
# the same script works across environments by changing only the SSM path.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "config" {
  name = "/${var.project_name}/${var.environment}/config"
  type = "String"
  value = jsonencode({
    dynamodb_table = var.dynamodb_table_name
    region         = var.aws_region
    environment    = var.environment
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-config"
  }
}

# ---------------------------------------------------------------------------
# SSM Run Command Documents
#
# Each document embeds a bash script as the runCommand array. Terraform reads
# the script from disk using file(), normalises CRLF to LF with replace(), and
# splits on newlines. This ensures the document is always created with Unix
# line endings regardless of the host OS, preventing the '#!/bin/bash\r'
# kernel rejection error on Amazon Linux 2023.
#
# schemaVersion "2.2" is required for the aws:runShellScript action.
# ---------------------------------------------------------------------------

resource "aws_ssm_document" "health_check" {
  name          = "${var.project_name}-${var.environment}-health-check"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Run the health check script and write the result to DynamoDB"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "runHealthCheck"
        inputs = {
          runCommand = split("\n", trimspace(replace(
            file("${path.module}/../../scripts/bash/health_check.sh"),
            "\r\n",
            "\n"
          )))
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-health-check"
  }
}

resource "aws_ssm_document" "log_event" {
  name          = "${var.project_name}-${var.environment}-log-event"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Log a named event to DynamoDB with an optional message"
    parameters = {
      EventType = {
        type         = "String"
        description  = "Type of event to log (e.g. deployment, maintenance)"
        defaultValue = "manual_event"
      }
      Message = {
        type         = "String"
        description  = "Free-text description of the event"
        defaultValue = "no message provided"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "runLogEvent"
        inputs = {
          runCommand = split("\n", trimspace(replace(
            file("${path.module}/../../scripts/bash/log_event.sh"),
            "\r\n",
            "\n"
          )))
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-log-event"
  }
}
