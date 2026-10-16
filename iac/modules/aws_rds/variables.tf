#region RDS Variables
variable "name_prefix" {
  type = string
}

variable "db_subnet_group_name" {
  type = string
}

variable "db_security_group_id" {
  type = string
}

variable "db_name" {
  type = string
  default = "appdb"
}

variable "db_username" {
  type = string
  default = "dbadmin"
}

variable "db_instance_class" {
  type = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type = number
  default = 20
}

variable "db_max_allocated_storage" {
  type = number
  default = 20
}

variable "db_multi_az" {
  type = bool
  default = false
}

variable "db_backup_retention_days" {
  type = number
  default = 1
}

variable "db_deletion_protection" {
  type = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type = bool
  default = true
}
#endregion
