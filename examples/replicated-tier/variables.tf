variable "primary_region" {
  description = "AWS Region of the primary bucket and multi-Region KMS primary key. The default provider is configured for it."
  type        = string
}

variable "replica_region" {
  description = "AWS Region of the replica bucket and KMS replica key; must differ from primary_region. The aws.replica provider is configured for it."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name of the primary state bucket."
  type        = string
}

variable "replica_bucket_name" {
  description = "Globally unique name of the replica bucket in the replica Region; must differ from bucket_name."
  type        = string
}

variable "name_prefix" {
  description = "Approved lowercase prefix for state buckets, keys, aliases and lock tables (3-31 characters, starting with a letter)."
  type        = string
}

variable "access_log_bucket_name" {
  description = "Name of the pre-existing central S3 access-log bucket (owned by Log Archive). The module never creates it; it must allow S3 server access log delivery."
  type        = string
}

variable "access_log_prefix" {
  description = "Prefix inside the central access-log bucket under which the state buckets' logs are written."
  type        = string
}

variable "state_access_principal_arns" {
  description = "IAM role ARNs of the CI deployment role(s) and the break-glass role that may use state objects and locks. At least two."
  type        = set(string)
}

variable "key_administrator_arns" {
  description = "IAM role ARNs that administer the state KMS keys."
  type        = set(string)
}

variable "kms_key_deletion_window_in_days" {
  description = "KMS pending-deletion window for the state keys, 7-30 days."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Allocation and ownership tags applied to every resource."
  type        = map(string)
  default     = {}
}
