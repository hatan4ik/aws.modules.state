# The policy documents that ARE known at plan time. A tier without a replica has
# no replication role, so its key policy depends on inputs only and can be read
# from the resource. Every other document embeds a computed ARN: those are
# asserted in modules/policies/tests (content) and tests/wired (wiring).

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

run "a_tier_without_a_replica_gets_a_key_policy_for_the_state_roles_only" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_kms_key.state["dev"].policy).Statement) == 2 &&
      jsondecode(aws_kms_key.state["dev"].policy).Statement[0].Sid == "KeyAdministration" &&
      jsondecode(aws_kms_key.state["dev"].policy).Statement[0].Principal.AWS == ["arn:aws:iam::111122223333:role/key-admin"] &&
      jsondecode(aws_kms_key.state["dev"].policy).Statement[1].Sid == "StateEncryptionUse" &&
      jsondecode(aws_kms_key.state["dev"].policy).Statement[1].Principal.AWS == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
      ]
    )
    error_message = "The key policy of a non-replicated tier must administer with the key administrators and grant use to the CI and break-glass roles only."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_kms_key.state["dev"].policy).Statement : statement.Effect == "Allow" && statement.Resource == "*"
    ])
    error_message = "Key policy statements are Allow statements on the key itself."
  }
}

run "administrators_and_state_roles_are_rendered_sorted_regardless_of_input_order" {
  command = plan

  variables {
    state_access_principal_arns = [
      "arn:aws:iam::111122223333:role/zeta",
      "arn:aws:iam::111122223333:role/alpha",
      "arn:aws:iam::111122223333:role/mid",
    ]
    key_administrator_arns = [
      "arn:aws:iam::111122223333:role/key-b",
      "arn:aws:iam::111122223333:role/key-a",
    ]
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.state["dev"].policy).Statement[0].Principal.AWS == ["arn:aws:iam::111122223333:role/key-a", "arn:aws:iam::111122223333:role/key-b"] &&
      jsondecode(aws_kms_key.state["dev"].policy).Statement[1].Principal.AWS == [
        "arn:aws:iam::111122223333:role/alpha",
        "arn:aws:iam::111122223333:role/mid",
        "arn:aws:iam::111122223333:role/zeta",
      ]
    )
    error_message = "Principals must render sorted so the document is stable across runs."
  }
}
