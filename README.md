# Internal state-backend composition module

Creates one primary S3 state bucket, multi-Region KMS key, and DynamoDB lock
table for every caller-defined state tier. A tier can opt into a same-tier
replica bucket and replica KMS key in a distinct Region; replication uses an
IAM role scoped to that tier only. Every created bucket is versioned, private,
owner-enforced, TLS-only, lifecycle-managed, resource-policy-restricted to the
approved CI/recovery/replication roles, logged to a pre-existing centralized
access-log bucket, and configured to publish S3 events to EventBridge. Object
Lock is an explicit per-tier decision and is applied consistently to both copies
when replication is enabled.

The S3 backend's native lockfile is also emitted for configuration. DynamoDB locking remains present only because the task requires it; HashiCorp documents it as deprecated, so a later ADR must define the migration/retirement plan. The central access-log bucket is deliberately an input: it must be created and protected by the Log Archive design, not circularly created by this module. This module is bootstrapped from a specially approved local root and must never attempt to use the backend it is creating.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |
| <a name="provider_aws.replica"></a> [aws.replica](#provider\_aws.replica) | 6.65.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_dynamodb_table.state_lock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.state_replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.state_replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_replica_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_replica_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_logging.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_notification.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_notification.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_object_lock_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_replication_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_replication_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.state_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_log_bucket_name"></a> [access\_log\_bucket\_name](#input\_access\_log\_bucket\_name) | Pre-existing approved centralized S3 access-log bucket, normally owned by Log Archive; this module does not create the shared log destination. | `string` | n/a | yes |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Approved non-empty access-log prefix inside the centralized log bucket. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | Approved IAM role ARNs that administer state KMS keys; they must be distinct from routine state use where possible. | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | Approved KMS pending-deletion window for state keys. A key must remain recoverable long enough for the organization's break-glass process. | `number` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases, and lock tables. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Approved AWS Region containing the primary state buckets and KMS multi-Region primary keys. | `string` | n/a | yes |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | Approved, distinct AWS Region containing the state-bucket replicas and KMS replica keys. | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | Only CI deployment roles and the approved break-glass role allowed to read or write state objects and locks. | `set(string)` | n/a | yes |
| <a name="input_state_tiers"></a> [state\_tiers](#input\_state\_tiers) | One or more isolated state tier configurations. Cross-Region replication is optional per tier; Object Lock is optional only when a retention decision explicitly disables it. | <pre>map(object({<br/>    bucket_name                                  = string<br/>    replica_bucket_name                          = optional(string)<br/>    noncurrent_version_expiration_in_days        = number<br/>    abort_incomplete_multipart_upload_after_days = number<br/>    object_lock = object({<br/>      enabled        = bool<br/>      retention_mode = optional(string)<br/>      retention_days = optional(number)<br/>    })<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional required allocation and ownership tags. Name and Component tags are computed by the module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret S3 backend values for each environment tier. Configure both S3 lockfile and DynamoDB during the documented locking migration period. |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | State bucket and KMS ARNs to scope the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
