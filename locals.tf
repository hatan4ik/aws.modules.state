locals {
  # The tiers that opt into cross-Region replication: exactly those that name a
  # replica bucket. Every replica resource, the replication role, and the
  # replica documents are keyed by this map, so a tier without a replica has none.
  replication_tiers = {
    for tier, configuration in var.state_tiers : tier => configuration
    if configuration.replica_bucket_name != null
  }

  # Terraform's S3 backend supports a lockfile; DynamoDB locking stays here during
  # its documented migration period to meet the platform requirement (ADR 0016).
  state_lock_table_names = {
    for tier in keys(var.state_tiers) : tier => "${var.name_prefix}-${tier}-terraform-locks"
  }

  # The base name of a tier's state KMS key: its Name tag, the stem of the
  # replica key's Name tag, and (behind "alias/") the alias in both Regions.
  state_key_names = {
    for tier in keys(var.state_tiers) : tier => "${var.name_prefix}-${tier}-terraform-state"
  }

  # A replicated tier's replication role name, used for the role, its Name tag,
  # its inline policy and the 64-character precondition that guards it.
  replication_role_names = {
    for tier in keys(local.replication_tiers) : tier => "${var.name_prefix}-${tier}-terraform-state-replication"
  }

  # Every bucket this module creates, primary and replica, for the uniqueness and
  # access-log-target rules.
  state_bucket_names = concat(
    [for configuration in values(var.state_tiers) : configuration.bucket_name],
    [for configuration in values(local.replication_tiers) : configuration.replica_bucket_name],
  )

  common_tags = merge(var.tags, {
    Component = "terraform-state"
  })

  # Tags the module computes itself; a caller tag with the same key is overwritten.
  module_owned_tag_keys = ["Component", "EnvironmentTier", "Name", "ReplicaRegion"]

  # Tiers whose retention settings are set but ignored because Object Lock is off.
  object_lock_ignored_tiers = sort([
    for tier, configuration in var.state_tiers : tier
    if !configuration.object_lock.enabled && (configuration.object_lock.retention_mode != null || configuration.object_lock.retention_days != null)
  ])

  # Tiers whose default retention is longer than the noncurrent-version expiry.
  object_lock_retention_outlives_expiration_tiers = sort([
    for tier, configuration in var.state_tiers : tier
    if configuration.object_lock.enabled && try(configuration.object_lock.retention_days > configuration.noncurrent_version_expiration_in_days, false)
  ])
}
