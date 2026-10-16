locals {
  name_prefix = "${var.prefix}-${var.project}-${var.environment}"
}

#region Network Module
module "network" {
  source = "../../modules/aws_network"

  name_prefix = local.name_prefix
  vpc_cidr = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_gateway_count = var.nat_gateway_count
}
#endregion

#region Security Groups Module
module "security_groups" {
  source = "../../modules/aws_security_groups"

  name_prefix = local.name_prefix
  vpc_id = module.network.vpc_id
  container_port = var.container_port
}
#endregion

#region ALB Module
module "alb" {
  source = "../../modules/aws_alb"

  name_prefix = local.name_prefix
  vpc_id = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  container_port = var.container_port
}
#endregion

#region ECR Module
module "ecr" {
  source = "../../modules/aws_ecr"

  name_prefix = local.name_prefix
  image_tag_mutability = "MUTABLE"
}
#endregion

#region RDS Module
module "rds" {
  source = "../../modules/aws_rds"

  name_prefix = local.name_prefix
  db_subnet_group_name = module.network.database_subnet_group_name
  db_security_group_id = module.security_groups.db_security_group_id
  db_name = var.db_name
  db_instance_class = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage
  db_multi_az = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  db_deletion_protection = var.db_deletion_protection
  db_skip_final_snapshot = var.db_skip_final_snapshot
}
#endregion

#region ECS Module
module "ecs" {
  source = "../../modules/aws_ecs"

  name_prefix = local.name_prefix
  region = var.region
  vpc_id = module.network.vpc_id
  app_subnet_ids = module.network.app_subnet_ids
  app_security_group_id = module.security_groups.app_security_group_id
  target_group_arn = module.alb.target_group_arn
  container_port = var.container_port
  image_url = "${module.ecr.repository_url}:latest"
  task_cpu = var.task_cpu
  task_memory = var.task_memory
  desired_count = var.desired_count
  enable_autoscaling = var.enable_autoscaling
  autoscaling_min_capacity = var.autoscaling_min_capacity
  autoscaling_max_capacity = var.autoscaling_max_capacity
  autoscaling_cpu_target = var.autoscaling_cpu_target
  log_retention_days = var.log_retention_days
  enable_container_insights = var.enable_container_insights
  environment_variables = [
    {
      name = "APP_ENV"
      value = var.environment
    }
  ]
  secrets = [
    {
      name = "DATABASE_URL"
      valueFrom = "${module.rds.db_secret_arn}:database_url::"
    },
    {
      name = "DB_HOST"
      valueFrom = "${module.rds.db_secret_arn}:host::"
    },
    {
      name = "DB_PORT"
      valueFrom = "${module.rds.db_secret_arn}:port::"
    },
    {
      name = "DB_NAME"
      valueFrom = "${module.rds.db_secret_arn}:dbname::"
    },
    {
      name = "DB_USER"
      valueFrom = "${module.rds.db_secret_arn}:username::"
    },
    {
      name = "DB_PASSWORD"
      valueFrom = "${module.rds.db_secret_arn}:password::"
    }
  ]
}
#endregion

#region Monitoring Module
module "monitoring" {
  source = "../../modules/aws_monitoring"

  name_prefix = local.name_prefix
  alarm_email = var.alarm_email
  enable_full_alarms = var.enable_full_alarms
  alb_arn_suffix = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  rds_instance_id = module.rds.db_instance_id
}
#endregion
