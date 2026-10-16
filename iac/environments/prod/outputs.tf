#region Network Outputs
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "database_subnet_ids" {
  value = module.network.database_subnet_ids
}

output "database_subnet_group_name" {
  value = module.network.database_subnet_group_name
}
#endregion

#region Security Group Outputs
output "alb_security_group_id" {
  value = module.security_groups.alb_security_group_id
}

output "app_security_group_id" {
  value = module.security_groups.app_security_group_id
}

output "db_security_group_id" {
  value = module.security_groups.db_security_group_id
}
#endregion

#region ALB Outputs
output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "alb_arn" {
  value = module.alb.alb_arn
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}
#endregion

#region ECS Outputs
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  value = module.ecs.task_definition_arn
}

output "ecs_execution_role_arn" {
  value = module.ecs.execution_role_arn
}

output "ecs_task_role_arn" {
  value = module.ecs.task_role_arn
}
#endregion

#region ECR Outputs
output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecr_repository_arn" {
  value = module.ecr.repository_arn
}
#endregion

#region RDS Outputs
output "rds_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "rds_address" {
  value = module.rds.db_instance_address
}

output "rds_secret_arn" {
  value = module.rds.db_secret_arn
}
#endregion

#region Monitoring Outputs
output "alerts_sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}
#endregion
