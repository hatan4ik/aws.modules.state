# The DynamoDB lock table of every tier. Terraform's S3 backend supports a native
# lockfile and the outputs emit use_lockfile = true, but the platform requires the
# lock table for the ADR 0016 transition: it stays, and stays protected from
# destruction, until that ADR is amended with the retirement evidence.

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
