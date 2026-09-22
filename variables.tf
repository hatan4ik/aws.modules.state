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
  description = "Approved AWS Region containing the primary state buckets and KMS multi-Region primary keys."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a valid AWS Region identifier."
  }
}

variable "replica_region" {
  description = "Approved, distinct AWS Region containing the state-bucket replicas and KMS replica keys."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.replica_region))
    error_message = "replica_region must be a valid AWS Region identifier."
  }
}

variable "access_log_bucket_name" {
  description = "Pre-existing approved centralized S3 access-log bucket, normally owned by Log Archive; this module does not create the shared log destination."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be a valid S3 bucket name."
  }
}

variable "access_log_prefix" {
  description = "Approved non-empty access-log prefix inside the centralized log bucket."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.access_log_prefix)) > 0
    error_message = "access_log_prefix must not be empty."
  }
}

variable "state_tiers" {
  description = "One or more isolated state tier configurations. Cross-Region replication is optional per tier; Object Lock is optional only when a retention decision explicitly disables it."
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
    error_message = "state_tiers must contain one or more lowercase, hyphenated tier names."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", tier.bucket_name)) && (tier.replica_bucket_name == null || (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", tier.replica_bucket_name)) && tier.bucket_name != tier.replica_bucket_name)) && tier.noncurrent_version_expiration_in_days > 0 && floor(tier.noncurrent_version_expiration_in_days) == tier.noncurrent_version_expiration_in_days && tier.abort_incomplete_multipart_upload_after_days > 0 && floor(tier.abort_incomplete_multipart_upload_after_days) == tier.abort_incomplete_multipart_upload_after_days
    ])
    error_message = "Every tier needs a valid primary bucket, an optional distinct valid replica bucket, and positive whole-number lifecycle periods."
  }

  validation {
    condition = alltrue([
      for tier in values(var.state_tiers) :
      !tier.object_lock.enabled || (
        contains(["COMPLIANCE", "GOVERNANCE"], tier.object_lock.retention_mode == null ? "UNSET" : tier.object_lock.retention_mode) &&
        try(tier.object_lock.retention_days > 0 && floor(tier.object_lock.retention_days) == tier.object_lock.retention_days, false)
      )
    ])
    error_message = "An Object Lock-enabled tier needs COMPLIANCE or GOVERNANCE mode and a positive whole-number retention period."
  }
}

variable "state_access_principal_arns" {
  description = "Only CI deployment roles and the approved break-glass role allowed to read or write state objects and locks."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.state_access_principal_arns) >= 2 && alltrue([for principal in var.state_access_principal_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "state_access_principal_arns must contain at least the CI and break-glass IAM role ARNs."
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
  description = "Approved IAM role ARNs that administer state KMS keys; they must be distinct from routine state use where possible."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.key_administrator_arns) >= 1 && alltrue([for principal in var.key_administrator_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "key_administrator_arns must contain one or more IAM role ARNs."
  }
}

variable "tags" {
  description = "Additional required allocation and ownership tags. Name and Component tags are computed by the module."
  type        = map(string)
  default     = {}
  nullable    = false
}
