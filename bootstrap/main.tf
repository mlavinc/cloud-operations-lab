terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "bootstrap"
      ManagedBy   = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# S3 Bucket - Terraform remote state storage
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB Table - Terraform state locking
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tf_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# GitHub OIDC Identity Provider
#
# Registers GitHub's token endpoint as a trusted identity provider in this
# AWS account. GitHub Actions presents a signed JWT; AWS verifies it against
# this provider before issuing temporary credentials.
#
# AWS manages certificate validation for GitHub's OIDC endpoint directly.
# The thumbprint_list is required by the Terraform resource schema but is not
# used for validation by AWS for this provider.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---------------------------------------------------------------------------
# GitHub CI IAM Role
#
# The role GitHub Actions assumes via OIDC. The trust policy is scoped to
# a specific repository using the 'sub' claim so no other GitHub repo can
# assume this role even if they know its ARN.
#
# sub condition uses :* (any ref) — this role only has read access so all
# branches and PRs are permitted. The apply role (Sprint 5) uses a stricter
# condition scoped to the GitHub Environment, not a branch ref.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_ci" {
  name = "${var.project_name}-github-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-ci"
  }
}

# ---------------------------------------------------------------------------
# CI Role - State Backend Policy (inline, scoped to specific resources)
#
# Terraform plan reads and writes the state file and acquires a DynamoDB lock.
# Permissions are scoped to the exact S3 key path and table ARN — no wildcard.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_ci_state_backend" {
  name = "${var.project_name}-github-ci-state-backend"
  role = aws_iam_role.github_ci.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateFileAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tf_state.arn}/dev/terraform.tfstate"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Sid      = "StateLocking"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tf_locks.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CI Role - ReadOnlyAccess (managed policy for infrastructure plan reads)
#
# terraform plan refreshes state by describing every tracked resource across
# EC2, VPC, IAM, SSM, CloudWatch, DynamoDB, SNS, and S3. A custom policy
# listing every required Describe*/Get*/List* action across all those services
# would be 30+ statements with no security benefit since plan never writes.
# ReadOnlyAccess is the documented, practical choice for plan-only CI roles.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "github_ci_readonly" {
  role       = aws_iam_role.github_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# GitHub Apply IAM Role (Sprint 5)
#
# A separate role used exclusively by the apply workflow. Two independent
# security gates must both pass before this role can be assumed:
#
# Gate 1 — GitHub Environment approval: the apply workflow declares
#   'environment: dev', which pauses execution until a designated reviewer
#   approves. The job never starts without explicit human sign-off.
#
# Gate 2 — OIDC sub condition: when a job references 'environment: dev',
#   GitHub sets the OIDC sub claim to 'repo:{org}/{repo}:environment:dev'.
#   The StringEquals condition below matches only this exact value. A rogue
#   workflow that omits the environment declaration gets a different sub claim
#   and cannot assume this role even if it knows the ARN.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_apply" {
  name = "${var.project_name}-github-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:environment:dev"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-apply"
  }
}

# ---------------------------------------------------------------------------
# Apply Role - State Backend Policy
# Identical scope to the plan role: exact S3 key path and table ARN only.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_apply_state_backend" {
  name = "${var.project_name}-github-apply-state-backend"
  role = aws_iam_role.github_apply.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateFileAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tf_state.arn}/dev/terraform.tfstate"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Sid      = "StateLocking"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tf_locks.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Apply Role - Infrastructure Write Policy
#
# terraform apply reads every resource (refresh) then writes changes.
# Each statement is scoped to a single AWS service so permissions are
# auditable in isolation.
#
# iam:PassRole is the most sensitive action here. It is double-scoped:
#   - Resource: only roles matching the project naming convention
#   - Condition: only when passing to the EC2 service (instance profiles)
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "github_apply_infra" {
  name        = "${var.project_name}-github-apply-infra"
  description = "Least-privilege write access for terraform apply on the cloud-ops-lab dev environment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AndVPCManagement"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMRoleAndProfileManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion"
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRoleToEC2Only"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::*:role/${var.project_name}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "DynamoDBManagement"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:UpdateTable",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:DescribeContinuousBackups"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAlarmsManagement"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsManagement"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSManagement"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:ListTagsForResource",
          "sns:TagResource",
          "sns:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMManagement"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DescribeParameters",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource",
          "ssm:ListTagsForResource",
          "ssm:CreateDocument",
          "ssm:DeleteDocument",
          "ssm:UpdateDocument",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:ListDocuments"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_apply_infra" {
  role       = aws_iam_role.github_apply.name
  policy_arn = aws_iam_policy.github_apply_infra.arn
}
