#region ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = {
    Name = "${var.name_prefix}-cluster"
  }
}
#endregion

#region CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.name_prefix}-app"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-log-group"
  }
}
#endregion

#region IAM Roles
resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-ecs-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "${var.name_prefix}-ecs-exec-secrets-policy"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-ecs-task-role"
  }
}
#endregion

#region ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family = "${var.name_prefix}-app"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = tostring(var.task_cpu)
  memory = tostring(var.task_memory)
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name = "${var.name_prefix}-app"
      image = var.image_url
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort = var.container_port
          protocol = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = aws_cloudwatch_log_group.ecs.name
          "awslogs-region" = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = var.environment_variables
      secrets = var.secrets
    }
  ])

  tags = {
    Name = "${var.name_prefix}-task-def"
  }
}
#endregion

#region ECS Service
resource "aws_ecs_service" "this" {
  name = "${var.name_prefix}-service"
  cluster = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count = var.desired_count
  launch_type = "FARGATE"

  network_configuration {
    subnets = var.app_subnet_ids
    security_groups = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name = "${var.name_prefix}-app"
    container_port = var.container_port
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]

  tags = {
    Name = "${var.name_prefix}-service"
  }
}
#endregion

#region ECS Autoscaling
resource "aws_appautoscaling_target" "ecs" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity = var.autoscaling_max_capacity
  min_capacity = var.autoscaling_min_capacity
  resource_id = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name = "${var.name_prefix}-cpu-autoscaling"
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.autoscaling_cpu_target
    scale_in_cooldown = 300
    scale_out_cooldown = 60
  }
}
#endregion
