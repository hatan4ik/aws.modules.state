output "key_policies" {
  description = "Primary KMS key policy document by tier: key administration for the administrators, encryption use for the CI and break-glass roles and, on a replicated tier, that tier's replication role."
  value       = local.key_policies

  precondition {
    condition     = length(setsubtract(toset(keys(var.replication_role_arns)), var.tiers)) == 0
    error_message = "replication_role_arns may only name tiers listed in tiers."
  }
}

output "replica_key_policies" {
  description = "KMS replica key policy document by replicated tier, with the same principals as the tier's primary key policy."
  value       = local.replica_key_policies
}

output "bucket_policies" {
  description = "Primary bucket policy document by tier: TLS-only, deny every principal outside the state roles (and the tier's own replication role), allow the state roles to use state and lock objects."
  value       = local.bucket_policies

  precondition {
    condition     = toset(keys(var.bucket_arns)) == var.tiers
    error_message = "bucket_arns must have exactly one entry for every tier in tiers."
  }
}

output "replica_bucket_policies" {
  description = "Replica bucket policy document by replicated tier, with the same deny and allow rules as the primary bucket policy."
  value       = local.replica_bucket_policies

  precondition {
    condition     = toset(keys(var.replica_bucket_arns)) == toset(keys(var.replication_role_arns))
    error_message = "replica_bucket_arns must have exactly one entry for every tier in replication_role_arns."
  }
}

output "replication_policies" {
  description = "Replication role inline policy document by replicated tier: read only that tier's source bucket, write only its replica bucket, use only its two keys."
  value       = local.replication_policies

  precondition {
    condition = (
      toset(keys(var.key_arns)) == var.tiers &&
      toset(keys(var.replica_key_arns)) == toset(keys(var.replication_role_arns)) &&
      toset(keys(var.replica_bucket_arns)) == toset(keys(var.replication_role_arns)) &&
      toset(keys(var.bucket_arns)) == var.tiers
    )
    error_message = "key_arns and bucket_arns need one entry for every tier in tiers, and replica_key_arns and replica_bucket_arns one entry for every tier in replication_role_arns."
  }
}
