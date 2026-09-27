# Legacy adoption (historical, plan-only)

**Historical. Never apply. Not a template for a new backend.** [ADR 0015](https://github.com/hatan4ik/devops-aws-infra/blob/main/docs/adr/0015-adopt-legacy-state-bootstrap.md) is closed: the legacy bootstrap was adopted through a reviewed, state-preserving migration and no reusable adoption procedure remains. `modules/legacy-adoption` stays in the module only because removing it would change its public source paths; it is a v2 removal candidate.

This example wires the submodule with the observed identifiers so that it keeps validating and planning while it exists. Run only `terraform init` and `terraform plan` against an already-adopted state, and only under an approved state-change record. For a new backend use the root module ([`../minimal`](../minimal)).

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
| <a name="module_legacy"></a> [legacy](#module\_legacy) | ../../modules/legacy-adoption | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Observed name of the legacy state bucket. | `string` | n/a | yes |
| <a name="input_dynamodb_table_name"></a> [dynamodb\_table\_name](#input\_dynamodb\_table\_name) | Observed name of the legacy DynamoDB lock table. | `string` | n/a | yes |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | Observed KMS alias of the legacy state key, beginning with alias/. | `string` | n/a | yes |
| <a name="input_kms_key_description"></a> [kms\_key\_description](#input\_kms\_key\_description) | Observed description of the legacy state KMS key. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS Region of the observed legacy backend. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Observed ownership and allocation tags of the legacy resources. At least one. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Compatibility-shaped backend configuration for the single legacy tier: DynamoDB locking only, no replica. |
| <a name="output_backend_identity"></a> [backend\_identity](#output\_backend\_identity) | Non-secret identifiers of the represented legacy backend: bucket name, lock-table name and KMS alias. |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Compatibility-shaped ARNs of the legacy tier's bucket, key and lock table. |
<!-- END_TF_DOCS -->
