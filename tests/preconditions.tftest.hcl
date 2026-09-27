# Provider-to-Region binding (ADR 0008, 2026-09-20 amendment) and the other
# cross-input preconditions. Each failing run names the one object whose
# precondition must fail.

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

run "accepts_providers_bound_to_the_declared_regions" {
  command = plan

  assert {
    condition     = length(aws_kms_key.state) == 3 && length(aws_kms_replica_key.state) == 2
    error_message = "Providers bound to primary_region and replica_region must be accepted."
  }
}

run "rejects_a_default_provider_bound_to_another_region" {
  command = plan

  variables {
    primary_region = "eu-west-1"
  }

  expect_failures = [aws_kms_key.state]
}

run "rejects_a_replica_provider_bound_to_another_region" {
  command = plan

  variables {
    replica_region = "eu-central-1"
  }

  expect_failures = [aws_kms_replica_key.state]
}

run "rejects_the_same_primary_and_replica_region_when_a_tier_replicates" {
  command = plan

  variables {
    replica_region = "us-east-2"
  }

  expect_failures = [aws_s3_bucket.state, aws_kms_replica_key.state]
}

run "accepts_the_same_region_when_no_tier_replicates" {
  command = plan

  variables {
    replica_region = "us-east-2"
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
    condition     = length(aws_kms_key.state) == 1 && length(aws_kms_replica_key.state) == 0
    error_message = "Without a replicated tier the replica Region is unused, so it may equal the primary Region."
  }
}

run "rejects_an_access_log_bucket_that_is_a_state_bucket" {
  command = plan

  variables {
    access_log_bucket_name = "test-platform-prod-tfstate"
  }

  expect_failures = [aws_s3_bucket_logging.state]
}

run "rejects_an_access_log_bucket_that_is_a_replica_bucket" {
  command = plan

  variables {
    access_log_bucket_name = "test-platform-staging-tfstate-replica"
  }

  expect_failures = [aws_s3_bucket_logging.state]
}

run "rejects_a_replication_role_name_longer_than_iam_allows" {
  command = plan

  variables {
    name_prefix = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    state_tiers = {
      cdddddddddddddddddddddddddddddd = {
        bucket_name                                  = "test-platform-long-tfstate"
        replica_bucket_name                          = "test-platform-long-tfstate-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [aws_iam_role.state_replication]
}

run "accepts_a_replication_role_name_of_exactly_64_characters" {
  command = plan

  variables {
    state_tiers = {
      abbbbbbbbbbbbbbbbbbbbb = {
        bucket_name                                  = "test-platform-limit-tfstate"
        replica_bucket_name                          = "test-platform-limit-tfstate-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.state_replication["abbbbbbbbbbbbbbbbbbbbb"].name) == 64
    error_message = "A role name of exactly 64 characters must be accepted."
  }
}

run "rejects_a_replication_role_name_of_65_characters" {
  command = plan

  variables {
    state_tiers = {
      abbbbbbbbbbbbbbbbbbbbbb = {
        bucket_name                                  = "test-platform-limit-tfstate"
        replica_bucket_name                          = "test-platform-limit-tfstate-replica"
        noncurrent_version_expiration_in_days        = 30
        abort_incomplete_multipart_upload_after_days = 7
        object_lock = {
          enabled = false
        }
      }
    }
  }

  expect_failures = [aws_iam_role.state_replication]
}
