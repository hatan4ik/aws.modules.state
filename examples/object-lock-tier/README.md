# Object Lock tier

A replicated tier whose primary and replica buckets both have Object Lock with a default retention. Object Lock is an explicit per-tier decision: it can only be enabled when a bucket is created, requires versioning (always on here), and in `COMPLIANCE` mode cannot be shortened or removed by anyone during the retention period, so choose the mode and days deliberately and record the retention decision first.

Object Lock retention is also a floor for the lifecycle rule: lifecycle cannot delete a locked version, so `noncurrent_version_expiration_in_days` should not be shorter than `retention_days`; the module warns (a `check`) when it is. This example sets it to the larger of the retention and 90 days.

Plan only; run from an approved bootstrap root, never from a root that uses the backend it creates.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_state"></a> [state](#module\_state) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_bucket_name"></a> [access\_log\_bucket\_name](#input\_access\_log\_bucket\_name) | Name of the pre-existing central S3 access-log bucket (owned by Log Archive). The module never creates it; it must allow S3 server access log delivery. | `string` | n/a | yes |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Prefix inside the central access-log bucket under which the state buckets' logs are written. | `string` | n/a | yes |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Globally unique name of the primary state bucket. Object Lock can only be enabled when a bucket is created. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM role ARNs that administer the state KMS keys. | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | KMS pending-deletion window for the state keys, 7-30 days. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases and lock tables (3-31 characters, starting with a letter). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | AWS Region of the primary bucket and multi-Region KMS primary key. The default provider is configured for it. | `string` | n/a | yes |
| <a name="input_replica_bucket_name"></a> [replica\_bucket\_name](#input\_replica\_bucket\_name) | Globally unique name of the replica bucket; it is created with Object Lock enabled as well. | `string` | n/a | yes |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | AWS Region of the replica bucket and KMS replica key; must differ from primary\_region. The aws.replica provider is configured for it. | `string` | n/a | yes |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Default Object Lock retention in whole days. Also the minimum time noncurrent state versions survive, whatever noncurrent\_version\_expiration\_in\_days says. | `number` | n/a | yes |
| <a name="input_retention_mode"></a> [retention\_mode](#input\_retention\_mode) | Default Object Lock retention mode: GOVERNANCE (privileged users may override) or COMPLIANCE (nobody, including the root user, may shorten or remove it). | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | IAM role ARNs of the CI deployment role(s) and the break-glass role that may use state objects and locks. At least two. | `set(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Allocation and ownership tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica). |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
