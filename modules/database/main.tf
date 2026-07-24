locals {
  name = "${var.project_name}-${var.environment}"
}

resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = var.data_subnet_ids
  tags       = merge(var.tags, { Name = "${local.name}-db-subnet-group" })
}

# ---------------------------------------------------------------------------
# Secrets Manager — master credentials. App tier reads this at boot instead
# of embedding credentials in user-data / AMI / SSM parameters in plaintext.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_creds" {
  name                    = "${local.name}-db-credentials"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    dbname   = var.db_name
    engine   = "mysql"
  })
}

# ---------------------------------------------------------------------------
# Aurora MySQL Serverless v2 — writer + N readers, Multi-AZ by nature
# (cluster storage is distributed across 3 AZs regardless of instance count;
# reader instances additionally provide compute-level failover + read scaling).
# ---------------------------------------------------------------------------
resource "aws_rds_cluster" "this" {
  cluster_identifier     = "${local.name}-aurora"
  engine                 = "aurora-mysql"
  engine_mode            = "provisioned"
  engine_version         = var.engine_version
  database_name          = var.db_name
  master_username        = var.master_username
  master_password        = random_password.master.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]

  storage_encrypted   = true
  kms_key_id          = var.kms_key_id
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-aurora-final-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity_acu
    max_capacity = var.max_capacity_acu
  }

  tags = merge(var.tags, { Name = "${local.name}-aurora" })

  lifecycle {
    ignore_changes = [master_password] # rotated via Secrets Manager, not TF diffs
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name}-aurora-writer"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  performance_insights_enabled = true
  performance_insights_kms_key_id = var.kms_key_id

  tags = merge(var.tags, { Name = "${local.name}-aurora-writer" })
}

resource "aws_rds_cluster_instance" "reader" {
  count              = var.reader_count
  identifier         = "${local.name}-aurora-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  performance_insights_enabled = true
  performance_insights_kms_key_id = var.kms_key_id

  tags = merge(var.tags, { Name = "${local.name}-aurora-reader-${count.index}" })
}
