# The primary state bucket of every tier and everything that configures it. The
# public access block, ownership, versioning, SSE-KMS, lifecycle, logging and
# notification settings are not inputs: a state bucket has no other valid shape.
# Object Lock is the one per-tier decision. The policy is attached last, after
# the public access block, and comes from modules/policies.

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

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = var.state_tiers

  bucket                  = aws_s3_bucket.state[each.key].id
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

resource "aws_s3_bucket_versioning" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id

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

resource "aws_s3_bucket_logging" "state" {
  for_each = var.state_tiers

  bucket        = aws_s3_bucket.state[each.key].id
  target_bucket = var.access_log_bucket_name
  target_prefix = "${trimsuffix(var.access_log_prefix, "/")}/primary/${each.key}/"

  lifecycle {
    precondition {
      condition     = !contains(local.state_bucket_names, var.access_log_bucket_name)
      error_message = "access_log_bucket_name is also a state bucket or replica bucket of this module. State buckets must log to the separate central log bucket, never into themselves or each other."
    }
  }
}

resource "aws_s3_bucket_notification" "state" {
  for_each = var.state_tiers

  bucket      = aws_s3_bucket.state[each.key].id
  eventbridge = true
}

resource "aws_s3_bucket_policy" "state" {
  for_each = var.state_tiers

  bucket = aws_s3_bucket.state[each.key].id
  policy = module.policies.bucket_policies[each.key]

  depends_on = [aws_s3_bucket_public_access_block.state]
}
