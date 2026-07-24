variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "dash-cloudops"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  description = "true = 1 NAT GW false = 1 per AZ "
  type        = bool
  default     = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 6
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "db_min_capacity_acu" {
  type    = number
  default = 0.5
}

variable "db_max_capacity_acu" {
  type    = number
  default = 4
}

variable "db_reader_count" {
  type    = number
  default = 1
}

variable "db_deletion_protection" {
  type    = bool
  default = false 
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true 
}

variable "enable_https" {
  type    = bool
  default = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "alert_email" {
  description = "Email to subscribe to operational CloudWatch alarms via SNS."
  type        = string
  default     = ""
}

variable "enable_ssh" {
  type    = bool
  default = false
}

variable "allowed_ssh_cidrs" {
  type    = list(string)
  default = []
}
