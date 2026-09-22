output "backend_identity" {
  description = "Non-secret identifiers used only by the approved canonical state-migration runbook."
  value = {
    bucket_name         = aws_s3_bucket.state.bucket
    dynamodb_table_name = aws_dynamodb_table.state_lock.name
    kms_key_alias       = aws_kms_alias.state.name
  }
}

output "backend_configuration" {
  description = "Compatibility-shaped backend configuration for the one transitional legacy tier. Replica fields are null until the separately approved hardening migration creates them."
  value = {
    legacy = {
      bucket         = aws_s3_bucket.state.id
      kms_key_id     = aws_kms_key.state.arn
      dynamodb_table = aws_dynamodb_table.state_lock.name
      use_lockfile   = false
      replica_bucket = null
      replica_region = null
      replica_key_id = null
    }
  }
}

output "state_access_policy_arns" {
  description = "Compatibility-shaped ARNs for the transitional legacy tier's future least-privilege policy."
  value = {
    legacy = {
      bucket_arn         = aws_s3_bucket.state.arn
      key_arn            = aws_kms_key.state.arn
      lock_arn           = aws_dynamodb_table.state_lock.arn
      replica_bucket_arn = null
      replica_key_arn    = null
    }
  }
}
