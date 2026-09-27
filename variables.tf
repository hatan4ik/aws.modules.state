variable "name_prefix" {
  description = "Approved lowercase prefix for state buckets, keys, aliases, and lock tables."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix must be 3-31 lowercase letters, digits, and hyphens and start with a letter."
  }
}

variable "primary_region" {
  description = "Approved AWS Region containing the primary state buckets and KMS multi-Region primary keys. The default aws provider must be configured for this Region; a precondition rejects a mismatch."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a valid AWS Region identifier."
  }
}

variable "replica_region" {
  description = "Approved, distinct AWS Region containing the state-bucket replicas and KMS replica keys. The aws.replica provider must be configured for this Region; a precondition rejects a mismatch. Required even when no tier replicates, because the aws.replica provider is always passed."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.replica_region))
    error_message = "replica_region must be a valid AWS Region identifier."
  }
}

variable "access_log_bucket_name" {
  description = "Pre-existing approved centralized S3 access-log bucket, normally owned by Log Archive; this module does not create the shared log destination. It must not be one of the state or replica buckets."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be a valid S3 bucket name."
  }
}

variable "access_log_prefix" {
  description = "Approved non-empty access-log prefix inside the centralized log bucket. Logs land under <prefix>/primary/<tier>/ and <prefix>/replica/<tier>/."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.access_log_prefix)) > 0
    error_message = "access_log_prefix must not be empty."
  }
}

variable "state_tiers" {
  description = <<-EOT
    One or more isolated state tier configurations, keyed by a lowercase tier name.
    Every tier gets a primary bucket, a multi-Region KMS key and a lock table.
    - bucket_name: globally unique primary bucket name.
    - replica_bucket_name: optional; naming a replica bucket opts the tier into cross-Region replication (replica bucket, replica key, tier-scoped replication role).
    - noncurrent_version_expiration_in_days, abort_incomplete_multipart_upload_after_days: positive whole numbers for the lifecycle rule on every bucket of the tier.
    - object_lock: an explicit per-tier decision applied to both copies. When enabled, retention_mode (COMPLIANCE or GOVERNANCE) and retention_days set the default retention. Object Lock can only be enabled when a bucket is created.
  EOT
  type = map(object({
    bucket_name                                  = string
    replica_bucket_name                          = optional(string)
    noncurrent_version_expiration_in_days        = number
    abort_incomplete_multipart_upload_after_days = number
    object_lock = object({
      enabled        = bool
      retention_mode = optional(string)
      retention_days = optional(number)
    })
  }))
  nullable = false

  validation {
    condition     = length(var.state_tiers) > 0 && alltrue([for tier in keys(var.state_tiers) : can(regex("^[a-z][a-z0-9-]{1,30}$", tier))])
    error_message = "state_tiers must contain one or more lowercase, hyphenated tier names of 2-31 characters that start with a letter."
  }

  validation {
    condition = alltrue([
      for name in concat(
        [for tier in values(var.state_tiers) : tier.bucket_name],
        [for tier in values(var.state_tiers) : tier.replica_bucket_name if tier.replica_bucket_name != null],
      ) :
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", name)) && !can(regex("[.][.]", name)) && !can(regex("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", name))
    ])
    error_message = "Every bucket_name and replica_bucket_name must be 3-63 lowercase letters, digits, dots, or hyphens, start and end with a letter or digit, contain no two adjacent dots, and not be formatted like an IP address."
  }

  validation {
    condition = alltrue([
      for name in concat(
        [for tier in values(var.state_tiers) : tier.bucket_name],
        [for tier in values(var.state_tiers) : tier.replica_bucket_name if tier.replica_bucket_name != null],
      ) :
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", name)) && !can(regex("(-s3alias|--ol-s3|[.]mrap|--x-s3|--table-s3)$", name))
    ])
    error_message = "Bucket names must not start with the reserved prefixes xn--, sthree-, or amzn-s3-demo-, or end with the reserved suffixes -s3alias, --ol-s3, .mrap, --x-s3, or --table-s3."
  }

  validation {
    condition     = alltrue([for tier in values(var.state_tiers) : tier.replica_bucket_name == null ? true : tier.replica_bucket_name != tier.bucket_name])
    error_message = "A tier's replica_bucket_name must differ from its bucket_name."
  }

  validation {
    condition = length(concat(
      [for tier in values(var.state_tiers) : tier.bucket_name],
      [for tier in values(var.state_tiers) : tier.replica_bucket_name if tier.replica_bucket_name != null],
      )) == length(distinct(concat(
        [for tier in values(var.state_tiers) : tier.bucket_name],
        [for tier in values(var.state_tiers) : tier.replica_bucket_name if tier.replica_bucket_name != null],
    )))
    error_message = "Bucket names must be unique across every tier: no two tiers may share a bucket_name or replica_bucket_name, and no replica may reuse another tier's bucket."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      tier.noncurrent_version_expiration_in_days > 0 && floor(tier.noncurrent_version_expiration_in_days) == tier.noncurrent_version_expiration_in_days
    ])
    error_message = "noncurrent_version_expiration_in_days must be a positive whole number for every tier."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      tier.abort_incomplete_multipart_upload_after_days > 0 && floor(tier.abort_incomplete_multipart_upload_after_days) == tier.abort_incomplete_multipart_upload_after_days
    ])
    error_message = "abort_incomplete_multipart_upload_after_days must be a positive whole number for every tier."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      !tier.object_lock.enabled || contains(["COMPLIANCE", "GOVERNANCE"], tier.object_lock.retention_mode == null ? "UNSET" : tier.object_lock.retention_mode)
    ])
    error_message = "An Object Lock-enabled tier needs retention_mode COMPLIANCE or GOVERNANCE."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      !tier.object_lock.enabled || try(tier.object_lock.retention_days > 0 && floor(tier.object_lock.retention_days) == tier.object_lock.retention_days, false)
    ])
    error_message = "An Object Lock-enabled tier needs a positive whole-number retention_days."
  }
}

variable "state_access_principal_arns" {
  description = "Only CI deployment roles and the approved break-glass role allowed to read or write state objects and locks. At least two IAM role ARNs: the CI role and the break-glass role."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.state_access_principal_arns) >= 2
    error_message = "state_access_principal_arns must contain at least the CI and break-glass IAM role ARNs."
  }

  validation {
    condition     = alltrue([for principal in var.state_access_principal_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "state_access_principal_arns must contain only IAM role ARNs of the form arn:<partition>:iam::<account>:role/<name>."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = "Approved KMS pending-deletion window for state keys. A key must remain recoverable long enough for the organization's break-glass process."
  type        = number
  nullable    = false

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30 && floor(var.kms_key_deletion_window_in_days) == var.kms_key_deletion_window_in_days
    error_message = "kms_key_deletion_window_in_days must be a whole number from 7 through 30."
  }
}

variable "key_administrator_arns" {
  description = "Approved IAM role ARNs that administer state KMS keys; they must be distinct from routine state use where possible (a check warns on overlap)."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.key_administrator_arns) >= 1
    error_message = "key_administrator_arns must contain one or more IAM role ARNs."
  }

  validation {
    condition     = alltrue([for principal in var.key_administrator_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "key_administrator_arns must contain only IAM role ARNs of the form arn:<partition>:iam::<account>:role/<name>."
  }
}

variable "tags" {
  description = "Additional required allocation and ownership tags. Name, Component, EnvironmentTier and ReplicaRegion tags are computed by the module and win over the same keys here (a check warns)."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) >= 1 && length(key) <= 128 && !startswith(lower(key), "aws:")])
    error_message = "Tag keys must be 1-128 characters and must not start with the reserved prefix aws:."
  }
}
