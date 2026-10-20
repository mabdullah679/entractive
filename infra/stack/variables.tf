variable "name_prefix" {
  type    = string
  default = "pf-entractive"
}

variable "image_tag" {
  description = "Tag of the resource-server image already pushed to ECR (the pipeline passes the git SHA)."
  type        = string
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "required_role" {
  type    = string
  default = "Resource.Admin"
}
