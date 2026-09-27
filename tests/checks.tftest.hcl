# The advisory checks: each one warns (fails the run unless listed in
# expect_failures) on the unintended-but-valid configuration it describes, and is
# silent on the baseline. Plan only, under mock_provider.

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

run "the_baseline_satisfies_every_check" {
  command = plan

  assert {
    condition     = length(aws_kms_key.state) == 3
    error_message = "The baseline must plan without any advisory check firing."
  }
}

run "warns_when_a_key_administrator_is_also_a_state_access_principal" {
  command = plan

  variables {
    key_administrator_arns = ["arn:aws:iam::111122223333:role/key-admin", "arn:aws:iam::111122223333:role/break-glass"]
  }

  expect_failures = [check.key_administrators_are_not_routine_state_users]
}

run "does_not_warn_when_administrators_and_state_roles_are_distinct" {
  command = plan

  variables {
    key_administrator_arns = ["arn:aws:iam::111122223333:role/key-admin", "arn:aws:iam::111122223333:role/key-admin-2"]
  }

  assert {
    condition     = length(aws_kms_key.state) == 3
    error_message = "Distinct administrators must not trigger the check."
  }
}

run "warns_when_retention_settings_are_set_but_object_lock_is_disabled" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = false
          retention_mode = "COMPLIANCE"
        }
      }
    }
  }

  expect_failures = [check.object_lock_settings_are_used]
}

run "warns_when_object_lock_retention_outlives_noncurrent_expiration" {
  command = plan

  variables {
    state_tiers = {
      vault = {
        bucket_name                                  = "test-platform-vault-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "COMPLIANCE"
          retention_days = 90
        }
      }
    }
  }

  expect_failures = [check.object_lock_retention_outlives_noncurrent_expiration]
}

run "does_not_warn_when_retention_equals_noncurrent_expiration" {
  command = plan

  variables {
    state_tiers = {
      vault = {
        bucket_name                                  = "test-platform-vault-tfstate"
        noncurrent_version_expiration_in_days        = 90
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "COMPLIANCE"
          retention_days = 90
        }
      }
    }
  }

  assert {
    condition     = aws_s3_bucket.state["vault"].object_lock_enabled == true
    error_message = "Equal retention and expiry must not trigger the check."
  }
}

run "warns_when_a_tag_key_is_owned_by_the_module" {
  command = plan

  variables {
    tags = {
      Owner = "platform"
      Name  = "my-state"
    }
  }

  expect_failures = [check.tags_are_not_overwritten_by_the_module]
}

run "module_computed_tags_win_over_the_callers" {
  command = plan

  variables {
    tags = {
      Component = "something-else"
    }
  }

  assert {
    condition     = aws_s3_bucket.state["dev"].tags["Component"] == "terraform-state"
    error_message = "The module's Component tag must win over the caller's."
  }

  expect_failures = [check.tags_are_not_overwritten_by_the_module]
}
