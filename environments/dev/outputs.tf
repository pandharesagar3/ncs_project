output "app_url" {
  description = "URL to access the Increment/Decrement Counter app."
  value       = "http://${module.alb.alb_dns_name}"
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "aurora_writer_endpoint" {
  value = module.database.cluster_endpoint
}

output "aurora_reader_endpoint" {
  value = module.database.reader_endpoint
}

output "cloudwatch_dashboard_name" {
  value = module.monitoring.dashboard_name
}

output "sns_alerts_topic_arn" {
  value = module.monitoring.sns_topic_arn
}
