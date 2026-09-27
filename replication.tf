# Cross-Region replication for the tiers that opt in. Each tier has its own role,
# assumable only by S3, whose policy (modules/policies) reaches only that tier's
# source bucket, replica bucket and two keys.

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

  lifecycle {
    precondition {
      condition     = length("${var.name_prefix}-${each.key}-terraform-state-replication") <= 64
      error_message = "The replication role name ${var.name_prefix}-${each.key}-terraform-state-replication is longer than the 64 characters IAM allows. Shorten name_prefix or the tier name."
    }
  }
}

resource "aws_iam_role_policy" "state_replication" {
  for_each = local.replication_tiers

  name   = "${var.name_prefix}-${each.key}-terraform-state-replication"
  role   = aws_iam_role.state_replication[each.key].id
  policy = module.policies.replication_policies[each.key]
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
