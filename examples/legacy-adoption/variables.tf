variable "region" {
  description = "AWS Region of the observed legacy backend."
  type        = string
}

variable "bucket_name" {
  description = "Observed name of the legacy state bucket."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Observed name of the legacy DynamoDB lock table."
  type        = string
}

variable "kms_key_alias" {
  description = "Observed KMS alias of the legacy state key, beginning with alias/."
  type        = string
}

variable "kms_key_description" {
  description = "Observed description of the legacy state KMS key."
  type        = string
}

variable "tags" {
  description = "Observed ownership and allocation tags of the legacy resources. At least one."
  type        = map(string)
}
