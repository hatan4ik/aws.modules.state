# Every variable validation, each with a failing case (and where the rule has a
# boundary, the accepted side of it). Plan only, under mock_provider. Each
# failing run names the one variable whose validation must reject it.

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

run "rejects_a_name_prefix_that_is_too_short" {
  command = plan

  variables {
    name_prefix = "ab"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_a_name_prefix_with_uppercase_letters" {
  command = plan

  variables {
    name_prefix = "Test-platform"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_a_name_prefix_starting_with_a_digit" {
  command = plan

  variables {
    name_prefix = "1test-platform"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_a_name_prefix_that_is_too_long" {
  command = plan

  variables {
    name_prefix = "a234567890123456789012345678901x"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_an_invalid_primary_region" {
  command = plan

  variables {
    primary_region = "useast2"
  }

  expect_failures = [var.primary_region]
}

run "rejects_an_invalid_replica_region" {
  command = plan

  variables {
    replica_region = "west"
  }

  expect_failures = [var.replica_region]
}

run "rejects_an_access_log_bucket_with_uppercase_letters" {
  command = plan

  variables {
    access_log_bucket_name = "Central-Logs"
  }

  expect_failures = [var.access_log_bucket_name]
}

run "rejects_an_access_log_bucket_that_is_too_short" {
  command = plan

  variables {
    access_log_bucket_name = "ab"
  }

  expect_failures = [var.access_log_bucket_name]
}

run "rejects_an_empty_access_log_prefix" {
  command = plan

  variables {
    access_log_prefix = ""
  }

  expect_failures = [var.access_log_prefix]
}

run "rejects_a_blank_access_log_prefix" {
  command = plan

  variables {
    access_log_prefix = "   "
  }

  expect_failures = [var.access_log_prefix]
}

run "rejects_a_deletion_window_below_7_days" {
  command = plan

  variables {
    kms_key_deletion_window_in_days = 6
  }

  expect_failures = [var.kms_key_deletion_window_in_days]
}

run "rejects_a_deletion_window_above_30_days" {
  command = plan

  variables {
    kms_key_deletion_window_in_days = 31
  }

  expect_failures = [var.kms_key_deletion_window_in_days]
}

run "rejects_a_fractional_deletion_window" {
  command = plan

  variables {
    kms_key_deletion_window_in_days = 7.5
  }

  expect_failures = [var.kms_key_deletion_window_in_days]
}

run "rejects_a_single_state_access_principal" {
  command = plan

  variables {
    state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform"]
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_a_state_access_principal_that_is_a_user" {
  command = plan

  variables {
    state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform", "arn:aws:iam::111122223333:user/alice"]
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_the_account_root_as_a_state_access_principal" {
  command = plan

  variables {
    state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform", "arn:aws:iam::111122223333:root"]
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_a_wildcard_state_access_principal" {
  command = plan

  variables {
    state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform", "*"]
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_no_key_administrators" {
  command = plan

  variables {
    key_administrator_arns = []
  }

  expect_failures = [var.key_administrator_arns]
}

run "rejects_a_key_administrator_that_is_not_a_role" {
  command = plan

  variables {
    key_administrator_arns = ["arn:aws:iam::111122223333:user/alice"]
  }

  expect_failures = [var.key_administrator_arns]
}

run "rejects_a_tag_key_with_the_reserved_aws_prefix" {
  command = plan

  variables {
    tags = { "aws:cloudformation:stack-name" = "x" }
  }

  expect_failures = [var.tags]
}

run "rejects_an_empty_tag_key" {
  command = plan

  variables {
    tags = { "" = "x" }
  }

  expect_failures = [var.tags]
}

run "accepts_the_boundaries_of_the_scalar_inputs" {
  command = plan

  variables {
    name_prefix                     = "abc"
    kms_key_deletion_window_in_days = 7
    tags                            = { "Cost-Center" = "1234" }
  }

  assert {
    condition     = length(aws_kms_key.state) == 3 && aws_kms_key.state["dev"].deletion_window_in_days == 7
    error_message = "A 3-character prefix, a 7-day window and an ordinary tag key must be accepted."
  }
}

run "accepts_a_30_day_deletion_window_and_a_31_character_prefix_without_replicas" {
  command = plan

  variables {
    name_prefix                     = "a234567890123456789012345678901"
    kms_key_deletion_window_in_days = 30
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
    condition     = aws_kms_key.state["dev"].deletion_window_in_days == 30
    error_message = "The upper boundaries must be accepted."
  }
}

run "rejects_an_empty_tier_map" {
  command = plan

  variables {
    state_tiers = {}
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_tier_name_with_uppercase_letters" {
  command = plan

  variables {
    state_tiers = {
      Prod = {
        bucket_name                                  = "test-platform-prod-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_one_character_tier_name" {
  command = plan

  variables {
    state_tiers = {
      p = {
        bucket_name                                  = "test-platform-p-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_tier_name_starting_with_a_digit" {
  command = plan

  variables {
    state_tiers = {
      "1prod" = {
        bucket_name                                  = "test-platform-1prod-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_tier_name_with_an_underscore" {
  command = plan

  variables {
    state_tiers = {
      prod_a = {
        bucket_name                                  = "test-platform-prod-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_with_uppercase_letters" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "Test-Platform-Dev"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_with_an_underscore" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test_platform_dev"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_that_is_too_short" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "ab"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_that_is_too_long" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_ending_in_a_hyphen" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_with_adjacent_dots" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test..platform"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_shaped_like_an_ip_address" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "192.168.5.4"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_with_a_reserved_prefix" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "sthree-test-platform"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_bucket_name_with_a_reserved_suffix" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-s3alias"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_an_invalid_replica_bucket_name" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        replica_bucket_name                          = "Test_Replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_replica_bucket_name_with_a_reserved_prefix" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        replica_bucket_name                          = "xn--test-platform-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_replica_bucket_equal_to_its_primary" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        replica_bucket_name                          = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_two_tiers_sharing_a_bucket_name" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-shared-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
      prod = {
        bucket_name                                  = "test-platform-shared-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_replica_bucket_reusing_another_tiers_primary" {
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
      prod = {
        bucket_name                                  = "test-platform-prod-tfstate"
        replica_bucket_name                          = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_two_tiers_sharing_a_replica_bucket_name" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        replica_bucket_name                          = "test-platform-shared-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
      prod = {
        bucket_name                                  = "test-platform-prod-tfstate"
        replica_bucket_name                          = "test-platform-shared-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_zero_noncurrent_expiration" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 0
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_negative_noncurrent_expiration" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = -5
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_fractional_noncurrent_expiration" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30.5
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_zero_multipart_abort_period" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 0
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_a_fractional_multipart_abort_period" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 2.5
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_without_a_retention_mode" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_days = 30
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_with_an_unknown_retention_mode" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "SOFT"
          retention_days = 30
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_with_a_lowercase_retention_mode" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "governance"
          retention_days = 30
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_without_retention_days" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "GOVERNANCE"
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_with_zero_retention_days" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "GOVERNANCE"
          retention_days = 0
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "rejects_object_lock_with_fractional_retention_days" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = true
          retention_mode = "COMPLIANCE"
          retention_days = 1.5
        }
      }
    }
  }

  expect_failures = [var.state_tiers]
}

run "accepts_valid_edge_case_bucket_names" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "a1.b-2"
        replica_bucket_name                          = "abc"
        noncurrent_version_expiration_in_days        = 1
        abort_incomplete_multipart_upload_after_days = 1
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition     = aws_s3_bucket.state["dev"].bucket == "a1.b-2" && aws_s3_bucket.state_replica["dev"].bucket == "abc"
    error_message = "Dots and hyphens inside a name, a 3-character name and 1-day periods must be accepted."
  }
}

run "accepts_a_63_character_bucket_name_and_a_two_character_tier_name" {
  command = plan

  variables {
    state_tiers = {
      qa = {
        bucket_name                                  = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket.state["qa"].bucket) == 63
    error_message = "The 63-character bucket name and 2-character tier name boundaries must be accepted."
  }
}

run "accepts_retention_mode_and_days_with_object_lock_disabled" {
  command = plan

  variables {
    state_tiers = {
      dev = {
        bucket_name                                  = "test-platform-dev-tfstate"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled        = false
          retention_mode = "GOVERNANCE"
          retention_days = 30
        }
      }
    }
  }

  expect_failures = [check.object_lock_settings_are_used]
}
