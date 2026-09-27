output "backend_identity" {
  description = "Non-secret identifiers of the represented legacy backend: bucket name, lock-table name and KMS alias."
  value       = module.legacy.backend_identity
}

output "backend_configuration" {
  description = "Compatibility-shaped backend configuration for the single legacy tier: DynamoDB locking only, no replica."
  value       = module.legacy.backend_configuration
}

output "state_access_policy_arns" {
  description = "Compatibility-shaped ARNs of the legacy tier's bucket, key and lock table."
  value       = module.legacy.state_access_policy_arns
}
