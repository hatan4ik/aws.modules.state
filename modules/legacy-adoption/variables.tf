variable "bucket_name" {
  description = "Observed S3 bucket name for the one legacy state backend being adopted."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "dynamodb_table_name" {
  description = "Observed DynamoDB lock-table name for the legacy state backend."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,255}$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name must be a valid DynamoDB table name."
  }
}

variable "kms_key_alias" {
  description = "Observed KMS alias used by the legacy state backend."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^alias/[A-Za-z0-9/_-]+$", var.kms_key_alias))
    error_message = "kms_key_alias must be a KMS alias beginning with alias/."
  }
}

variable "kms_key_description" {
  description = "Observed non-secret description of the legacy state KMS key."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.kms_key_description)) > 0
    error_message = "kms_key_description must not be empty."
  }
}

variable "tags" {
  description = "Observed ownership and allocation tags. Resource tags are explicit; the root does not use provider default_tags."
  type        = map(string)
  nullable    = false

  validation {
    condition     = length(var.tags) > 0
    error_message = "tags must contain the approved ownership and allocation tags."
  }
}
