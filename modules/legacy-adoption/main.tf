# This module represents the observed bootstrap exactly enough to move its
# existing Terraform bindings into the canonical tree. It deliberately does
# not introduce the future multi-Region state design; ADR 0015 requires that
# to be a separately reviewed hardening migration after adoption is complete.

resource "aws_kms_key" "state" {
  # checkov:skip=CKV2_AWS_64: ADR 0015 adopts the existing key without replacing an unknown key policy; a Security-approved least-privilege policy is required before this bootstrap becomes a delivery backend.
  description = var.kms_key_description
  # Fixed observed values; changing either is a separately approved hardening migration.
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false
  tags                    = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  name          = var.kms_key_alias
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_18: ADR 0015 adoption must be no-change until a Log Archive destination is approved; logging is a separately gated hardening action.
  # checkov:skip=CKV2_AWS_61: ADR 0015 preserves Object Lock/versioned state before a Security-approved lifecycle policy is defined.
  # checkov:skip=CKV2_AWS_62: ADR 0015 does not create an EventBridge integration without the approved event ownership and retention contract.
  # checkov:skip=CKV_AWS_144: ADR 0015 does not create a replica bucket or replication role; cross-Region recovery is a separately approved migration.
  bucket              = var.bucket_name
  object_lock_enabled = true
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 14
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_dynamodb_table" "state_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  # Preserve the observed setting in this no-change adoption. Hardening is separately gated.
  deletion_protection_enabled = false

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
