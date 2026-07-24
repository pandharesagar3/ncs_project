output "cluster_id" {
  value = aws_rds_cluster.this.id
}

output "cluster_endpoint" {
  description = "Writer endpoint."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Load-balanced reader endpoint."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_creds.arn
}

output "db_name" {
  value = aws_rds_cluster.this.database_name
}
