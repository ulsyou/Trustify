#region SNS Alert Topic
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol = "email"
  endpoint = var.alarm_email
}
#endregion

#region Essential Alarms
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name = "${var.name_prefix}-alb-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "HTTPCode_Target_5XX_Count"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Sum"
  threshold = 5
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup = var.target_group_arn_suffix
  }

  tags = {
    Name = "${var.name_prefix}-alb-target-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name = "${var.name_prefix}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "MemoryUtilization"
  namespace = "AWS/ECS"
  period = 60
  statistic = "Average"
  threshold = 85
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = {
    Name = "${var.name_prefix}-ecs-memory-high"
  }
}
#endregion

#region Full Alarms
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.enable_full_alarms ? 1 : 0

  alarm_name = "${var.name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "UnHealthyHostCount"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Maximum"
  threshold = 0
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup = var.target_group_arn_suffix
  }

  tags = {
    Name = "${var.name_prefix}-alb-unhealthy-hosts"
  }
}

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  count = var.enable_full_alarms ? 1 : 0

  alarm_name = "${var.name_prefix}-alb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "TargetResponseTime"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Average"
  threshold = 1
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup = var.target_group_arn_suffix
  }

  tags = {
    Name = "${var.name_prefix}-alb-high-latency"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  count = var.enable_full_alarms ? 1 : 0

  alarm_name = "${var.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/ECS"
  period = 60
  statistic = "Average"
  threshold = 80
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = {
    Name = "${var.name_prefix}-ecs-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.enable_full_alarms ? 1 : 0

  alarm_name = "${var.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/RDS"
  period = 60
  statistic = "Average"
  threshold = 80
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = {
    Name = "${var.name_prefix}-rds-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  count = var.enable_full_alarms ? 1 : 0

  alarm_name = "${var.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = 2
  metric_name = "FreeStorageSpace"
  namespace = "AWS/RDS"
  period = 60
  statistic = "Average"
  threshold = 5000000000
  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = {
    Name = "${var.name_prefix}-rds-storage-low"
  }
}
#endregion
