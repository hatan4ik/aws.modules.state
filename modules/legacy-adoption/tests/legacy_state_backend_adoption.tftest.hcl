# Contract tests for the historical adoption composition (ADR 0015, closed). They
# pin what the composition represents so it cannot drift while it exists: the
# observed controls, every validation with a failing case, and the output shape
# it shares with the root module. Plan only, under mock_provider.

mock_provider "aws" {}

variables {
  bucket_name         = "test-platform-tf-state"
  dynamodb_table_name = "test-platform-tf-lock"
  kms_key_alias       = "alias/test-platform-terraform-state"
  kms_key_description = "Test legacy Terraform state key"
  tags = {
    Environment = "shared"
    Layer       = "shared-services"
    ManagedBy   = "Terraform"
    Module      = "legacy-state-backend-adoption"
    Project     = "platform-aws-platform"
  }
}

run "plans_exact_observed_bootstrap_controls" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.object_lock_enabled && aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "The adoption module must preserve Object Lock and bucket versioning."
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.state.rule[0].default_retention[0].mode == "COMPLIANCE" && aws_s3_bucket_object_lock_configuration.state.rule[0].default_retention[0].days == 14
    error_message = "The adoption module must preserve the observed COMPLIANCE 14-day retention."
  }

  assert {
    condition     = aws_dynamodb_table.state_lock.billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.state_lock.point_in_time_recovery[0].enabled
    error_message = "The adoption module must preserve on-demand locking with PITR."
  }

  assert {
    condition     = output.backend_configuration.legacy.replica_bucket == null && contains(keys(output.state_access_policy_arns.legacy), "lock_arn")
    error_message = "The transitional contract must be compatible with state-backend consumers without claiming a replica exists."
  }
}

run "keeps_the_bucket_private_owner_enforced_and_encrypted" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.block_public_acls &&
      aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.state.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Ownership must be enforced so ACLs are disabled."
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).bucket_key_enabled == true &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    )
    error_message = "Default encryption must be SSE-KMS with a Bucket Key."
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "test-platform-tf-state"
    error_message = "The bucket must carry the observed name."
  }
}

run "keeps_the_observed_key_and_lock_table_settings" {
  command = plan

  assert {
    condition = (
      aws_kms_key.state.enable_key_rotation == true &&
      aws_kms_key.state.multi_region == false &&
      aws_kms_key.state.deletion_window_in_days == 30 &&
      aws_kms_key.state.description == "Test legacy Terraform state key" &&
      aws_kms_alias.state.name == "alias/test-platform-terraform-state"
    )
    error_message = "The key must rotate, stay single-Region with a 30-day window, and carry the observed description and alias."
  }

  assert {
    condition = (
      aws_dynamodb_table.state_lock.name == "test-platform-tf-lock" &&
      aws_dynamodb_table.state_lock.hash_key == "LockID" &&
      aws_dynamodb_table.state_lock.deletion_protection_enabled == false &&
      one(aws_dynamodb_table.state_lock.server_side_encryption).enabled == true &&
      one(aws_dynamodb_table.state_lock.attribute).name == "LockID"
    )
    error_message = "The lock table must keep the observed name, LockID key, SSE and the observed (disabled) deletion protection."
  }
}

run "applies_the_observed_tags_explicitly_to_every_stateful_resource" {
  command = plan

  assert {
    condition = (
      aws_kms_key.state.tags == var.tags &&
      aws_s3_bucket.state.tags == var.tags &&
      aws_dynamodb_table.state_lock.tags == var.tags
    )
    error_message = "The key, bucket and lock table must carry exactly the observed tags; the composition never relies on provider default_tags."
  }
}

run "emits_a_compatibility_shaped_legacy_tier_without_the_native_lockfile" {
  command = plan

  assert {
    condition = (
      toset(keys(output.backend_configuration)) == toset(["legacy"]) &&
      toset(keys(output.backend_configuration.legacy)) == toset(["bucket", "kms_key_id", "dynamodb_table", "use_lockfile", "replica_bucket", "replica_region", "replica_key_id"]) &&
      output.backend_configuration.legacy.use_lockfile == false &&
      output.backend_configuration.legacy.dynamodb_table == "test-platform-tf-lock" &&
      output.backend_configuration.legacy.replica_region == null &&
      output.backend_configuration.legacy.replica_key_id == null
    )
    error_message = "The legacy tier must use the root module's output shape, DynamoDB locking only, and no replica."
  }

  assert {
    condition = (
      toset(keys(output.state_access_policy_arns.legacy)) == toset(["bucket_arn", "key_arn", "lock_arn", "replica_bucket_arn", "replica_key_arn"]) &&
      output.state_access_policy_arns.legacy.replica_bucket_arn == null &&
      output.state_access_policy_arns.legacy.replica_key_arn == null
    )
    error_message = "The legacy ARN map must use the root module's shape with null replica ARNs."
  }

  assert {
    condition     = output.backend_identity.bucket_name == "test-platform-tf-state" && output.backend_identity.dynamodb_table_name == "test-platform-tf-lock" && output.backend_identity.kms_key_alias == "alias/test-platform-terraform-state"
    error_message = "backend_identity must expose the three observed identifiers."
  }
}

run "rejects_an_invalid_bucket_name" {
  command = plan

  variables {
    bucket_name = "invalid_bucket_name"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_a_bucket_name_that_is_too_short" {
  command = plan

  variables {
    bucket_name = "ab"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_an_invalid_dynamodb_table_name" {
  command = plan

  variables {
    dynamodb_table_name = "ab"
  }

  expect_failures = [var.dynamodb_table_name]
}

run "rejects_a_dynamodb_table_name_with_a_space" {
  command = plan

  variables {
    dynamodb_table_name = "state lock"
  }

  expect_failures = [var.dynamodb_table_name]
}

run "rejects_an_invalid_kms_alias" {
  command = plan

  variables {
    kms_key_alias = "not-an-alias"
  }

  expect_failures = [var.kms_key_alias]
}

run "rejects_an_empty_kms_key_description" {
  command = plan

  variables {
    kms_key_description = "  "
  }

  expect_failures = [var.kms_key_description]
}

run "rejects_empty_tags" {
  command = plan

  variables {
    tags = {}
  }

  expect_failures = [var.tags]
}
