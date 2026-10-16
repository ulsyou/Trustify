#region Security Groups Variables
variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "container_port" {
  type = number
  default = 8000
}

variable "db_port" {
  type = number
  default = 5432
}
#endregion
