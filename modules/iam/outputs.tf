output "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the EC2 instance"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "role_name" {
  description = "Name of the IAM role attached to the instance profile"
  value       = aws_iam_role.ec2_ssm.name
}

output "role_arn" {
  description = "ARN of the IAM role. Used for scoping permissions in later sprints."
  value       = aws_iam_role.ec2_ssm.arn
}
