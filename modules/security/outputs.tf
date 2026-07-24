output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "kms_key_id" {
  value = aws_kms_key.this.key_id
}

output "app_instance_role_name" {
  value = aws_iam_role.app_instance.name
}

output "app_instance_role_arn" {
  value = aws_iam_role.app_instance.arn
}

output "app_instance_profile_name" {
  value = aws_iam_instance_profile.app_instance.name
}
