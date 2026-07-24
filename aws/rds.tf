# --- Master password: generated, stored in Secrets Manager, and wired into
# the cluster via write-only arguments so the plaintext password is never
# written to the Terraform state or plan file (previously it was a regular
# `random_password` resource stored in state and re-exposed via a sensitive
# output).
#
# Requires Terraform >= 1.11 and aws provider >= 6.43 (see main.tf).
ephemeral "random_password" "db_password" {
  length           = 20
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.db_identifier}-master-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id                = aws_secretsmanager_secret.db_password.id
  secret_string_wo         = ephemeral.random_password.db_password.result
  secret_string_wo_version = 1
}

ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret_version.db_password.secret_id
}

resource "aws_security_group" "rds" {
  name   = "${var.db_identifier}-db"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }
}

resource "aws_db_subnet_group" "opal" {
  name       = var.db_identifier
  subnet_ids = module.vpc.private_subnets
}

# --- Aurora PostgreSQL, replacing the single-instance RDS Postgres setup.
#
# Aurora gives us storage that's replicated across 3 AZs and typically
# fails over to a reader in under 30s, versus RDS Postgres Multi-AZ which
# has no automatic failover between instances - a monitor has to detect the
# failure and promote a replica. This is a bigger change than a version
# bump: migrating an existing RDS Postgres instance to Aurora is a
# snapshot-restore or dump/restore exercise, not an in-place `terraform
# apply`. If you'd rather stay on plain RDS Postgres for now, keep
# `aws_db_instance` and just bump `engine_version` to a supported release
# (see UPGRADE_NOTES.md).
resource "aws_rds_cluster" "opal" {
  cluster_identifier = var.db_identifier

  engine          = "aurora-postgresql"
  engine_version  = var.db_engine_version
  database_name   = "opal"
  master_username = "postgres"

  master_password_wo         = ephemeral.aws_secretsmanager_secret_version.db_password.secret_string
  master_password_wo_version = aws_secretsmanager_secret_version.db_password.secret_string_wo_version

  db_subnet_group_name   = aws_db_subnet_group.opal.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  storage_encrypted      = true

  backup_retention_period = 30
  #not for prod - make sure your Opal snapshot is not deleted by accident
  skip_final_snapshot = true
}

# 1 writer + N readers, spread across AZs by the provider, giving Aurora a
# same-region failover target.
resource "aws_rds_cluster_instance" "opal" {
  count = 1 + var.db_reader_count

  identifier         = "${var.db_identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.opal.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.opal.engine
  engine_version     = aws_rds_cluster.opal.engine_version

  publicly_accessible = false
}
