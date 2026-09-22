mock_provider "aws" {}

mock_provider "aws" {
  alias = "replica"
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
      replica_bucket_name                          = "test-platform-dev-tfstate-replica"
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled = false
      }
    }
    staging = {
      bucket_name                                  = "test-platform-staging-tfstate"
      replica_bucket_name                          = "test-platform-staging-tfstate-replica"
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "GOVERNANCE"
        retention_days = 30
      }
    }
    prod = {
      bucket_name                                  = "test-platform-prod-tfstate"
      replica_bucket_name                          = "test-platform-prod-tfstate-replica"
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "COMPLIANCE"
        retention_days = 30
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
}

run "plans_one_encrypted_versioned_backend_per_tier" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.state) == 3 && length(aws_dynamodb_table.state_lock) == 3 && length(aws_kms_key.state) == 3
    error_message = "Every environment tier must have one isolated state bucket, lock table, and KMS key."
  }

  assert {
    condition = (
      alltrue([for configuration in aws_s3_bucket_versioning.state["prod"].versioning_configuration : configuration.status == "Enabled"]) &&
      alltrue(flatten([for rule in aws_s3_bucket_server_side_encryption_configuration.state["prod"].rule : [for encryption in rule.apply_server_side_encryption_by_default : encryption.sse_algorithm == "aws:kms"]]))
    )
    error_message = "Production state must be versioned and encrypted with SSE-KMS."
  }

  assert {
    condition     = length(aws_s3_bucket_object_lock_configuration.state) == 2
    error_message = "Only tiers explicitly configured for Object Lock may receive an Object Lock rule."
  }

  assert {
    condition = (
      length(aws_s3_bucket.state_replica) == 3 &&
      length(aws_kms_replica_key.state) == 3 &&
      length(aws_s3_bucket_replication_configuration.state) == 3 &&
      length(aws_iam_role.state_replication) == 3 &&
      length(aws_s3_bucket_logging.state) == 3 &&
      length(aws_s3_bucket_notification.state) == 3
    )
    error_message = "Every state tier must have encrypted cross-Region replication, logging, and notifications."
  }
}

run "plans_custom_tier_without_replication" {
  command = plan

  variables {
    state_tiers = {
      residency-bound = {
        bucket_name                                  = "test-platform-residency-bound-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket.state) == 1 && length(aws_s3_bucket.state_replica) == 0 && length(aws_s3_bucket_replication_configuration.state) == 0 && length(aws_iam_role.state_replication) == 0
    error_message = "A valid state tier must be able to opt out of cross-Region replication."
  }
}

run "rejects_same_primary_and_replica_region" {
  command = plan

  variables {
    replica_region = "us-east-2"
  }

  expect_failures = [aws_s3_bucket.state]
}
