# Integration suite: real apply in the caller's own account, then destroy.
#
# Requires AWS credentials of an IAM ROLE (an assumed-role session) and a region
# from the environment; nothing is hard-coded. Run it with scripts/run-integration.sh
# (`make integration-smoke`), which runs it in a temporary copy of the module with
# the prevent_destroy guards lifted, because the guards (ADR 0008) would otherwise
# make the disposable tier impossible to tear down. It cannot be run with a plain
# `terraform test -test-directory=tests/integration` against the committed tree
# without leaving the tier behind.
#
# The setup fixture creates a throwaway access-log bucket, a stand-in break-glass
# role and unique names. One non-replicated tier without Object Lock is then
# applied, asserted against the real APIs, and destroyed at the end of the file.
# The KMS key stays in pending deletion for the 7-day minimum.

provider "aws" {}

# The module always receives the replica provider. The smoke tier does not
# replicate, so nothing is created through it; it is bound to the same Region.
provider "aws" {
  alias = "replica"
}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "state-it"
  }
}

run "smoke" {
  variables {
    name_prefix            = run.setup.name_prefix
    primary_region         = run.setup.region
    replica_region         = run.setup.region
    access_log_bucket_name = run.setup.access_log_bucket_name
    access_log_prefix      = run.setup.access_log_prefix

    state_tiers = {
      smoke = {
        bucket_name                                  = run.setup.state_bucket_name
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }

    state_access_principal_arns     = run.setup.state_access_principal_arns
    key_administrator_arns          = run.setup.key_administrator_arns
    kms_key_deletion_window_in_days = 7
    tags                            = run.setup.tags
  }

  # The role the suite runs as must be a state access principal (the bucket policy
  # denies everyone else) and a key administrator (the key policy has no
  # account-root statement), so the advisory separation-of-duties check fires by
  # construction. That is expected here and nowhere else.
  expect_failures = [check.key_administrators_are_not_routine_state_users]

  assert {
    condition     = output.backend_configuration["smoke"].bucket == run.setup.state_bucket_name && output.backend_configuration["smoke"].use_lockfile == true
    error_message = "The state bucket must exist under the fixture name and the backend output must carry the lockfile flag."
  }

  assert {
    condition     = output.backend_configuration["smoke"].dynamodb_table == "${run.setup.name_prefix}-smoke-terraform-locks" && output.backend_configuration["smoke"].replica_bucket == null && output.backend_configuration["smoke"].replica_region == null
    error_message = "The lock table must carry the derived name and a tier without a replica must expose null replica fields."
  }

  assert {
    condition     = startswith(output.backend_configuration["smoke"].kms_key_id, "arn:") && strcontains(output.backend_configuration["smoke"].kms_key_id, ":key/mrk-")
    error_message = "The KMS key must be a real multi-Region key (its key id starts with mrk-)."
  }

  assert {
    condition     = aws_kms_key.state["smoke"].enable_key_rotation == true && aws_kms_key.state["smoke"].multi_region == true
    error_message = "The real key must have rotation on and be multi-Region."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state["smoke"].block_public_acls &&
      aws_s3_bucket_public_access_block.state["smoke"].block_public_policy &&
      aws_s3_bucket_public_access_block.state["smoke"].ignore_public_acls &&
      aws_s3_bucket_public_access_block.state["smoke"].restrict_public_buckets
    )
    error_message = "All four public access blocks must be on for the real bucket."
  }

  assert {
    condition = (
      one(aws_s3_bucket_versioning.state["smoke"].versioning_configuration).status == "Enabled" &&
      one(aws_s3_bucket_ownership_controls.state["smoke"].rule).object_ownership == "BucketOwnerEnforced" &&
      aws_s3_bucket_notification.state["smoke"].eventbridge == true
    )
    error_message = "The real bucket must be versioned, owner-enforced and publish EventBridge events."
  }

  assert {
    condition     = aws_s3_bucket_logging.state["smoke"].target_bucket == run.setup.access_log_bucket_name && aws_s3_bucket_logging.state["smoke"].target_prefix == "${run.setup.access_log_prefix}/primary/smoke/"
    error_message = "Server access logging must target the fixture's log bucket under the tier's primary prefix; the API accepted the delivery permissions."
  }

  assert {
    condition = alltrue([
      for sid in ["DenyInsecureTransport", "DenyPrincipalsOutsideStateRoles", "AllowStateBucketMetadata", "AllowStateAndLockObjects"] :
      contains([for statement in jsondecode(aws_s3_bucket_policy.state["smoke"].policy).Statement : statement.Sid], sid)
    ])
    error_message = "The bucket policy must be attached with the TLS deny, the role deny and the two allow statements."
  }

  assert {
    condition = alltrue([
      for sid in ["KeyAdministration", "StateEncryptionUse"] :
      contains([for statement in jsondecode(aws_kms_key.state["smoke"].policy).Statement : statement.Sid], sid)
    ])
    error_message = "The key policy must be attached with the administration and use statements."
  }

  assert {
    condition = (
      aws_dynamodb_table.state_lock["smoke"].billing_mode == "PAY_PER_REQUEST" &&
      one(aws_dynamodb_table.state_lock["smoke"].point_in_time_recovery).enabled == true &&
      one(aws_dynamodb_table.state_lock["smoke"].server_side_encryption).enabled == true
    )
    error_message = "The real lock table must be on-demand, recoverable and encrypted with the tier's key."
  }

  assert {
    condition     = length(aws_s3_bucket.state_replica) == 0 && length(aws_iam_role.state_replication) == 0 && length(aws_kms_replica_key.state) == 0
    error_message = "A non-replicated tier must create no replica resource."
  }
}
