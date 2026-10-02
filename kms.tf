# One multi-Region KMS key per tier, and for a replicated tier its replica key in
# the replica Region. Rotation is always on. The key policies come from
# modules/policies; there is deliberately no account-root statement, so only the
# named administrators and state roles can manage or use a state key.

resource "aws_kms_key" "state" {
  for_each = var.state_tiers

  description             = "Terraform state encryption key for ${each.key}"
  enable_key_rotation     = true
  multi_region            = true
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  policy                  = module.policies.key_policies[each.key]

  tags = merge(local.common_tags, {
    Name            = local.state_key_names[each.key]
    EnvironmentTier = each.key
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = data.aws_region.primary.region == var.primary_region
      error_message = "The default aws provider is configured for ${data.aws_region.primary.region}, but primary_region is ${var.primary_region}. Configure the default provider for primary_region so keys and buckets are created where the outputs say they are."
    }
  }
}

resource "aws_kms_replica_key" "state" {
  provider = aws.replica
  for_each = local.replication_tiers

  description             = "Terraform state replica encryption key for ${each.key} in ${var.replica_region}"
  primary_key_arn         = aws_kms_key.state[each.key].arn
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  policy                  = module.policies.replica_key_policies[each.key]

  tags = merge(local.common_tags, {
    Name            = "${local.state_key_names[each.key]}-replica"
    EnvironmentTier = each.key
    ReplicaRegion   = var.replica_region
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = data.aws_region.replica.region == var.replica_region
      error_message = "The aws.replica provider is configured for ${data.aws_region.replica.region}, but replica_region is ${var.replica_region}. Configure the aws.replica provider for replica_region so replicas are created where the outputs say they are."
    }
  }
}

resource "aws_kms_alias" "state" {
  for_each = var.state_tiers

  name          = "alias/${local.state_key_names[each.key]}"
  target_key_id = aws_kms_key.state[each.key].key_id
}

resource "aws_kms_alias" "state_replica" {
  provider = aws.replica
  for_each = local.replication_tiers

  name          = "alias/${local.state_key_names[each.key]}"
  target_key_id = aws_kms_replica_key.state[each.key].key_id
}
