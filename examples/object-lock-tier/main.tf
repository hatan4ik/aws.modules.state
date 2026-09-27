# A replicated tier with Object Lock. The decision is explicit per tier and is
# applied to both copies: the primary and the replica bucket are created with
# Object Lock enabled and the same default retention.
#
# noncurrent_version_expiration_in_days is deliberately not shorter than the
# retention: lifecycle cannot remove a locked version, and a check warns when the
# retention outlives the expiry.

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
      noncurrent_version_expiration_in_days        = max(var.retention_days, 90)
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = var.retention_mode
        retention_days = var.retention_days
      }
    }
  }

  state_access_principal_arns     = var.state_access_principal_arns
  key_administrator_arns          = var.key_administrator_arns
  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days
  tags                            = var.tags
}
