# terraform/modules/aws/s3/main.tf

# Random suffix for bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# S3 Bucket for ML Artifacts
resource "aws_s3_bucket" "ml_artifacts" {
  bucket = "${var.bucket_name_prefix}-artifacts-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name        = "ML Artifacts Storage"
    Environment = var.environment
    Project     = var.project_name
  })
}

# S3 Bucket for Model Registry
resource "aws_s3_bucket" "model_registry" {
  bucket = "${var.bucket_name_prefix}-models-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name        = "Model Registry Storage"
    Environment = var.environment
    Project     = var.project_name
  })
}

# S3 Bucket for Data Storage
resource "aws_s3_bucket" "data_storage" {
  bucket = "${var.bucket_name_prefix}-data-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name        = "ML Data Storage"
    Environment = var.environment
    Project     = var.project_name
  })
}

# Versioning for all buckets
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.model_registry.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.model_registry.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

# Lifecycle Policies
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket Policies
resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json
}

# KMS Key for S3 Encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 encryption ${var.project_name}-${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_s3.json

  tags = merge(var.tags, {
    Name = "${var.project_name}-s3-kms-${var.environment}"
  })
}