variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID to use. Leave empty to auto-select the latest Amazon Linux 2023 AMI."
  type        = string
  default     = ""
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 6
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "cpu_target_value" {
  description = "Target average CPU utilization (%) for target-tracking scaling."
  type        = number
  default     = 50
}

variable "alb_request_count_target" {
  description = "Target ALB requests per target for the second target-tracking policy."
  type        = number
  default     = 500
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "user_data" {
  description = "Rendered user-data script (base64 not required; passed as plain text)."
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for EBS volume encryption."
  type        = string
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
