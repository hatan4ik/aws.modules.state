# The replica bucket of every tier that opts in (replica_bucket_name), created in
# the replica Region through the aws.replica provider alias. It carries the same
# controls as the primary, encrypts under the tier's replica key, and applies the
# tier's Object Lock decision to the copy as well.

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

resource "aws_s3_bucket_public_access_block" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket                  = aws_s3_bucket.state_replica[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
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

resource "aws_s3_bucket_logging" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket        = aws_s3_bucket.state_replica[each.key].id
  target_bucket = var.access_log_bucket_name
  target_prefix = "${trimsuffix(var.access_log_prefix, "/")}/replica/${each.key}/"
}

resource "aws_s3_bucket_notification" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket      = aws_s3_bucket.state_replica[each.key].id
  eventbridge = true
}

resource "aws_s3_bucket_policy" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  bucket = aws_s3_bucket.state_replica[each.key].id
  policy = module.policies.replica_bucket_policies[each.key]

  depends_on = [aws_s3_bucket_public_access_block.state_replica]
}
