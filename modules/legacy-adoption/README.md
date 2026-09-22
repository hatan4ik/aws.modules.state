# Legacy state-backend adoption

This internal composition records the observed one-bucket bootstrap selected by
[ADR 0015](../../../../docs/adr/0015-adopt-legacy-state-bootstrap.md). It is
not a general state-backend module and must not be used for a new environment.
Use the [adoption runbook](../../../../docs/runbooks/adopt-legacy-state-backend.md)
to move existing state addresses only after an approved state-change record.

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

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_dynamodb_table.state_lock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_object_lock_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Observed S3 bucket name for the one legacy state backend being adopted. | `string` | n/a | yes |
| <a name="input_dynamodb_table_name"></a> [dynamodb\_table\_name](#input\_dynamodb\_table\_name) | Observed DynamoDB lock-table name for the legacy state backend. | `string` | n/a | yes |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | Observed KMS alias used by the legacy state backend. | `string` | n/a | yes |
| <a name="input_kms_key_description"></a> [kms\_key\_description](#input\_kms\_key\_description) | Observed non-secret description of the legacy state KMS key. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Observed ownership and allocation tags. Resource tags are explicit; the root does not use provider default\_tags. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Compatibility-shaped backend configuration for the one transitional legacy tier. Replica fields are null until the separately approved hardening migration creates them. |
| <a name="output_backend_identity"></a> [backend\_identity](#output\_backend\_identity) | Non-secret identifiers used only by the approved canonical state-migration runbook. |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | Compatibility-shaped ARNs for the transitional legacy tier's future least-privilege policy. |
<!-- END_TF_DOCS -->
