#region Monitoring Outputs
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  value = aws_sns_topic.alerts.name
}
#endregion
