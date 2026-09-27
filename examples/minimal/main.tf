# The smallest deployment: one tier, no replica, no Object Lock. The module always
# receives an aws.replica provider; with no replicated tier nothing is created
# through it, so it is simply bound to the primary provider and replica_region
# repeats primary_region.

provider "aws" {
  region = var.primary_region
}

module "state" {
  source = "../../"

  providers = {
    aws         = aws
    aws.replica = aws
  }

  name_prefix            = var.name_prefix
  primary_region         = var.primary_region
  replica_region         = var.primary_region
  access_log_bucket_name = var.access_log_bucket_name
  access_log_prefix      = var.access_log_prefix

  state_tiers = {
    shared = {
      bucket_name                                  = var.bucket_name
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
