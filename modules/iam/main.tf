# ---------------------------------------------------------------------------
# Data sources
#
# These are read at plan time and used to build ARNs for the inline policy.
# Using data sources avoids hard-coding account IDs and regions.
# ---------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM Role
# The trust policy allows the EC2 service to assume this role.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-ssm-role"
  }
}

# ---------------------------------------------------------------------------
# Policy Attachments
# ---------------------------------------------------------------------------

# Minimum permissions for SSM Session Manager (Sprint 1)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Permissions for the CloudWatch agent to publish logs and metrics (Sprint 2)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---------------------------------------------------------------------------
# Instance Profile
# EC2 instances cannot attach an IAM role directly — they require an
# instance profile as the carrier. The profile wraps the role.
# ---------------------------------------------------------------------------

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-ssm-profile"
  }
}

# ---------------------------------------------------------------------------
# Ops Automation Inline Policy (Sprint 3, conditional)
#
# Allows the EC2 instance to:
#   - Write log entries to the DynamoDB ops-logs table (PutItem only)
#   - Read its own runtime config from SSM Parameter Store (GetParameter only)
#
# count uses a boolean variable (enable_ops_automation) rather than checking
# var.dynamodb_table_arn directly. A computed ARN is not known until apply,
# which would cause Terraform to fail at plan time with "count depends on
# resource attributes that cannot be determined until apply". A boolean
# variable is known at plan time and avoids this error.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "ops_automation" {
  count = var.enable_ops_automation ? 1 : 0

  name = "${var.project_name}-${var.environment}-ops-automation"
  role = aws_iam_role.ec2_ssm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBPutItem"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid      = "SSMGetParameter"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/config"
      }
    ]
  })
}
