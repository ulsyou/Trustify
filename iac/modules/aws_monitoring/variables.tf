#region Monitoring Variables
variable "name_prefix" {
  type = string
}

variable "alarm_email" {
  type = string
}

variable "enable_full_alarms" {
  type = bool
  default = false
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "rds_instance_id" {
  type = string
}
#endregion
