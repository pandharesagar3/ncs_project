locals {
  name = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Security Groups — strictly layered: internet -> ALB -> App -> DB
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Internet-facing ALB: allow inbound HTTP/HTTPS from allowed CIDRs only"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    description = "To app tier only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${local.name}-alb-sg" })
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "App tier: allow HTTP only from ALB SG, all egress for patching/SSM/DB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH (break-glass only; SSM preferred)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  egress {
    description = "All outbound (NAT-routed for updates/SSM/DB)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name}-app-sg" })
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "Data tier: allow DB port only from app tier SG, no egress to internet"
  vpc_id      = var.vpc_id

  ingress {
    description     = "DB access from app tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Intra-VPC only (cluster replication)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${local.name}-db-sg" })
}

# ---------------------------------------------------------------------------
# KMS — shared CMK for EBS, Aurora storage, Secrets Manager, CloudWatch Logs
# ---------------------------------------------------------------------------
resource "aws_kms_key" "this" {
  description             = "${local.name} CMK for at-rest encryption (EBS, RDS, Secrets Manager, Logs)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${local.name}-kms" })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# IAM — EC2 instance role, least privilege: SSM core + CloudWatch agent +
# read-only access to the single DB secret (scoped by ARN in database module
# via a separate policy attachment once the secret exists).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app_instance" {
  name = "${local.name}-app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app_instance" {
  name = "${local.name}-app-instance-profile"
  role = aws_iam_role.app_instance.name
}
