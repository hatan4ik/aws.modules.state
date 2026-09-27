# HISTORICAL, plan-only. ADR 0015 (adopt the legacy state bootstrap) is closed and
# its adoption was completed; this example exists to keep the adoption composition
# valid while modules/legacy-adoption remains in the module (a v2 removal
# candidate). It is not a procedure and not a template for a new backend: a new
# backend uses the root module, see ../minimal.

provider "aws" {
  region = var.region
}

module "legacy" {
  source = "../../modules/legacy-adoption"

  bucket_name         = var.bucket_name
  dynamodb_table_name = var.dynamodb_table_name
  kms_key_alias       = var.kms_key_alias
  kms_key_description = var.kms_key_description
  tags                = var.tags
}
