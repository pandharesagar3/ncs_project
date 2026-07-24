variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "db_sg_id" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "db_name" {
  type    = string
  default = "counterapp"
}

variable "master_username" {
  type    = string
  default = "appadmin"
}

variable "engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
  default     = "8.0.mysql_aurora.3.05.2"
}

variable "min_capacity_acu" {
  description = "Aurora Serverless v2 minimum capacity (ACUs)."
  type        = number
  default     = 0.5
}

variable "max_capacity_acu" {
  description = "Aurora Serverless v2 maximum capacity (ACUs)."
  type        = number
  default     = 4
}

variable "reader_count" {
  description = "Number of Aurora reader instances (0 for dev/cost-savings, >=1 for HA)."
  type        = number
  default     = 1
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "preferred_backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  type    = string
  default = "mon:04:30-mon:05:30"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  description = "Set true only for throwaway/dev environments so `terraform destroy` doesn't require a manual snapshot."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
