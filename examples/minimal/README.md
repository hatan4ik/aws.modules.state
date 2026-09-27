# Minimal

One tier, no replica, no Object Lock: a primary bucket, a multi-Region KMS key with an alias, and a DynamoDB lock table, all with the module's fixed security controls (private, owner-enforced, versioned, SSE-KMS, TLS-only, role-restricted, access-logged, EventBridge notifications).

Because the module always receives the `aws.replica` provider, a deployment with no replicated tier binds it to the primary provider (`aws.replica = aws`) and repeats `primary_region` as `replica_region`. Nothing is created through it.

**Run it from an approved bootstrap root only.** The state backend must never use the backend it creates (ADR 0008); apply is not part of this example, only `terraform init` and `terraform plan`. Supply the values in a `.tfvars` file (never committed), for example:

```hcl
name_prefix                 = "acme"
primary_region              = "us-east-2"
bucket_name                 = "acme-shared-tfstate-111122223333"
access_log_bucket_name      = "acme-central-access-logs"
access_log_prefix           = "acme/terraform-state"
state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform", "arn:aws:iam::111122223333:role/break-glass"]
key_administrator_arns      = ["arn:aws:iam::111122223333:role/key-admin"]
```

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
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Globally unique name of the state bucket. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM role ARNs that administer the state KMS keys. | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | KMS pending-deletion window for the state keys, 7-30 days. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases and lock tables (3-31 characters, starting with a letter). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | AWS Region of the state bucket, key and lock table. The provider below is configured for it. | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | IAM role ARNs of the CI deployment role(s) and the break-glass role that may use state objects and locks. At least two. | `set(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Allocation and ownership tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret backend values for each tier: bucket, KMS key, lock table, lockfile flag and the replica identifiers (null without a replica). |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Bucket, key and lock-table ARNs per tier, for scoping the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
