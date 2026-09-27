# Integration fixture

Disposable prerequisites for the credential-driven suites in `tests/integration`: a random suffix, a throwaway central access-log bucket that allows S3 server access log delivery, and a throwaway stand-in for the break-glass role. It resolves the IAM role the suite runs as from the caller identity so that role can be named as a state access principal and key administrator. The suite must run as an IAM role (an assumed-role session), because the module accepts role ARNs only.

The fixture is short-lived scaffolding created and destroyed by the suites in your own account. It is not a deployable pattern and is excluded from the Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.break_glass](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_s3_bucket.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_session_context.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_session_context) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every disposable name; a random suffix is appended so concurrent runs never collide. 1-15 lowercase letters, digits and hyphens, starting with a letter, so the suffixed prefix stays a valid module name\_prefix and every derived name stays within its service limits. | `string` | `"state-it"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the disposable resources in addition to the identifying defaults. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_log_bucket_name"></a> [access\_log\_bucket\_name](#output\_access\_log\_bucket\_name) | Name of the throwaway central access-log bucket, which allows S3 server access log delivery for the buckets under test. |
| <a name="output_access_log_prefix"></a> [access\_log\_prefix](#output\_access\_log\_prefix) | Prefix inside the throwaway log bucket for the buckets under test. |
| <a name="output_key_administrator_arns"></a> [key\_administrator\_arns](#output\_key\_administrator\_arns) | The role this suite runs as, which must be able to manage the keys it creates. |
| <a name="output_name_prefix"></a> [name\_prefix](#output\_name\_prefix) | Unique name prefix (the given prefix plus a random suffix) for the module under test. |
| <a name="output_region"></a> [region](#output\_region) | Region the suite runs in, from the environment; used as both the primary and the replica Region because the smoke tier does not replicate. |
| <a name="output_state_access_principal_arns"></a> [state\_access\_principal\_arns](#output\_state\_access\_principal\_arns) | The role this suite runs as and the throwaway stand-in for the break-glass role. |
| <a name="output_state_bucket_name"></a> [state\_bucket\_name](#output\_state\_bucket\_name) | Unique name for the state bucket under test. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags for the resources under test. |
<!-- END_TF_DOCS -->
