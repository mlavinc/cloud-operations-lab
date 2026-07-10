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
# Sprint 4: sub condition uses :* (any ref) — this role only has read access
# so all branches and PRs are permitted.
# Sprint 5 will introduce a separate apply role scoped to :ref:refs/heads/main.
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
        Sid    = "StateFileAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tf_state.arn}/dev/terraform.tfstate"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Sid    = "StateLocking"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
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
