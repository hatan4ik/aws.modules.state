variable "tiers" {
  description = "Names of every state tier to render a primary key policy and a primary bucket policy for."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.tiers) > 0 && alltrue([for tier in var.tiers : can(regex("^[a-z][a-z0-9-]{1,30}$", tier))])
    error_message = "tiers must contain one or more lowercase, hyphenated tier names of 2-31 characters that start with a letter."
  }
}

variable "state_access_principal_arns" {
  description = "IAM role ARNs of the CI deployment roles and the break-glass role allowed to use state objects, locks and keys. Rendered as a sorted list."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.state_access_principal_arns) > 0 && alltrue([for principal in var.state_access_principal_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "state_access_principal_arns must contain one or more IAM role ARNs."
  }
}

variable "key_administrator_arns" {
  description = "IAM role ARNs that administer the state KMS keys. Rendered as a sorted list."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.key_administrator_arns) > 0 && alltrue([for principal in var.key_administrator_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", principal))])
    error_message = "key_administrator_arns must contain one or more IAM role ARNs."
  }
}

variable "bucket_arns" {
  description = "Primary state bucket ARN by tier (arn:<partition>:s3:::<name>). Keys must equal tiers."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for arn in values(var.bucket_arns) : can(regex("^arn:[^:]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", arn))])
    error_message = "bucket_arns values must be S3 bucket ARNs of the form arn:<partition>:s3:::<bucket-name>."
  }
}

variable "key_arns" {
  description = "Primary KMS key ARN by tier. Keys must equal tiers. Used only by the replication policies, so that a key policy never depends on the key it protects."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for arn in values(var.key_arns) : can(regex("^arn:[^:]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", arn))])
    error_message = "key_arns values must be KMS key ARNs of the form arn:<partition>:kms:<region>:<account>:key/<key-id>."
  }
}

variable "replication_role_arns" {
  description = "Replication role ARN by tier, only for tiers that replicate. The keys select which tiers get replica documents and add the tier's role to that tier's key and bucket policies."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for arn in values(var.replication_role_arns) : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", arn))])
    error_message = "replication_role_arns values must be IAM role ARNs."
  }
}

variable "replica_bucket_arns" {
  description = "Replica state bucket ARN by tier. Keys must equal the keys of replication_role_arns."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for arn in values(var.replica_bucket_arns) : can(regex("^arn:[^:]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", arn))])
    error_message = "replica_bucket_arns values must be S3 bucket ARNs of the form arn:<partition>:s3:::<bucket-name>."
  }
}

variable "replica_key_arns" {
  description = "KMS replica key ARN by tier. Keys must equal the keys of replication_role_arns. Used only by the replication policies."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for arn in values(var.replica_key_arns) : can(regex("^arn:[^:]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", arn))])
    error_message = "replica_key_arns values must be KMS key ARNs of the form arn:<partition>:kms:<region>:<account>:key/<key-id>."
  }
}
