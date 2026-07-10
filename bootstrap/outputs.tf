output "state_bucket_name" {
  description = "Name of the S3 bucket that stores Terraform remote state. Use this value in environments/dev/backend.tf."
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = aws_s3_bucket.tf_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking. Use this value in environments/dev/backend.tf."
  value       = aws_dynamodb_table.tf_locks.name
}

output "ci_role_arn" {
  description = "ARN of the GitHub Actions CI IAM role. Add this as a GitHub Actions secret named AWS_CI_ROLE_ARN in your repository settings."
  value       = aws_iam_role.github_ci.arn
}

output "apply_role_arn" {
  description = "ARN of the GitHub Actions apply IAM role. Add this as a GitHub Actions secret named AWS_APPLY_ROLE_ARN in your repository settings."
  value       = aws_iam_role.github_apply.arn
}
