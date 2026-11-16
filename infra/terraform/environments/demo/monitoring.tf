# Step 06 — Supervision (Amazon CloudWatch + SNS).
# Alarmes (status check + CPU) sur les machines critiques + un dashboard.
# Les alertes partent vers un topic SNS (email optionnel via var.alert_email).

variable "alert_email" {
  description = "Adresse email pour recevoir les alertes (vide = pas d'abonnement ; l'email demande une confirmation manuelle)."
  type        = string
  default     = ""
}

locals {
  # Machines supervisées (les serveurs + la passerelle ; les postes restent jetables).
  monitored = {
    dc         = aws_instance.dc.id
    fileserver = aws_instance.fileserver.id
    admin      = aws_instance.admin.id
    vpn        = aws_instance.vpn.id
  }
}

resource "aws_sns_topic" "alerts" {
  name = "ymmo-alerts"
  tags = { Name = "ymmo-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarme : échec du status check (instance défaillante) -> auto-recover + notification
resource "aws_cloudwatch_metric_alarm" "status_check" {
  for_each            = local.monitored
  alarm_name          = "ymmo-${each.key}-status-check-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 3
  dimensions          = { InstanceId = each.value }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_description    = "Status check KO sur ${each.key}"
}

# Alarme : CPU soutenu > 85 %
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each            = local.monitored
  alarm_name          = "ymmo-${each.key}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  period              = 300
  evaluation_periods  = 3
  dimensions          = { InstanceId = each.value }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  alarm_description    = "CPU > 85% sur ${each.key}"
}

resource "aws_cloudwatch_dashboard" "ymmo" {
  dashboard_name = "ymmo"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "CPU (%)"
          region = var.region
          view   = "timeSeries"
          metrics = [for k, id in local.monitored : ["AWS/EC2", "CPUUtilization", "InstanceId", id, { label = k }]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Status check failed"
          region = var.region
          view   = "timeSeries"
          metrics = [for k, id in local.monitored : ["AWS/EC2", "StatusCheckFailed", "InstanceId", id, { label = k }]]
        }
      }
    ]
  })
}

output "monitoring" {
  description = "Supervision CloudWatch"
  value = {
    sns_topic = aws_sns_topic.alerts.arn
    dashboard = aws_cloudwatch_dashboard.ymmo.dashboard_name
  }
}
