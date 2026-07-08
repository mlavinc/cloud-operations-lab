# ---------------------------------------------------------------------------
# AMI Data Source
# Resolves the latest Amazon Linux 2023 AMI at plan time.
# Using a data source keeps the code region-agnostic and always current.
# Amazon Linux 2023 ships the SSM agent preinstalled.
# ---------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Security Group
# No inbound rules: SSM Session Manager requires no open inbound ports.
# Egress allowed so the SSM agent can reach AWS service endpoints.
# ---------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-sg"
  description = "Security group for the ops EC2 instance. No inbound SSH - managed via SSM."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic for SSM agent and OS updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "ops" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.instance_profile_name
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  user_data_replace_on_change = true

  # No key_name - SSH access is intentionally disabled.
  # All access is via SSM Session Manager.

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail

# Amazon Linux 2023 uses systemd-journald by default and does not create
# /var/log/messages or /var/log/secure. Install rsyslog first so journald
# forwards log events to it, creating the traditional plain-text log files
# that the CloudWatch agent can collect.
dnf install -y rsyslog
systemctl enable --now rsyslog

# Install the CloudWatch agent (not preinstalled on Amazon Linux 2023)
dnf install -y amazon-cloudwatch-agent

# Write the CloudWatch agent configuration.
# Collects system logs and memory/disk metrics not available by default.
# {instance_id} is a CloudWatch agent placeholder resolved at runtime.
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${var.log_group_name}",
            "log_stream_name": "{instance_id}/messages"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${var.log_group_name}",
            "log_stream_name": "{instance_id}/secure"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      }
    }
  }
}
CWCONFIG

# Start the agent as a systemd service and enable it to survive reboots
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-ops-instance"
  }
}
