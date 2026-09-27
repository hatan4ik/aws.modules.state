# Every input validation and every cross-input precondition of the renderer,
# each with a failing case. The positive baseline is the same valid two-tier
# deployment (one replicated) that tests/policies.tftest.hcl renders.

variables {
  tiers = ["dev", "prod"]
  state_access_principal_arns = [
    "arn:aws:iam::111122223333:role/ci-terraform",
    "arn:aws:iam::111122223333:role/break-glass",
  ]
  key_administrator_arns = ["arn:aws:iam::111122223333:role/key-admin"]
  bucket_arns = {
    dev  = "arn:aws:s3:::test-platform-dev-tfstate"
    prod = "arn:aws:s3:::test-platform-prod-tfstate"
  }
  key_arns = {
    dev  = "arn:aws:kms:us-east-2:111122223333:key/mrk-dev"
    prod = "arn:aws:kms:us-east-2:111122223333:key/mrk-prod"
  }
  replication_role_arns = {
    prod = "arn:aws:iam::111122223333:role/test-platform-prod-terraform-state-replication"
  }
  replica_bucket_arns = {
    prod = "arn:aws:s3:::test-platform-prod-tfstate-replica"
  }
  replica_key_arns = {
    prod = "arn:aws:kms:us-west-2:111122223333:key/mrk-prod"
  }
}

run "accepts_a_valid_deployment" {
  command = plan

  assert {
    condition     = length(output.key_policies) == 2 && length(output.replication_policies) == 1
    error_message = "The baseline must be accepted."
  }
}

run "rejects_no_tiers" {
  command = plan

  variables {
    tiers                 = []
    bucket_arns           = {}
    key_arns              = {}
    replication_role_arns = {}
    replica_bucket_arns   = {}
    replica_key_arns      = {}
  }

  expect_failures = [var.tiers]
}

run "rejects_a_tier_name_with_uppercase_letters" {
  command = plan

  variables {
    tiers = ["dev", "Prod"]
  }

  expect_failures = [var.tiers]
}

run "rejects_a_one_character_tier_name" {
  command = plan

  variables {
    tiers = ["dev", "p"]
  }

  expect_failures = [var.tiers]
}

run "rejects_a_tier_name_starting_with_a_digit" {
  command = plan

  variables {
    tiers = ["dev", "1prod"]
  }

  expect_failures = [var.tiers]
}

run "rejects_no_state_access_principals" {
  command = plan

  variables {
    state_access_principal_arns = []
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_a_state_access_principal_that_is_not_a_role" {
  command = plan

  variables {
    state_access_principal_arns = ["arn:aws:iam::111122223333:user/alice", "arn:aws:iam::111122223333:role/break-glass"]
  }

  expect_failures = [var.state_access_principal_arns]
}

run "rejects_a_wildcard_state_access_principal" {
  command = plan

  variables {
    state_access_principal_arns = ["*", "arn:aws:iam::111122223333:role/break-glass"]
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
    key_administrator_arns = ["arn:aws:iam::111122223333:root"]
  }

  expect_failures = [var.key_administrator_arns]
}

run "rejects_a_bucket_arn_that_is_not_an_s3_bucket" {
  command = plan

  variables {
    bucket_arns = {
      dev  = "arn:aws:s3:::test-platform-dev-tfstate"
      prod = "arn:aws:s3:::test-platform-prod-tfstate/object"
    }
  }

  expect_failures = [var.bucket_arns]
}

run "rejects_a_key_arn_that_is_an_alias" {
  command = plan

  variables {
    key_arns = {
      dev  = "arn:aws:kms:us-east-2:111122223333:key/mrk-dev"
      prod = "arn:aws:kms:us-east-2:111122223333:alias/prod"
    }
  }

  expect_failures = [var.key_arns]
}

run "rejects_a_replication_role_arn_that_is_not_a_role" {
  command = plan

  variables {
    replication_role_arns = {
      prod = "arn:aws:iam::111122223333:user/replication"
    }
  }

  expect_failures = [var.replication_role_arns]
}

run "rejects_a_replica_bucket_arn_that_is_not_an_s3_bucket" {
  command = plan

  variables {
    replica_bucket_arns = {
      prod = "test-platform-prod-tfstate-replica"
    }
  }

  expect_failures = [var.replica_bucket_arns]
}

run "rejects_a_replica_key_arn_that_is_not_a_key" {
  command = plan

  variables {
    replica_key_arns = {
      prod = "mrk-prod"
    }
  }

  expect_failures = [var.replica_key_arns]
}

run "rejects_a_replication_role_for_an_unknown_tier" {
  command = plan

  variables {
    replication_role_arns = {
      prod  = "arn:aws:iam::111122223333:role/test-platform-prod-terraform-state-replication"
      ghost = "arn:aws:iam::111122223333:role/test-platform-ghost-terraform-state-replication"
    }
  }

  expect_failures = [output.key_policies, output.replica_bucket_policies, output.replication_policies]
}

run "rejects_a_tier_without_a_bucket_arn" {
  command = plan

  variables {
    bucket_arns = {
      dev = "arn:aws:s3:::test-platform-dev-tfstate"
    }
  }

  expect_failures = [output.bucket_policies, output.replication_policies]
}

run "rejects_a_bucket_arn_for_an_unknown_tier" {
  command = plan

  variables {
    bucket_arns = {
      dev   = "arn:aws:s3:::test-platform-dev-tfstate"
      prod  = "arn:aws:s3:::test-platform-prod-tfstate"
      ghost = "arn:aws:s3:::test-platform-ghost-tfstate"
    }
  }

  expect_failures = [output.bucket_policies, output.replication_policies]
}

run "rejects_a_replicated_tier_without_a_replica_bucket_arn" {
  command = plan

  variables {
    replica_bucket_arns = {}
  }

  expect_failures = [output.replica_bucket_policies, output.replication_policies]
}

run "rejects_a_replicated_tier_without_a_replica_key_arn" {
  command = plan

  variables {
    replica_key_arns = {}
  }

  expect_failures = [output.replication_policies]
}

run "rejects_a_tier_without_a_key_arn" {
  command = plan

  variables {
    key_arns = {
      dev = "arn:aws:kms:us-east-2:111122223333:key/mrk-dev"
    }
  }

  expect_failures = [output.replication_policies]
}
