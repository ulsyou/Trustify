#region ALB Variables
variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "container_port" {
  type = number
  default = 8000
}

variable "health_check_path" {
  type = string
  default = "/health"
}
#endregion
