resource "random_password" "password" {
  length  = 16
  special = false
}

resource "aws_security_group" "rds" {
  name   = "${var.name_prefix}-db-sec-group"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }
}

resource "aws_db_subnet_group" "opal" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "opal" {
  db_name    = "opal"
  identifier = "${var.name_prefix}-db"

  engine            = "postgres"
  engine_version    = "15.19"
  allocated_storage = 100
  storage_type      = "gp3"
  instance_class    = var.db_instance_class

  username = "postgres"
  password = random_password.password.result

  db_subnet_group_name   = aws_db_subnet_group.opal.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = true
  publicly_accessible    = false
  storage_encrypted      = true

  backup_retention_period = 30
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.name_prefix}-db-final-snapshot"

  apply_immediately = true
}
