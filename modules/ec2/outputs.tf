output "instance_id" {
  description = "ID of the EC2 instance. Use this to start an SSM Session Manager session."
  value       = aws_instance.ops.id
}

output "public_ip" {
  description = "Public IP address assigned to the instance"
  value       = aws_instance.ops.public_ip
}

output "security_group_id" {
  description = "ID of the security group attached to the instance"
  value       = aws_security_group.ec2.id
}
