# The output contract, for the parts known at plan time: keys, the lock mechanism
# flags, names and Regions. The ARN- and id-valued fields are computed; they are
# asserted with distinct values per tier in tests/wired.

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

run "backend_configuration_has_one_entry_per_tier_with_the_documented_fields" {
  command = plan

  assert {
    condition = (
      toset(keys(output.backend_configuration)) == toset(["dev", "staging", "prod"]) &&
      toset(keys(output.state_access_policy_arns)) == toset(["dev", "staging", "prod"])
    )
    error_message = "Both outputs must have exactly one entry per tier."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : toset(keys(output.backend_configuration[tier])) == toset(["bucket", "kms_key_id", "dynamodb_table", "use_lockfile", "replica_bucket", "replica_region", "replica_key_id"])
    ])
    error_message = "Every backend_configuration entry must expose exactly the documented fields."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : toset(keys(output.state_access_policy_arns[tier])) == toset(["bucket_arn", "key_arn", "lock_arn", "replica_bucket_arn", "replica_key_arn"])
    ])
    error_message = "Every state_access_policy_arns entry must expose exactly the documented fields."
  }
}

run "both_lock_mechanisms_are_emitted_for_every_tier" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        output.backend_configuration[tier].use_lockfile == true &&
        output.backend_configuration[tier].dynamodb_table == "test-platform-${tier}-terraform-locks"
      )
    ])
    error_message = "Every tier must emit the S3 native lockfile flag and the DynamoDB lock table name (ADR 0016 transition)."
  }
}

run "replica_fields_are_null_for_a_tier_without_a_replica_and_set_for_one_with" {
  command = plan

  assert {
    condition = (
      output.backend_configuration["dev"].replica_bucket == null &&
      output.backend_configuration["dev"].replica_region == null &&
      output.backend_configuration["dev"].replica_key_id == null &&
      output.state_access_policy_arns["dev"].replica_bucket_arn == null &&
      output.state_access_policy_arns["dev"].replica_key_arn == null
    )
    error_message = "A tier without a replica must expose null replica fields."
  }

  assert {
    condition = (
      output.backend_configuration["staging"].replica_region == "us-west-2" &&
      output.backend_configuration["prod"].replica_region == "us-west-2"
    )
    error_message = "A replicated tier must expose the replica Region."
  }
}

run "a_deployment_without_replicas_has_null_replica_fields_everywhere" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition = (
      output.backend_configuration["dev"].replica_region == null &&
      output.backend_configuration["dev"].replica_bucket == null &&
      output.backend_configuration["dev"].use_lockfile == true
    )
    error_message = "Without replicas every replica field must be null and the lockfile flag must still be true."
  }
}
