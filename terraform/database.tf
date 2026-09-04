resource "random_password" "database" {
  length  = 40
  special = false
}

resource "random_password" "cache" {
  length  = 40
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-database"
  subnet_ids = aws_subnet.data[*].id

  tags = {
    Name = "${local.name}-database"
  }
}

resource "aws_db_instance" "this" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.database_instance_class

  db_name  = "grick"
  username = "grickadmin"
  password = random_password.database.result
  port     = 5432

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = var.database_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  backup_retention_period         = var.database_backup_retention_days
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  apply_immediately               = true
  deletion_protection             = var.database_deletion_protection
  skip_final_snapshot             = var.skip_final_database_snapshot
  final_snapshot_identifier       = var.skip_final_database_snapshot ? null : "${local.name}-final"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${local.name}-postgres"
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name}-cache"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${local.name}-queue"
  family      = "redis7"
  description = "GRiCk BullMQ queue. Do not evict job keys."

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  parameter {
    name  = "timeout"
    value = "0"
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name}-cache"
  description          = "GRiCk Redis-compatible cache and BullMQ job queue"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.cache_node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.this.name

  num_cache_clusters         = var.cache_high_availability ? 2 : 1
  automatic_failover_enabled = var.cache_high_availability
  multi_az_enabled           = var.cache_high_availability

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.this.arn
  transit_encryption_enabled = true
  auth_token                 = random_password.cache.result

  snapshot_retention_limit = var.cache_snapshot_retention_days
  snapshot_window          = var.cache_snapshot_retention_days > 0 ? "16:00-17:00" : null

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name = "${local.name}-cache"
  }
}
