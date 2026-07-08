# ---------------------------------------------------------------------------
# CloudWatch Log Group
# Destination for logs shipped by the CloudWatch agent on the EC2 instance.
# Retention set to 7 days to stay within Free Tier log storage limits.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ops" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-log-group"
  }
}

# ---------------------------------------------------------------------------
# SNS Topic
# CloudWatch alarms publish here; SNS fans the message out to subscribers.
# Decoupling alarms from notification targets makes the architecture flexible.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "ops_alerts" {
  name = "${var.project_name}-${var.environment}-ops-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-ops-alerts"
  }
}

# ---------------------------------------------------------------------------
# SNS Email Subscription
# After terraform apply, AWS sends a confirmation email.
# The subscription stays pending until you click the confirmation link.
# ---------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "ops_alerts_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# CloudWatch Metric Alarm - CPU Utilization
# Monitors the specific EC2 instance. Fires when CPU exceeds the threshold
# for two consecutive 5-minute periods (10 minutes sustained high CPU).
# Two evaluation periods reduces false positives from transient spikes.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  alarm_description   = "Triggers when EC2 CPU utilization exceeds ${var.cpu_alarm_threshold}% for 10 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]

  tags = {
    Name = "${var.project_name}-${var.environment}-cpu-high"
  }
}
