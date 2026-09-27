output "backend_configuration" {
  description = "Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica)."
  value       = module.state.backend_configuration
}

output "state_access_policy_arns" {
  description = "Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies."
  value       = module.state.state_access_policy_arns
}
