#region COMMON
variable "prefix" {
  type = string
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "region_code" {
  type = string
}

variable "region_name" {
  type = string
}

variable "responsible_party" {
  type = string
}

variable "owner" {
  type = string
}
#endregion

#region Network
variable "vpc_cidr" {
  type = string

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  type = list(string)

  validation {
    condition = length(var.availability_zones) >= 2
    error_message = "Provide at least two Availability Zones."
  }
}

variable "nat_gateway_count" {
  type = number
}
#endregion

#region ECS
variable "container_port" {
  type = number
  default = 8000
}

variable "image_tag" {
  type = string
  default = "latest-placeholder"
}

variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "desired_count" {
  type = number
}

variable "enable_autoscaling" {
  type = bool
}

variable "autoscaling_min_capacity" {
  type = number
}

variable "autoscaling_max_capacity" {
  type = number
}

variable "autoscaling_cpu_target" {
  type = number
}

variable "log_retention_days" {
  type = number
}

variable "enable_container_insights" {
  type = bool
}
#endregion

#region Database
variable "db_name" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}

variable "db_max_allocated_storage" {
  type = number
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_deletion_protection" {
  type = bool
}

variable "db_skip_final_snapshot" {
  type = bool
}
#endregion

#region Monitoring
variable "alarm_email" {
  type = string
}

variable "enable_full_alarms" {
  type = bool
}

variable "monthly_budget_usd" {
  type = number
}
#endregion
