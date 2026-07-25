resource "aws_db_subnet_group" "default" {
  name        = "${var.env_name}-rds-subnet-group"
  description = "My DB subnet group keep only private subnet"
  subnet_ids  = var.subnet_ids
  tags        = local.tags
}

resource "aws_db_instance" "postgres_instance" {
  identifier                          = "ncs-demo"
  engine                              = "postgres"
  engine_version                      = "14.9"
  instance_class                      = "db.t3.micro"
  allocated_storage                   = 20
  storage_type                        = "gp2"
  publicly_accessible                 = true
  multi_az                            = false
  db_subnet_group_name                = aws_db_subnet_group.default.name
  vpc_security_group_ids              = ["sg-091ce53a59399a940"]
  parameter_group_name                = "default.postgres14"
  skip_final_snapshot                 = true
  iam_database_authentication_enabled = false
  username                            = var.DBA_ADMIN_USER
  password                            = var.DBA_ADMIN_PASSWORD
  tags                                = local.tags
}



output "database_host" {
  value = aws_db_instance.postgres_instance.address
}




