#region COMMON
variable "prefix" {
  type = string
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
  default = "shr"
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
