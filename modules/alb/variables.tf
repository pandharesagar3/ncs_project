variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "enable_https" {
  description = "Enable an HTTPS (443) listener. Requires acm_certificate_arn."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener (required if enable_https = true)."
  type        = string
  default     = ""
}

variable "enable_access_logs" {
  description = "Enable ALB access logs to S3."
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs (created in root module)."
  type        = string
  default     = ""
}

variable "health_check_path" {
  type    = string
  default = "/healthz.php"
}

variable "tags" {
  type    = map(string)
  default = {}
}
