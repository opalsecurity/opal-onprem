output "rds_hostname" {
  description = "RDS instance hostname"
  value       = aws_db_instance.opal.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.opal.port
}

output "rds_username" {
  description = "RDS instance root username"
  value       = aws_db_instance.opal.username
}

output "rds_password" {
  description = "RDS instance root password"
  value       = random_password.password.result
  sensitive   = true
}

output "exports_bucket_name" {
  description = "S3 bucket name for Opal async exports."
  value       = aws_s3_bucket.exports.id
}

output "exports_iam_user_name" {
  description = "IAM user with scoped access to the exports bucket. Generate an access key for this user (`aws iam create-access-key --user-name <name>`) and paste it into KOTS or Helm. See https://docs.opal.dev/docs/configure-async-exports-storage."
  value       = aws_iam_user.exports.name
}
