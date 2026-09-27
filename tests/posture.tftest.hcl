# Security posture of every tier variant, asserted positively. Everything here is
# known at plan time (configuration, not computed ARNs), so the runs are plain
# `plan` runs under mock_provider. The policy documents, which embed computed
# ARNs, are asserted in modules/policies/tests and, wired to the resources, in
# tests/wired.
#
# Variants covered: replica off, replica on, Object Lock off, Object Lock
# GOVERNANCE, Object Lock COMPLIANCE, and all of them at once.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-2"
    }
  }
}

mock_provider "aws" {
  alias = "replica"

  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
    }
  }
}

variables {
  name_prefix            = "test-platform"
  primary_region         = "us-east-2"
  replica_region         = "us-west-2"
  access_log_bucket_name = "test-platform-central-access-logs"
  access_log_prefix      = "test-platform/terraform-state"
  state_tiers = {
    dev = {
      bucket_name                                  = "test-platform-dev-tfstate"
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled = false
      }
    }
    staging = {
      bucket_name                                  = "test-platform-staging-tfstate"
      replica_bucket_name                          = "test-platform-staging-tfstate-replica"
      noncurrent_version_expiration_in_days        = 45
      abort_incomplete_multipart_upload_after_days = 3
      object_lock = {
        enabled        = true
        retention_mode = "GOVERNANCE"
        retention_days = 30
      }
    }
    prod = {
      bucket_name                                  = "test-platform-prod-tfstate"
      replica_bucket_name                          = "test-platform-prod-tfstate-replica"
      noncurrent_version_expiration_in_days        = 90
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "COMPLIANCE"
        retention_days = 60
      }
    }
  }
  state_access_principal_arns = [
    "arn:aws:iam::111122223333:role/ci-terraform",
    "arn:aws:iam::111122223333:role/break-glass",
  ]
  kms_key_deletion_window_in_days = 30
  key_administrator_arns = [
    "arn:aws:iam::111122223333:role/key-admin",
  ]
  tags = {
    Owner = "platform"
  }
}

run "every_tier_gets_a_bucket_a_key_an_alias_and_a_lock_table" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_s3_bucket.state)) == toset(["dev", "staging", "prod"]) &&
      toset(keys(aws_kms_key.state)) == toset(["dev", "staging", "prod"]) &&
      toset(keys(aws_kms_alias.state)) == toset(["dev", "staging", "prod"]) &&
      toset(keys(aws_dynamodb_table.state_lock)) == toset(["dev", "staging", "prod"])
    )
    error_message = "Every tier must have exactly one primary bucket, key, alias and lock table."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_s3_bucket_public_access_block.state[tier] != null &&
        aws_s3_bucket_ownership_controls.state[tier] != null &&
        aws_s3_bucket_versioning.state[tier] != null &&
        aws_s3_bucket_server_side_encryption_configuration.state[tier] != null &&
        aws_s3_bucket_lifecycle_configuration.state[tier] != null &&
        aws_s3_bucket_logging.state[tier] != null &&
        aws_s3_bucket_notification.state[tier] != null &&
        aws_s3_bucket_policy.state[tier] != null
      )
    ])
    error_message = "Every tier's bucket must carry the full set of configuration resources."
  }
}

run "primary_buckets_are_private_owner_enforced_versioned_and_encrypted_in_every_variant" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_s3_bucket_public_access_block.state[tier].block_public_acls &&
        aws_s3_bucket_public_access_block.state[tier].block_public_policy &&
        aws_s3_bucket_public_access_block.state[tier].ignore_public_acls &&
        aws_s3_bucket_public_access_block.state[tier].restrict_public_buckets
      )
    ])
    error_message = "All four public access blocks must be on for every tier."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        one(aws_s3_bucket_ownership_controls.state[tier].rule).object_ownership == "BucketOwnerEnforced" &&
        one(aws_s3_bucket_versioning.state[tier].versioning_configuration).status == "Enabled"
      )
    ])
    error_message = "Every tier must enforce bucket-owner ownership and enable versioning."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        one(aws_s3_bucket_server_side_encryption_configuration.state[tier].rule).bucket_key_enabled == true &&
        one(one(aws_s3_bucket_server_side_encryption_configuration.state[tier].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
      )
    ])
    error_message = "Every tier must default-encrypt with SSE-KMS and a Bucket Key."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : aws_s3_bucket_notification.state[tier].eventbridge == true
    ])
    error_message = "Every tier must publish S3 events to EventBridge."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_s3_bucket_logging.state[tier].target_bucket == "test-platform-central-access-logs" &&
        aws_s3_bucket_logging.state[tier].target_prefix == "test-platform/terraform-state/primary/${tier}/"
      )
    ])
    error_message = "Every tier must log to the central bucket under its own primary prefix."
  }

  assert {
    condition = alltrue([
      for tier, name in { dev = "test-platform-dev-tfstate", staging = "test-platform-staging-tfstate", prod = "test-platform-prod-tfstate" } : aws_s3_bucket.state[tier].bucket == name
    ])
    error_message = "Bucket names must be exactly the declared bucket_name of each tier."
  }
}

run "lifecycle_rules_use_each_tiers_own_periods" {
  command = plan

  assert {
    condition = alltrue([
      for tier, days in { dev = 30, staging = 45, prod = 90 } : (
        one(aws_s3_bucket_lifecycle_configuration.state[tier].rule).status == "Enabled" &&
        one(aws_s3_bucket_lifecycle_configuration.state[tier].rule).id == "retain-current-state-expire-noncurrent-versions" &&
        one(one(aws_s3_bucket_lifecycle_configuration.state[tier].rule).noncurrent_version_expiration).noncurrent_days == days
      )
    ])
    error_message = "Noncurrent versions must expire after the tier's declared period."
  }

  assert {
    condition = alltrue([
      for tier, days in { dev = 7, staging = 3, prod = 7 } : one(one(aws_s3_bucket_lifecycle_configuration.state[tier].rule).abort_incomplete_multipart_upload).days_after_initiation == days
    ])
    error_message = "Incomplete multipart uploads must be aborted after the tier's declared period."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : length(one(aws_s3_bucket_lifecycle_configuration.state[tier].rule).expiration) == 0
    ])
    error_message = "The lifecycle rule must never expire current state objects."
  }
}

run "keys_rotate_are_multi_region_and_use_the_declared_deletion_window" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_kms_key.state[tier].enable_key_rotation == true &&
        aws_kms_key.state[tier].multi_region == true &&
        aws_kms_key.state[tier].deletion_window_in_days == 30
      )
    ])
    error_message = "Every state key must rotate, be multi-Region and use the declared deletion window."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_kms_alias.state[tier].name == "alias/test-platform-${tier}-terraform-state" &&
        aws_kms_key.state[tier].tags["Name"] == "test-platform-${tier}-terraform-state" &&
        aws_kms_key.state[tier].tags["EnvironmentTier"] == tier
      )
    ])
    error_message = "Aliases and Name and EnvironmentTier tags must be derived from the prefix and the tier."
  }
}

run "lock_tables_are_on_demand_encrypted_and_recoverable" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_dynamodb_table.state_lock[tier].name == "test-platform-${tier}-terraform-locks" &&
        aws_dynamodb_table.state_lock[tier].billing_mode == "PAY_PER_REQUEST" &&
        aws_dynamodb_table.state_lock[tier].hash_key == "LockID" &&
        one(aws_dynamodb_table.state_lock[tier].point_in_time_recovery).enabled == true &&
        one(aws_dynamodb_table.state_lock[tier].server_side_encryption).enabled == true
      )
    ])
    error_message = "Every lock table must be on-demand, keyed by LockID, encrypted with the tier's key and recoverable to a point in time."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        one(aws_dynamodb_table.state_lock[tier].attribute).name == "LockID" &&
        one(aws_dynamodb_table.state_lock[tier].attribute).type == "S"
      )
    ])
    error_message = "The lock table's only attribute must be the string LockID."
  }
}

run "object_lock_is_a_per_tier_decision" {
  command = plan

  assert {
    condition     = toset(keys(aws_s3_bucket_object_lock_configuration.state)) == toset(["staging", "prod"])
    error_message = "Only tiers that enable Object Lock may receive an Object Lock configuration."
  }

  assert {
    condition = (
      aws_s3_bucket.state["dev"].object_lock_enabled == false &&
      aws_s3_bucket.state["staging"].object_lock_enabled == true &&
      aws_s3_bucket.state["prod"].object_lock_enabled == true
    )
    error_message = "The bucket-level Object Lock flag must follow the tier's decision."
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_object_lock_configuration.state["staging"].rule).default_retention).mode == "GOVERNANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state["staging"].rule).default_retention).days == 30 &&
      one(one(aws_s3_bucket_object_lock_configuration.state["prod"].rule).default_retention).mode == "COMPLIANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state["prod"].rule).default_retention).days == 60
    )
    error_message = "Default retention must be exactly the mode and days declared for each tier."
  }
}

run "a_tier_without_a_replica_has_no_replica_resources_at_all" {
  command = plan

  assert {
    condition = (
      !contains(keys(aws_s3_bucket.state_replica), "dev") &&
      !contains(keys(aws_kms_replica_key.state), "dev") &&
      !contains(keys(aws_kms_alias.state_replica), "dev") &&
      !contains(keys(aws_iam_role.state_replication), "dev") &&
      !contains(keys(aws_iam_role_policy.state_replication), "dev") &&
      !contains(keys(aws_s3_bucket_replication_configuration.state), "dev") &&
      !contains(keys(aws_s3_bucket_policy.state_replica), "dev") &&
      !contains(keys(aws_s3_bucket_logging.state_replica), "dev")
    )
    error_message = "A tier that names no replica_bucket_name must receive no replica bucket, key, alias, role, policy, replication rule or logging."
  }

  assert {
    condition = (
      toset(keys(aws_s3_bucket.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_kms_replica_key.state)) == toset(["staging", "prod"]) &&
      toset(keys(aws_iam_role.state_replication)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_replication_configuration.state)) == toset(["staging", "prod"])
    )
    error_message = "Only the tiers that name a replica bucket may receive replica resources."
  }
}

run "single_non_replicated_tier_without_object_lock" {
  command = plan

  variables {
    state_tiers = {
      solo = {
        bucket_name                                  = "test-platform-solo-tfstate"
        noncurrent_version_expiration_in_days        = 14
        abort_incomplete_multipart_upload_after_days = 1
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_s3_bucket.state) == 1 &&
      length(aws_kms_key.state) == 1 &&
      length(aws_dynamodb_table.state_lock) == 1 &&
      length(aws_s3_bucket.state_replica) == 0 &&
      length(aws_kms_replica_key.state) == 0 &&
      length(aws_kms_alias.state_replica) == 0 &&
      length(aws_iam_role.state_replication) == 0 &&
      length(aws_iam_role_policy.state_replication) == 0 &&
      length(aws_s3_bucket_replication_configuration.state) == 0 &&
      length(aws_s3_bucket_object_lock_configuration.state) == 0 &&
      length(aws_s3_bucket_object_lock_configuration.state_replica) == 0
    )
    error_message = "A single tier with no replica and no Object Lock must create exactly the primary set and nothing else."
  }

  assert {
    condition = (
      aws_s3_bucket.state["solo"].object_lock_enabled == false &&
      aws_kms_key.state["solo"].enable_key_rotation == true &&
      one(aws_s3_bucket_public_access_block.state["solo"] != null ? [1] : []) == 1
    )
    error_message = "Even the smallest deployment must keep rotation and the public access block."
  }
}

run "single_tier_with_object_lock_and_no_replica" {
  command = plan

  variables {
    state_tiers = {
      vault = {
        bucket_name                                  = "test-platform-vault-tfstate"
        noncurrent_version_expiration_in_days        = 400
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "COMPLIANCE"
          retention_days = 365
        }
      }
    }
  }

  assert {
    condition = (
      aws_s3_bucket.state["vault"].object_lock_enabled == true &&
      length(aws_s3_bucket_object_lock_configuration.state) == 1 &&
      length(aws_s3_bucket_object_lock_configuration.state_replica) == 0 &&
      one(one(aws_s3_bucket_object_lock_configuration.state["vault"].rule).default_retention).mode == "COMPLIANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state["vault"].rule).default_retention).days == 365
    )
    error_message = "A non-replicated Object Lock tier must lock the primary only."
  }
}

run "tags_carry_the_module_computed_keys_and_the_callers_own" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_s3_bucket.state[tier].tags["Component"] == "terraform-state" &&
        aws_s3_bucket.state[tier].tags["EnvironmentTier"] == tier &&
        aws_s3_bucket.state[tier].tags["Owner"] == "platform" &&
        aws_dynamodb_table.state_lock[tier].tags["Component"] == "terraform-state" &&
        aws_dynamodb_table.state_lock[tier].tags["Name"] == "test-platform-${tier}-terraform-locks" &&
        aws_kms_key.state[tier].tags["Owner"] == "platform"
      )
    ])
    error_message = "Every stateful resource must carry Component, EnvironmentTier, Name and the caller's tags."
  }
}
