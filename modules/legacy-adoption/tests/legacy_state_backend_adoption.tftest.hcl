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

run "rejects_an_invalid_bucket_name" {
  command = plan

  variables {
    bucket_name = "invalid_bucket_name"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_an_invalid_kms_alias" {
  command = plan

  variables {
    kms_key_alias = "not-an-alias"
  }

  expect_failures = [var.kms_key_alias]
}
