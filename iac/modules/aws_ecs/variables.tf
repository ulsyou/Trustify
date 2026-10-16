#region ECS Variables
variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "container_port" {
  type = number
  default = 8000
}

variable "image_url" {
  type = string
  default = "public.ecr.aws/docker/library/python:3.11-slim"
}

variable "task_cpu" {
  type = number
  default = 256
}

variable "task_memory" {
  type = number
  default = 512
}

variable "desired_count" {
  type = number
  default = 1
}

variable "enable_autoscaling" {
  type = bool
  default = false
}

variable "autoscaling_min_capacity" {
  type = number
  default = 1
}

variable "autoscaling_max_capacity" {
  type = number
  default = 2
}

variable "autoscaling_cpu_target" {
  type = number
  default = 70
}

variable "log_retention_days" {
  type = number
  default = 7
}

variable "enable_container_insights" {
  type = bool
  default = false
}

variable "environment_variables" {
  type = list(object({
    name = string
    value = string
  }))
  default = []
}

variable "secrets" {
  type = list(object({
    name = string
    valueFrom = string
  }))
  default = []
}
#endregion
