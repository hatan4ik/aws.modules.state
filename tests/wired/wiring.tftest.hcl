# Wiring suite: the whole root is APPLIED under mock providers and every policy
# document is read back from the resource that carries it.
#
# Why this exists. The documents are rendered by modules/policies (tested there
# with known ARNs) from ARNs the root passes in. Those ARNs are unknown at plan
# time, so a plan-only test cannot see whether the root passed the right ARN of
# the right tier to the right document. An apply can, but `terraform test` tears
# down what it applied, and teardown fails on the prevent_destroy guards ADR 0008
# requires. scripts/test-wired.sh therefore runs this directory against a
# temporary copy of the module with the guards lifted (scripts/lift-destroy-guards.sh);
# the committed tree is never changed. Run it with `make test-wired`.
#
# Every instance gets a distinct ARN through override_resource, so a document that
# named the wrong tier's bucket, key or role fails an assertion. Tiers: dev (no
# replica), staging (replica, GOVERNANCE Object Lock), prod (replica, COMPLIANCE).

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

override_resource {
  target = aws_s3_bucket.state["dev"]
  values = {
    id  = "test-platform-dev-tfstate"
    arn = "arn:aws:s3:::test-platform-dev-tfstate"
  }
}

override_resource {
  target = aws_kms_key.state["dev"]
  values = {
    key_id = "mrk-dev"
    arn    = "arn:aws:kms:us-east-2:111122223333:key/mrk-dev"
  }
}

override_resource {
  target = aws_dynamodb_table.state_lock["dev"]
  values = {
    arn = "arn:aws:dynamodb:us-east-2:111122223333:table/test-platform-dev-terraform-locks"
  }
}

override_resource {
  target = aws_s3_bucket.state["staging"]
  values = {
    id  = "test-platform-staging-tfstate"
    arn = "arn:aws:s3:::test-platform-staging-tfstate"
  }
}

override_resource {
  target = aws_kms_key.state["staging"]
  values = {
    key_id = "mrk-staging"
    arn    = "arn:aws:kms:us-east-2:111122223333:key/mrk-staging"
  }
}

override_resource {
  target = aws_dynamodb_table.state_lock["staging"]
  values = {
    arn = "arn:aws:dynamodb:us-east-2:111122223333:table/test-platform-staging-terraform-locks"
  }
}

override_resource {
  target = aws_s3_bucket.state["prod"]
  values = {
    id  = "test-platform-prod-tfstate"
    arn = "arn:aws:s3:::test-platform-prod-tfstate"
  }
}

override_resource {
  target = aws_kms_key.state["prod"]
  values = {
    key_id = "mrk-prod"
    arn    = "arn:aws:kms:us-east-2:111122223333:key/mrk-prod"
  }
}

override_resource {
  target = aws_dynamodb_table.state_lock["prod"]
  values = {
    arn = "arn:aws:dynamodb:us-east-2:111122223333:table/test-platform-prod-terraform-locks"
  }
}

override_resource {
  target = aws_s3_bucket.state_replica["staging"]
  values = {
    id  = "test-platform-staging-tfstate-replica"
    arn = "arn:aws:s3:::test-platform-staging-tfstate-replica"
  }
}

override_resource {
  target = aws_kms_replica_key.state["staging"]
  values = {
    key_id = "mrk-staging"
    arn    = "arn:aws:kms:us-west-2:111122223333:key/mrk-staging"
  }
}

override_resource {
  target = aws_iam_role.state_replication["staging"]
  values = {
    id  = "test-platform-staging-terraform-state-replication"
    arn = "arn:aws:iam::111122223333:role/test-platform-staging-terraform-state-replication"
  }
}

override_resource {
  target = aws_s3_bucket.state_replica["prod"]
  values = {
    id  = "test-platform-prod-tfstate-replica"
    arn = "arn:aws:s3:::test-platform-prod-tfstate-replica"
  }
}

override_resource {
  target = aws_kms_replica_key.state["prod"]
  values = {
    key_id = "mrk-prod"
    arn    = "arn:aws:kms:us-west-2:111122223333:key/mrk-prod"
  }
}

override_resource {
  target = aws_iam_role.state_replication["prod"]
  values = {
    id  = "test-platform-prod-terraform-state-replication"
    arn = "arn:aws:iam::111122223333:role/test-platform-prod-terraform-state-replication"
  }
}

run "apply_the_three_tier_deployment" {
  command = apply

  # --- primary key policies -------------------------------------------------
  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        jsondecode(aws_kms_key.state[tier].policy).Statement[0].Sid == "KeyAdministration" &&
        jsondecode(aws_kms_key.state[tier].policy).Statement[0].Principal.AWS == ["arn:aws:iam::111122223333:role/key-admin"] &&
        jsondecode(aws_kms_key.state[tier].policy).Statement[1].Sid == "StateEncryptionUse"
      )
    ])
    error_message = "Every primary key must carry its own key policy with the administrators and the use statement."
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.state["dev"].policy).Statement[1].Principal.AWS == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
      ] &&
      jsondecode(aws_kms_key.state["staging"].policy).Statement[1].Principal.AWS == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
        "arn:aws:iam::111122223333:role/test-platform-staging-terraform-state-replication",
      ] &&
      jsondecode(aws_kms_key.state["prod"].policy).Statement[1].Principal.AWS == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
        "arn:aws:iam::111122223333:role/test-platform-prod-terraform-state-replication",
      ]
    )
    error_message = "Each key policy must grant use to the state roles and only its own tier's replication role."
  }

  assert {
    condition = (
      !strcontains(aws_kms_key.state["dev"].policy, "replication") &&
      !strcontains(aws_kms_key.state["staging"].policy, "test-platform-prod") &&
      !strcontains(aws_kms_key.state["prod"].policy, "test-platform-staging")
    )
    error_message = "No key policy may name another tier's replication role."
  }

  assert {
    condition = (
      length(jsondecode(aws_kms_key.state["dev"].policy).Statement) == 2 &&
      !strcontains(aws_kms_key.state["dev"].policy, "kms:ReplicateKey") &&
      alltrue([
        for tier in ["staging", "prod"] : (
          length(jsondecode(aws_kms_key.state[tier].policy).Statement) == 3 &&
          jsondecode(aws_kms_key.state[tier].policy).Statement[2].Sid == "KeyReplication" &&
          jsondecode(aws_kms_key.state[tier].policy).Statement[2].Action == ["kms:ReplicateKey"] &&
          jsondecode(aws_kms_key.state[tier].policy).Statement[2].Principal.AWS == ["arn:aws:iam::111122223333:role/key-admin"]
        )
      ])
    )
    error_message = "Only a replicated tier's primary key may allow kms:ReplicateKey, and only to the key administrators, so aws_kms_replica_key can be created."
  }

  # --- replica key policies -------------------------------------------------
  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        jsondecode(aws_kms_replica_key.state[tier].policy).Statement[1].Sid == "StateReplicaEncryptionUse" &&
        jsondecode(aws_kms_replica_key.state[tier].policy).Statement[1].Principal.AWS == [
          "arn:aws:iam::111122223333:role/break-glass",
          "arn:aws:iam::111122223333:role/ci-terraform",
          "arn:aws:iam::111122223333:role/test-platform-${tier}-terraform-state-replication",
        ] &&
        jsondecode(aws_kms_replica_key.state[tier].policy).Statement[0].Principal.AWS == ["arn:aws:iam::111122223333:role/key-admin"]
      )
    ])
    error_message = "Each replica key must carry the replica policy of its own tier."
  }

  assert {
    condition = (
      aws_kms_replica_key.state["staging"].primary_key_arn == "arn:aws:kms:us-east-2:111122223333:key/mrk-staging" &&
      aws_kms_replica_key.state["prod"].primary_key_arn == "arn:aws:kms:us-east-2:111122223333:key/mrk-prod"
    )
    error_message = "Each replica key must replicate its own tier's primary key."
  }

  # --- primary bucket policies ----------------------------------------------
  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        aws_s3_bucket_policy.state[tier].bucket == "test-platform-${tier}-tfstate" &&
        jsondecode(aws_s3_bucket_policy.state[tier].policy).Statement[0].Sid == "DenyInsecureTransport" &&
        jsondecode(aws_s3_bucket_policy.state[tier].policy).Statement[0].Resource == ["arn:aws:s3:::test-platform-${tier}-tfstate", "arn:aws:s3:::test-platform-${tier}-tfstate/*"] &&
        jsondecode(aws_s3_bucket_policy.state[tier].policy).Statement[1].Resource == ["arn:aws:s3:::test-platform-${tier}-tfstate", "arn:aws:s3:::test-platform-${tier}-tfstate/*"] &&
        jsondecode(aws_s3_bucket_policy.state[tier].policy).Statement[2].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate" &&
        jsondecode(aws_s3_bucket_policy.state[tier].policy).Statement[3].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate/*"
      )
    ])
    error_message = "Each bucket policy must be attached to its own bucket and name only that bucket."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.state["dev"].policy).Statement[1].Condition.ArnNotEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
      ] &&
      jsondecode(aws_s3_bucket_policy.state["staging"].policy).Statement[1].Condition.ArnNotEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
        "arn:aws:iam::111122223333:role/test-platform-staging-terraform-state-replication",
      ] &&
      jsondecode(aws_s3_bucket_policy.state["prod"].policy).Statement[1].Condition.ArnNotEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::111122223333:role/break-glass",
        "arn:aws:iam::111122223333:role/ci-terraform",
        "arn:aws:iam::111122223333:role/test-platform-prod-terraform-state-replication",
      ]
    )
    error_message = "Each bucket's deny exemption must list the state roles and only its own tier's replication role."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        !strcontains(aws_s3_bucket_policy.state[tier].policy, "tfstate-replica") &&
        length([for other in ["dev", "staging", "prod"] : other if other != tier && strcontains(aws_s3_bucket_policy.state[tier].policy, "test-platform-${other}-")]) == 0
      )
    ])
    error_message = "No bucket policy may reference a replica bucket or another tier's bucket or role."
  }

  # --- replica bucket policies ----------------------------------------------
  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_s3_bucket_policy.state_replica[tier].bucket == "test-platform-${tier}-tfstate-replica" &&
        jsondecode(aws_s3_bucket_policy.state_replica[tier].policy).Statement[0].Resource == ["arn:aws:s3:::test-platform-${tier}-tfstate-replica", "arn:aws:s3:::test-platform-${tier}-tfstate-replica/*"] &&
        jsondecode(aws_s3_bucket_policy.state_replica[tier].policy).Statement[2].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate-replica" &&
        jsondecode(aws_s3_bucket_policy.state_replica[tier].policy).Statement[3].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate-replica/*" &&
        jsondecode(aws_s3_bucket_policy.state_replica[tier].policy).Statement[1].Condition.ArnNotEquals["aws:PrincipalArn"] == [
          "arn:aws:iam::111122223333:role/break-glass",
          "arn:aws:iam::111122223333:role/ci-terraform",
          "arn:aws:iam::111122223333:role/test-platform-${tier}-terraform-state-replication",
        ]
      )
    ])
    error_message = "Each replica bucket policy must be attached to its own replica bucket and exempt only its own tier's replication role."
  }

  # --- replication policies and roles ---------------------------------------
  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_iam_role_policy.state_replication[tier].role == "test-platform-${tier}-terraform-state-replication" &&
        jsondecode(aws_iam_role_policy.state_replication[tier].policy).Statement[0].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate" &&
        jsondecode(aws_iam_role_policy.state_replication[tier].policy).Statement[1].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate/*" &&
        jsondecode(aws_iam_role_policy.state_replication[tier].policy).Statement[2].Resource == "arn:aws:s3:::test-platform-${tier}-tfstate-replica/*" &&
        jsondecode(aws_iam_role_policy.state_replication[tier].policy).Statement[3].Resource == "arn:aws:kms:us-east-2:111122223333:key/mrk-${tier}" &&
        jsondecode(aws_iam_role_policy.state_replication[tier].policy).Statement[4].Resource == "arn:aws:kms:us-west-2:111122223333:key/mrk-${tier}"
      )
    ])
    error_message = "Each replication policy must be attached to its own tier's role and reach only that tier's buckets and keys."
  }

  assert {
    condition = (
      !strcontains(aws_iam_role_policy.state_replication["staging"].policy, "prod") &&
      !strcontains(aws_iam_role_policy.state_replication["staging"].policy, "dev") &&
      !strcontains(aws_iam_role_policy.state_replication["prod"].policy, "staging") &&
      !strcontains(aws_iam_role_policy.state_replication["prod"].policy, "dev")
    )
    error_message = "A replication policy must never reference another tier."
  }

  # --- replication configuration and encryption wiring ----------------------
  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_s3_bucket_replication_configuration.state[tier].bucket == "test-platform-${tier}-tfstate" &&
        aws_s3_bucket_replication_configuration.state[tier].role == "arn:aws:iam::111122223333:role/test-platform-${tier}-terraform-state-replication" &&
        one(one(aws_s3_bucket_replication_configuration.state[tier].rule).destination).bucket == "arn:aws:s3:::test-platform-${tier}-tfstate-replica" &&
        one(one(one(aws_s3_bucket_replication_configuration.state[tier].rule).destination).encryption_configuration).replica_kms_key_id == "arn:aws:kms:us-west-2:111122223333:key/mrk-${tier}"
      )
    ])
    error_message = "Each replication configuration must use its own role, source bucket, replica bucket and replica key."
  }

  assert {
    condition = alltrue([
      for tier in ["dev", "staging", "prod"] : (
        one(one(aws_s3_bucket_server_side_encryption_configuration.state[tier].rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-2:111122223333:key/mrk-${tier}" &&
        one(aws_dynamodb_table.state_lock[tier].server_side_encryption).kms_key_arn == "arn:aws:kms:us-east-2:111122223333:key/mrk-${tier}" &&
        aws_kms_alias.state[tier].target_key_id == "mrk-${tier}"
      )
    ])
    error_message = "Each tier's bucket, lock table and alias must use that tier's own key."
  }

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        one(one(aws_s3_bucket_server_side_encryption_configuration.state_replica[tier].rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-west-2:111122223333:key/mrk-${tier}" &&
        aws_kms_alias.state_replica[tier].target_key_id == "mrk-${tier}"
      )
    ])
    error_message = "Each replica bucket and replica alias must use that tier's own replica key."
  }

  # --- outputs ---------------------------------------------------------------
  # Compared field by field: an object with a null field and an object with a
  # string field have different types, so whole-object equality is always false.
  assert {
    condition = (
      output.backend_configuration["prod"].bucket == "test-platform-prod-tfstate" &&
      output.backend_configuration["prod"].kms_key_id == "arn:aws:kms:us-east-2:111122223333:key/mrk-prod" &&
      output.backend_configuration["prod"].dynamodb_table == "test-platform-prod-terraform-locks" &&
      output.backend_configuration["prod"].use_lockfile == true &&
      output.backend_configuration["prod"].replica_bucket == "test-platform-prod-tfstate-replica" &&
      output.backend_configuration["prod"].replica_region == "us-west-2" &&
      output.backend_configuration["prod"].replica_key_id == "arn:aws:kms:us-west-2:111122223333:key/mrk-prod"
    )
    error_message = "backend_configuration must expose the replicated tier's own bucket, key, lock table and replica values."
  }

  assert {
    condition = (
      output.backend_configuration["dev"].bucket == "test-platform-dev-tfstate" &&
      output.backend_configuration["dev"].kms_key_id == "arn:aws:kms:us-east-2:111122223333:key/mrk-dev" &&
      output.backend_configuration["dev"].dynamodb_table == "test-platform-dev-terraform-locks" &&
      output.backend_configuration["dev"].use_lockfile == true &&
      output.backend_configuration["dev"].replica_bucket == null &&
      output.backend_configuration["dev"].replica_region == null &&
      output.backend_configuration["dev"].replica_key_id == null
    )
    error_message = "backend_configuration must expose the non-replicated tier's own values with null replica fields."
  }

  assert {
    condition = (
      output.state_access_policy_arns["staging"].bucket_arn == "arn:aws:s3:::test-platform-staging-tfstate" &&
      output.state_access_policy_arns["staging"].key_arn == "arn:aws:kms:us-east-2:111122223333:key/mrk-staging" &&
      output.state_access_policy_arns["staging"].lock_arn == "arn:aws:dynamodb:us-east-2:111122223333:table/test-platform-staging-terraform-locks" &&
      output.state_access_policy_arns["staging"].replica_bucket_arn == "arn:aws:s3:::test-platform-staging-tfstate-replica" &&
      output.state_access_policy_arns["staging"].replica_key_arn == "arn:aws:kms:us-west-2:111122223333:key/mrk-staging"
    )
    error_message = "state_access_policy_arns must expose the replicated tier's own ARNs."
  }

  assert {
    condition = (
      output.state_access_policy_arns["dev"].bucket_arn == "arn:aws:s3:::test-platform-dev-tfstate" &&
      output.state_access_policy_arns["dev"].key_arn == "arn:aws:kms:us-east-2:111122223333:key/mrk-dev" &&
      output.state_access_policy_arns["dev"].lock_arn == "arn:aws:dynamodb:us-east-2:111122223333:table/test-platform-dev-terraform-locks" &&
      output.state_access_policy_arns["dev"].replica_bucket_arn == null &&
      output.state_access_policy_arns["dev"].replica_key_arn == null
    )
    error_message = "state_access_policy_arns must expose the non-replicated tier's own ARNs with null replica ARNs."
  }
}
