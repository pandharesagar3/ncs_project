variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  description = "Email address subscribed to the operational alerts SNS topic. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "asg_name" {
  type = string
}

variable "aurora_cluster_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
