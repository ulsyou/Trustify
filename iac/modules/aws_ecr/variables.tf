#region ECR Variables
variable "name_prefix" {
  type = string
}

variable "image_tag_mutability" {
  type = string
  default = "MUTABLE"
}

variable "scan_on_push" {
  type = bool
  default = true
}

variable "max_image_count" {
  type = number
  default = 10
}
#endregion
