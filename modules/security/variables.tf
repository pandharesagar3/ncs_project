variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "allowed_http_cidrs" {
  description = "CIDR ranges allowed to reach the ALB on 80/443. Default = open internet (public-facing app requirement)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_ssh" {
  description = "If true, opens SSH (22) from allowed_ssh_cidrs to app instances. Default false — SSM Session Manager is the preferred access path."
  type        = bool
  default     = false
}

variable "allowed_ssh_cidrs" {
  type    = list(string)
  default = []
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "tags" {
  type    = map(string)
  default = {}
}
