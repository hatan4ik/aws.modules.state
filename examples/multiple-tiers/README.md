# Multiple tiers

Three isolated tiers in one module call: `dev` (no replica, no Object Lock), `staging` (replica, Object Lock `GOVERNANCE`) and `prod` (replica, Object Lock `COMPLIANCE`). The map key is the tier; each tier gets its own bucket, KMS key, lock table and, where it opts in, replica bucket, replica key and replication role. A tier's replication role appears only in that tier's key, bucket and replication documents.

The `backend_blocks` output shows how a workload root consumes the result: both the S3 native lockfile (`use_lockfile`) and the DynamoDB lock table are configured during the transition defined by ADR 0016; the lock table is not retired by this module.

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
| <a name="input_bucket_names"></a> [bucket\_names](#input\_bucket\_names) | Globally unique bucket names per tier. The keys must be dev, staging and prod; the module rejects a name used twice. | <pre>object({<br/>    dev             = string<br/>    staging         = string<br/>    staging_replica = string<br/>    prod            = string<br/>    prod_replica    = string<br/>  })</pre> | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM role ARNs that administer the state KMS keys. | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | KMS pending-deletion window for the state keys, 7-30 days. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases and lock tables (3-31 characters, starting with a letter). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | AWS Region of the primary buckets and multi-Region KMS primary keys. The default provider is configured for it. | `string` | n/a | yes |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | AWS Region of the replica buckets and KMS replica keys; must differ from primary\_region. The aws.replica provider is configured for it. | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | IAM role ARNs of the CI deployment role(s) and the break-glass role that may use state objects and locks. At least two. | `set(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Allocation and ownership tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_blocks"></a> [backend\_blocks](#output\_backend\_blocks) | One S3 backend configuration per tier, ready to hand to a workload root's `terraform init -backend-config`: the bucket, the KMS key, the DynamoDB table and the native lockfile flag. Both lock mechanisms are configured during the ADR 0016 transition. |
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica). |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
