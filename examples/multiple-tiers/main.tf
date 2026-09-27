# Several isolated tiers in one call: the map key is the tier, and each tier gets
# its own bucket, KMS key, lock table and (where it opts in) replica, replication
# role and Object Lock decision. Tiers share nothing but the module's inputs, so
# a tier's replication role never appears in another tier's documents.
#
#   dev      no replica, no Object Lock: fast and cheap, no cross-Region copy.
#   staging  replica, Object Lock in GOVERNANCE mode (privileged override allowed).
#   prod     replica, Object Lock in COMPLIANCE mode (no override).

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
    dev = {
      bucket_name                                  = var.bucket_names.dev
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled = false
      }
    }
    staging = {
      bucket_name                                  = var.bucket_names.staging
      replica_bucket_name                          = var.bucket_names.staging_replica
      noncurrent_version_expiration_in_days        = 60
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "GOVERNANCE"
        retention_days = 30
      }
    }
    prod = {
      bucket_name                                  = var.bucket_names.prod
      replica_bucket_name                          = var.bucket_names.prod_replica
      noncurrent_version_expiration_in_days        = 120
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "COMPLIANCE"
        retention_days = 90
      }
    }
  }

  state_access_principal_arns     = var.state_access_principal_arns
  key_administrator_arns          = var.key_administrator_arns
  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days
  tags                            = var.tags
}
