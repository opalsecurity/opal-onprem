output "rds_hostname" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.opal.endpoint
}

output "rds_reader_hostname" {
  description = "Aurora cluster reader endpoint (load-balanced across reader instances)"
  value       = aws_rds_cluster.opal.reader_endpoint
}

output "rds_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.opal.port
}

output "rds_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.opal.master_username
}

# The master password is intentionally NOT output here (previously this was
# a `sensitive` output holding the plaintext password, which still leaves it
# in the state file). Fetch it from Secrets Manager instead, e.g.:
#   aws secretsmanager get-secret-value --secret-id <rds_password_secret_arn>
output "rds_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master password"
  value       = aws_secretsmanager_secret.db_password.arn
}
