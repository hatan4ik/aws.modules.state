resource "aws_kms_key" "state" {
  for_each = var.state_tiers

  description             = "Terraform state encryption key for ${each.key}"
  enable_key_rotation     = true
  multi_region            = true
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  policy                  = local.state_key_policies[each.key]

  tags = merge(local.common_tags, {
    Name            = "${var.name_prefix}-${each.key}-terraform-state"
    EnvironmentTier = each.key
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_replica_key" "state" {
  provider = aws.replica
  for_each = local.replication_tiers

  description             = "Terraform state replica encryption key for ${each.key} in ${var.replica_region}"
  primary_key_arn         = aws_kms_key.state[each.key].arn
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  policy                  = local.state_replica_key_policies[each.key]

  tags = merge(local.common_tags, {
    Name            = "${var.name_prefix}-${each.key}-terraform-state-replica"
    EnvironmentTier = each.key
    ReplicaRegion   = var.replica_region
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  for_each = var.state_tiers

  name          = "alias/${var.name_prefix}-${each.key}-terraform-state"
  target_key_id = aws_kms_key.state[each.key].key_id
}

resource "aws_kms_alias" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  name          = "alias/${var.name_prefix}-${each.key}-terraform-state"
  target_key_id = aws_kms_replica_key.state[each.key].key_id
}

resource "aws_s3_bucket" "state" {
  for_each = var.state_tiers

  bucket              = each.value.bucket_name
  object_lock_enabled = each.value.object_lock.enabled

  tags = merge(local.common_tags, {
    Name            = each.value.bucket_name
    EnvironmentTier = each.key
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(local.replication_tiers) == 0 || var.replica_region != var.primary_region
      error_message = "replica_region must be distinct from primary_region for cross-Region state replication."
    }
  }
}

resource "aws_s3_bucket" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket              = each.value.replica_bucket_name
  object_lock_enabled = each.value.object_lock.enabled

  tags = merge(local.common_tags, {
    Name            = each.value.replica_bucket_name
    EnvironmentTier = each.key
    ReplicaRegion   = var.replica_region
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = var.state_tiers

  bucket                  = aws_s3_bucket.state[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket                  = aws_s3_bucket.state_replica[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state[each.key].arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_replica_key.state[each.key].arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id

  rule {
    id     = "retain-current-state-expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = each.value.noncurrent_version_expiration_in_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = each.value.abort_incomplete_multipart_upload_after_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id

  rule {
    id     = "retain-current-state-expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = each.value.noncurrent_version_expiration_in_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = each.value.abort_incomplete_multipart_upload_after_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state_replica]
}

resource "aws_s3_bucket_object_lock_configuration" "state" {
  for_each = {
    for tier, configuration in var.state_tiers : tier => configuration
    if configuration.object_lock.enabled
  }

  bucket = aws_s3_bucket.state[each.key].id

  rule {
    default_retention {
      mode = each.value.object_lock.retention_mode
      days = each.value.object_lock.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_object_lock_configuration" "state_replica" {
  provider = aws.replica
  for_each = {
    for tier, configuration in local.replication_tiers : tier => configuration
    if configuration.object_lock.enabled
  }

  bucket = aws_s3_bucket.state_replica[each.key].id

  rule {
    default_retention {
      mode = each.value.object_lock.retention_mode
      days = each.value.object_lock.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state_replica]
}

resource "aws_s3_bucket_logging" "state" {
  for_each = var.state_tiers

  bucket        = aws_s3_bucket.state[each.key].id
  target_bucket = var.access_log_bucket_name
  target_prefix = "${trimsuffix(var.access_log_prefix, "/")}/primary/${each.key}/"
}

resource "aws_s3_bucket_logging" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket        = aws_s3_bucket.state_replica[each.key].id
  target_bucket = var.access_log_bucket_name
  target_prefix = "${trimsuffix(var.access_log_prefix, "/")}/replica/${each.key}/"
}

resource "aws_s3_bucket_notification" "state" {
  for_each = var.state_tiers

  bucket      = aws_s3_bucket.state[each.key].id
  eventbridge = true
}

resource "aws_s3_bucket_notification" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket      = aws_s3_bucket.state_replica[each.key].id
  eventbridge = true
}

resource "aws_s3_bucket_policy" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id
  policy = local.state_bucket_policies[each.key]

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_policy" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id
  policy = local.state_replica_bucket_policies[each.key]

  depends_on = [aws_s3_bucket_public_access_block.state_replica]
}

resource "aws_iam_role" "state_replication" {
  for_each = local.replication_tiers

  name = "${var.name_prefix}-${each.key}-terraform-state-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = merge(local.common_tags, {
    Name            = "${var.name_prefix}-${each.key}-terraform-state-replication"
    EnvironmentTier = each.key
  })
}

resource "aws_iam_role_policy" "state_replication" {
  for_each = local.replication_tiers

  name   = "${var.name_prefix}-${each.key}-terraform-state-replication"
  role   = aws_iam_role.state_replication[each.key].id
  policy = local.state_replication_policies[each.key]
}

resource "aws_s3_bucket_replication_configuration" "state" {
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state[each.key].id
  role   = aws_iam_role.state_replication[each.key].arn

  rule {
    id     = "replicate-state-to-${var.replica_region}"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.state_replica[each.key].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_replica_key.state[each.key].arn
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.state,
    aws_s3_bucket_versioning.state_replica,
    aws_s3_bucket_server_side_encryption_configuration.state_replica,
    aws_iam_role_policy.state_replication,
  ]
}

resource "aws_dynamodb_table" "state_lock" {
  for_each = var.state_tiers

  name         = local.state_lock_table_names[each.key]
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state[each.key].arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name            = local.state_lock_table_names[each.key]
    EnvironmentTier = each.key
  })

  lifecycle {
    prevent_destroy = true
  }
}
