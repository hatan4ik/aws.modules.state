# Replicated tier

A tier that replicates to a second Region. Naming `replica_bucket_name` is the whole opt-in: the module adds a replica bucket, a KMS replica key and alias in the replica Region through the `aws.replica` provider alias, and an IAM replication role scoped to this tier (assumable only by S3; it reads only this tier's source bucket, writes only its replica bucket, and uses only its two keys). Delete markers and SSE-KMS objects replicate; the replica bucket has the same controls as the primary.

The two providers must be bound to `primary_region` and `replica_region`; a plan-time precondition rejects a mismatch (ADR 0008's provider-alias requirement). The Regions must differ.

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
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Globally unique name of the primary state bucket. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM role ARNs that administer the state KMS keys. | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | KMS pending-deletion window for the state keys, 7-30 days. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases and lock tables (3-31 characters, starting with a letter). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | AWS Region of the primary bucket and multi-Region KMS primary key. The default provider is configured for it. | `string` | n/a | yes |
| <a name="input_replica_bucket_name"></a> [replica\_bucket\_name](#input\_replica\_bucket\_name) | Globally unique name of the replica bucket in the replica Region; must differ from bucket\_name. | `string` | n/a | yes |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | AWS Region of the replica bucket and KMS replica key; must differ from primary\_region. The aws.replica provider is configured for it. | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | IAM role ARNs of the CI deployment role(s) and the break-glass role that may use state objects and locks. At least two. | `set(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Allocation and ownership tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica). |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
