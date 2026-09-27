output "backend_configuration" {
  description = "Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica)."
  value       = module.state.backend_configuration
}

output "state_access_policy_arns" {
  description = "Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies."
  value       = module.state.state_access_policy_arns
}

output "backend_blocks" {
  description = "One S3 backend configuration per tier, ready to hand to a workload root's `terraform init -backend-config`: the bucket, the KMS key, the DynamoDB table and the native lockfile flag. Both lock mechanisms are configured during the ADR 0016 transition."
  value = {
    for tier, configuration in module.state.backend_configuration : tier => {
      bucket         = configuration.bucket
      kms_key_id     = configuration.kms_key_id
      dynamodb_table = configuration.dynamodb_table
      use_lockfile   = configuration.use_lockfile
    }
  }
}
