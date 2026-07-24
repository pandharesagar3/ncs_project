data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 bucket for ALB access logs (separate from Terraform state bucket)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # dev convenience; set false for prod

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = 90 }
  }
}

# ELB access logging requires a bucket policy. Regions that existed before Aug 2022 use
# a fixed per-region ELB account principal; regions launched after that date instead
# require the elasticloadbalancing.amazonaws.com service principal + SourceAccount
# condition. Including both statements keeps this deployable in any region.
data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LegacyElbAccountWrite"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "NewRegionServicePrincipalWrite"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

# ---------------------------------------------------------------------------
# Security (SGs, KMS, IAM)
# ---------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  enable_ssh        = var.enable_ssh
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = local.common_tags
}

# Scoped Secrets Manager read policy — attached after the DB secret exists.
resource "aws_iam_role_policy" "read_db_secret" {
  name = "${var.project_name}-${var.environment}-read-db-secret"
  role = module.security.app_instance_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = module.database.secret_arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name        = var.project_name
  environment         = var.environment
  data_subnet_ids     = module.network.data_subnet_ids
  db_sg_id            = module.security.db_sg_id
  kms_key_id          = module.security.kms_key_arn
  min_capacity_acu    = var.db_min_capacity_acu
  max_capacity_acu    = var.db_max_capacity_acu
  reader_count        = var.db_reader_count
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  alb_sg_id           = module.security.alb_sg_id
  enable_https        = var.enable_https
  acm_certificate_arn = var.acm_certificate_arn
  enable_access_logs  = true
  access_logs_bucket  = aws_s3_bucket.alb_logs.bucket
  tags                = local.common_tags

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# ---------------------------------------------------------------------------
# App tier (ASG)
# ---------------------------------------------------------------------------
locals {
  user_data = templatefile("${path.module}/../../scripts/user_data.sh.tpl", {
    db_secret_arn = module.database.secret_arn
    db_endpoint   = module.database.cluster_endpoint
    aws_region    = var.aws_region
    cw_namespace  = "${var.project_name}/${var.environment}"
  })
}

module "asg" {
  source = "../../modules/asg"

  project_name            = var.project_name
  environment             = var.environment
  app_subnet_ids          = module.network.app_subnet_ids
  app_sg_id               = module.security.app_sg_id
  instance_profile_name   = module.security.app_instance_profile_name
  target_group_arn        = module.alb.target_group_arn
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  instance_type           = var.instance_type
  min_size                = var.asg_min_size
  max_size                = var.asg_max_size
  desired_capacity        = var.asg_desired_capacity
  user_data               = local.user_data
  kms_key_id              = module.security.kms_key_id
  tags                    = local.common_tags
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  project_name            = var.project_name
  environment             = var.environment
  alert_email             = var.alert_email
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  asg_name                = module.asg.asg_name
  aurora_cluster_id       = module.database.cluster_id
  tags                    = local.common_tags
}
