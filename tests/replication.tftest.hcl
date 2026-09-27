# Cross-Region replication and the replica copy, per tier variant. Plan only, under
# mock_provider: everything asserted here is configuration and therefore known at
# plan time. The replication role's policy and the replica documents embed
# computed ARNs; they are asserted in modules/policies/tests and wired in
# tests/wired.
#
# Variants: replicated with Object Lock GOVERNANCE (staging), replicated with
# Object Lock COMPLIANCE (prod), replicated without Object Lock, not replicated
# (dev, see posture.tftest.hcl).

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

run "every_replicated_tier_gets_a_full_replica_set_and_no_other_tier_does" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_s3_bucket.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_kms_replica_key.state)) == toset(["staging", "prod"]) &&
      toset(keys(aws_kms_alias.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_public_access_block.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_ownership_controls.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_versioning.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_server_side_encryption_configuration.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_lifecycle_configuration.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_logging.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_notification.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_policy.state_replica)) == toset(["staging", "prod"]) &&
      toset(keys(aws_iam_role.state_replication)) == toset(["staging", "prod"]) &&
      toset(keys(aws_iam_role_policy.state_replication)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_replication_configuration.state)) == toset(["staging", "prod"])
    )
    error_message = "Exactly the tiers that name a replica bucket must receive the complete replica set, one of each resource."
  }
}

run "replica_buckets_have_the_same_controls_as_the_primary" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_s3_bucket_public_access_block.state_replica[tier].block_public_acls &&
        aws_s3_bucket_public_access_block.state_replica[tier].block_public_policy &&
        aws_s3_bucket_public_access_block.state_replica[tier].ignore_public_acls &&
        aws_s3_bucket_public_access_block.state_replica[tier].restrict_public_buckets &&
        one(aws_s3_bucket_ownership_controls.state_replica[tier].rule).object_ownership == "BucketOwnerEnforced" &&
        one(aws_s3_bucket_versioning.state_replica[tier].versioning_configuration).status == "Enabled" &&
        aws_s3_bucket_notification.state_replica[tier].eventbridge == true
      )
    ])
    error_message = "Every replica bucket must be private, owner-enforced, versioned and publish EventBridge events."
  }

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        one(aws_s3_bucket_server_side_encryption_configuration.state_replica[tier].rule).bucket_key_enabled == true &&
        one(one(aws_s3_bucket_server_side_encryption_configuration.state_replica[tier].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
      )
    ])
    error_message = "Every replica bucket must default-encrypt with SSE-KMS and a Bucket Key."
  }

  assert {
    condition = (
      aws_s3_bucket.state_replica["staging"].bucket == "test-platform-staging-tfstate-replica" &&
      aws_s3_bucket.state_replica["prod"].bucket == "test-platform-prod-tfstate-replica" &&
      aws_s3_bucket.state_replica["prod"].tags["ReplicaRegion"] == "us-west-2" &&
      aws_s3_bucket.state_replica["prod"].tags["EnvironmentTier"] == "prod" &&
      aws_s3_bucket.state_replica["prod"].tags["Component"] == "terraform-state" &&
      aws_s3_bucket.state_replica["prod"].tags["Owner"] == "platform"
    )
    error_message = "Replica buckets must use the declared replica names and carry the tier, Region and component tags."
  }

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_s3_bucket_logging.state_replica[tier].target_bucket == "test-platform-central-access-logs" &&
        aws_s3_bucket_logging.state_replica[tier].target_prefix == "test-platform/terraform-state/replica/${tier}/"
      )
    ])
    error_message = "Every replica bucket must log to the central bucket under its own replica prefix."
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_lifecycle_configuration.state_replica["staging"].rule).noncurrent_version_expiration).noncurrent_days == 45 &&
      one(one(aws_s3_bucket_lifecycle_configuration.state_replica["staging"].rule).abort_incomplete_multipart_upload).days_after_initiation == 3 &&
      one(one(aws_s3_bucket_lifecycle_configuration.state_replica["prod"].rule).noncurrent_version_expiration).noncurrent_days == 90 &&
      one(one(aws_s3_bucket_lifecycle_configuration.state_replica["prod"].rule).abort_incomplete_multipart_upload).days_after_initiation == 7 &&
      one(aws_s3_bucket_lifecycle_configuration.state_replica["prod"].rule).status == "Enabled" &&
      length(one(aws_s3_bucket_lifecycle_configuration.state_replica["prod"].rule).expiration) == 0
    )
    error_message = "The replica lifecycle rule must use the tier's own periods and never expire current objects."
  }
}

run "object_lock_applies_to_both_copies_of_a_replicated_tier" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket.state["staging"].object_lock_enabled == true &&
      aws_s3_bucket.state_replica["staging"].object_lock_enabled == true &&
      aws_s3_bucket.state["prod"].object_lock_enabled == true &&
      aws_s3_bucket.state_replica["prod"].object_lock_enabled == true
    )
    error_message = "A replicated tier that enables Object Lock must lock the primary and the replica bucket."
  }

  assert {
    condition = (
      toset(keys(aws_s3_bucket_object_lock_configuration.state)) == toset(["staging", "prod"]) &&
      toset(keys(aws_s3_bucket_object_lock_configuration.state_replica)) == toset(["staging", "prod"])
    )
    error_message = "Both copies of a locked tier must carry a default retention."
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_object_lock_configuration.state["staging"].rule).default_retention).mode == "GOVERNANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state_replica["staging"].rule).default_retention).mode == "GOVERNANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state["staging"].rule).default_retention).days == 30 &&
      one(one(aws_s3_bucket_object_lock_configuration.state_replica["staging"].rule).default_retention).days == 30 &&
      one(one(aws_s3_bucket_object_lock_configuration.state["prod"].rule).default_retention).mode == "COMPLIANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state_replica["prod"].rule).default_retention).mode == "COMPLIANCE" &&
      one(one(aws_s3_bucket_object_lock_configuration.state["prod"].rule).default_retention).days == 60 &&
      one(one(aws_s3_bucket_object_lock_configuration.state_replica["prod"].rule).default_retention).days == 60
    )
    error_message = "The replica's default retention must equal the primary's mode and days for the tier."
  }
}

run "a_replicated_tier_without_object_lock_locks_neither_copy" {
  command = plan

  variables {
    state_tiers = {
      plain = {
        bucket_name                                  = "test-platform-plain-tfstate"
        replica_bucket_name                          = "test-platform-plain-tfstate-replica"
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
      aws_s3_bucket.state["plain"].object_lock_enabled == false &&
      aws_s3_bucket.state_replica["plain"].object_lock_enabled == false &&
      length(aws_s3_bucket_object_lock_configuration.state) == 0 &&
      length(aws_s3_bucket_object_lock_configuration.state_replica) == 0
    )
    error_message = "A replicated tier that does not enable Object Lock must lock neither copy."
  }

  assert {
    condition = (
      length(aws_s3_bucket.state_replica) == 1 &&
      length(aws_iam_role.state_replication) == 1 &&
      length(aws_s3_bucket_replication_configuration.state) == 1
    )
    error_message = "The tier must still replicate."
  }
}

run "replica_keys_are_named_and_tagged_for_their_tier_and_region" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_kms_replica_key.state[tier].deletion_window_in_days == 30 &&
        aws_kms_replica_key.state[tier].description == "Terraform state replica encryption key for ${tier} in us-west-2" &&
        aws_kms_replica_key.state[tier].tags["Name"] == "test-platform-${tier}-terraform-state-replica" &&
        aws_kms_replica_key.state[tier].tags["ReplicaRegion"] == "us-west-2" &&
        aws_kms_replica_key.state[tier].tags["EnvironmentTier"] == tier &&
        aws_kms_alias.state_replica[tier].name == "alias/test-platform-${tier}-terraform-state"
      )
    ])
    error_message = "Replica keys must carry the tier and Region in their description and tags, and the same alias name as the primary."
  }
}

run "each_replicated_tier_gets_its_own_replication_role" {
  command = plan

  assert {
    condition = (
      aws_iam_role.state_replication["staging"].name == "test-platform-staging-terraform-state-replication" &&
      aws_iam_role.state_replication["prod"].name == "test-platform-prod-terraform-state-replication" &&
      aws_iam_role_policy.state_replication["staging"].name == "test-platform-staging-terraform-state-replication" &&
      aws_iam_role_policy.state_replication["prod"].name == "test-platform-prod-terraform-state-replication" &&
      aws_iam_role.state_replication["staging"].name != aws_iam_role.state_replication["prod"].name
    )
    error_message = "Every replicated tier must have a distinctly named role and inline policy."
  }

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        aws_iam_role.state_replication[tier].tags["EnvironmentTier"] == tier &&
        aws_iam_role.state_replication[tier].tags["Component"] == "terraform-state" &&
        aws_iam_role.state_replication[tier].tags["Name"] == "test-platform-${tier}-terraform-state-replication"
      )
    ])
    error_message = "Replication roles must carry their tier and component tags."
  }
}

run "replication_roles_are_assumable_by_s3_only" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Version == "2012-10-17" &&
        length(jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Statement) == 1 &&
        jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Statement[0].Effect == "Allow" &&
        jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
        jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Statement[0].Principal == { Service = "s3.amazonaws.com" } &&
        !can(jsondecode(aws_iam_role.state_replication[tier].assume_role_policy).Statement[0].Condition)
      )
    ])
    error_message = "A replication role must trust only the S3 service principal and nothing else."
  }
}

run "the_replication_rule_replicates_everything_encrypted_under_the_replica_key" {
  command = plan

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        one(aws_s3_bucket_replication_configuration.state[tier].rule).id == "replicate-state-to-us-west-2" &&
        one(aws_s3_bucket_replication_configuration.state[tier].rule).status == "Enabled" &&
        one(one(aws_s3_bucket_replication_configuration.state[tier].rule).delete_marker_replication).status == "Enabled" &&
        one(one(one(aws_s3_bucket_replication_configuration.state[tier].rule).source_selection_criteria).sse_kms_encrypted_objects).status == "Enabled" &&
        one(one(aws_s3_bucket_replication_configuration.state[tier].rule).destination).storage_class == "STANDARD"
      )
    ])
    error_message = "Each replicated tier must replicate all objects and delete markers, including SSE-KMS objects, into STANDARD storage in the replica Region."
  }

  assert {
    condition = alltrue([
      for tier in ["staging", "prod"] : (
        length(one(aws_s3_bucket_replication_configuration.state[tier].rule).filter) == 1 &&
        length(one(one(aws_s3_bucket_replication_configuration.state[tier].rule).destination).encryption_configuration) == 1
      )
    ])
    error_message = "The replication rule must have an empty filter (everything) and an explicit replica-key encryption configuration."
  }
}
