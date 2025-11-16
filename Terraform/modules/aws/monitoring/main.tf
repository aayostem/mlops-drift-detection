# terraform/modules/aws/monitoring/main.tf

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ml_platform" {
  for_each = toset(var.log_groups)

  name              = each.value
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = merge(var.tags, {
    Name = each.value
  })
}

# CloudWatch Dashboard for MLOps Platform
resource "aws_cloudwatch_dashboard" "ml_platform" {
  dashboard_name = "${var.project_name}-mlops-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", "ClusterName", "${var.cluster_name}"],
            [".", "cluster_node_count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "EKS Cluster Nodes"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.rds_identifier}"],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeStorageSpace", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "RDS Performance"
        }
      }
    ]
  })
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${var.environment}"
  kms_master_key_id = aws_kms_key.cloudwatch.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-alerts-${var.environment}"
  })
}

# SNS Topic Subscription for Slack
resource "aws_sns_topic_subscription" "slack" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# SNS Topic Subscription for PagerDuty
resource "aws_sns_topic_subscription" "pagerduty" {
  count     = var.pagerduty_integration_key != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/integration/${var.pagerduty_integration_key}/enqueue"
}

# KMS Key for CloudWatch
resource "aws_kms_key" "cloudwatch" {
  description             = "KMS key for CloudWatch ${var.project_name}-${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-cloudwatch-kms-${var.environment}"
  })
}