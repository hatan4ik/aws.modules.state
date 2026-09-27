# One tier that opts into cross-Region replication by naming a replica bucket. The
# module then creates, for that tier only, a replica bucket and a KMS replica key
# in the replica Region (through the aws.replica alias) and an IAM replication
# role that reaches only this tier's two buckets and two keys.
#
# Each provider must be configured for the Region the module is told about: a
# precondition fails the plan when the default provider is not bound to
# primary_region or the aws.replica provider is not bound to replica_region.

provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

module "state" {
  source = "../../"

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  name_prefix            = var.name_prefix
  primary_region         = var.primary_region
  replica_region         = var.replica_region
  access_log_bucket_name = var.access_log_bucket_name
  access_log_prefix      = var.access_log_prefix

  state_tiers = {
    prod = {
      bucket_name                                  = var.bucket_name
      replica_bucket_name                          = var.replica_bucket_name
      noncurrent_version_expiration_in_days        = 90
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled = false
      }
    }
  }

  state_access_principal_arns     = var.state_access_principal_arns
  key_administrator_arns          = var.key_administrator_arns
  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days
  tags                            = var.tags
}
