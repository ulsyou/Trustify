#region Password Generation
resource "random_password" "db_password" {
  length = 16
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
#endregion

#region RDS Instance
resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-pg"
  engine = "postgres"
  engine_version = "16.1"
  instance_class = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  db_subnet_group_name = var.db_subnet_group_name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible = false
  multi_az = var.db_multi_az
  backup_retention_period = var.db_backup_retention_days
  skip_final_snapshot = var.db_skip_final_snapshot
  deletion_protection = var.db_deletion_protection

  tags = {
    Name = "${var.name_prefix}-pg"
  }
}
#endregion

#region Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.name_prefix}-db-credentials"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    engine = "postgres"
    host = aws_db_instance.this.address
    port = aws_db_instance.this.port
    username = var.db_username
    password = random_password.db_password.result
    dbname = var.db_name
    database_url = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
  })
}
#endregion
