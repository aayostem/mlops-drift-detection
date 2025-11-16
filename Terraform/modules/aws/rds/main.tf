# terraform/modules/aws/rds/main.tf

# Random password for database
resource "random_password" "database_password" {
  length  = 16
  special = false
}

# Database Subnet Group
resource "aws_db_subnet_group" "ml_platform" {
  name       = "${var.project_name}-db-subnet-group-${var.environment}"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-db-subnet-group-${var.environment}"
  })
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "ml_metadata" {
  identifier = "${var.project_name}-ml-metadata-${var.environment}"

  # Database Configuration
  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  storage_type         = var.storage_type
  max_allocated_storage = var.max_allocated_storage

  # Database Credentials
  db_name  = var.database_name
  username = var.database_username
  password = random_password.database_password.result
  port     = 5432

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.ml_platform.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Backup & Maintenance
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true

  # Deletion Protection
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier

  # Monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn

  # Encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Parameters
  parameter_group_name = aws_db_parameter_group.ml_platform.name

  tags = merge(var.tags, {
    Name = "ML Metadata Database"
  })
}

# RDS Parameter Group
resource "aws_db_parameter_group" "ml_platform" {
  name   = "${var.project_name}-db-params-${var.environment}"
  family = var.parameter_group_family

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,auto_explain"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-db-params-${var.environment}"
  })
}

# RDS Option Group
resource "aws_db_option_group" "ml_platform" {
  name                     = "${var.project_name}-db-options-${var.environment}"
  engine_name              = "postgres"
  major_engine_version     = var.major_engine_version

  option {
    option_name = "pgAudit"

    option_settings {
      name  = "pgaudit.log"
      value = "all"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-db-options-${var.environment}"
  })
}

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption ${var.project_name}-${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-kms-${var.environment}"
  })
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  ]

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-monitoring-role-${var.environment}"
  })
}