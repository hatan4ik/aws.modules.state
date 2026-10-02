# policies

Renders every policy document of the state backend from ARN strings: the primary and replica KMS key policies, the primary and replica bucket policies, and the replication role's inline policy, each keyed by tier. It creates no resources and declares no provider, so the security-critical documents have a single owner and are asserted with `terraform test` alone, with known ARNs. The root module calls it once for all tiers and attaches each document to its resource.

The documents are byte-identical to the ones v0.1.0 built as root locals, with one reviewed exception: since 1.0.1 a replicated tier's primary key policy also carries a `KeyReplication` statement (`kms:ReplicateKey` for `key_administrator_arns`), without which `aws_kms_replica_key` cannot be created. `tests/policies.tftest.hcl` compares every document byte for byte. A change to any statement is a change to the live policy of a backend that protects state and needs its own review.

## What it renders

| Output | Document | Principals and scope |
| --- | --- | --- |
| `key_policies` | Primary KMS key policy per tier | `KeyAdministration` for `key_administrator_arns`; `StateEncryptionUse` for the CI and break-glass roles and, on a replicated tier, that tier's replication role; on a replicated tier only, `KeyReplication` (`kms:ReplicateKey`) for `key_administrator_arns`. No account-root statement. |
| `replica_key_policies` | KMS replica key policy per replicated tier | The same administrators and principals as the tier's primary key. |
| `bucket_policies` | Primary bucket policy per tier | `DenyInsecureTransport`; `DenyPrincipalsOutsideStateRoles` (`Deny s3:*` unless the caller is a state role or the tier's replication role); allows for the CI and break-glass roles only. |
| `replica_bucket_policies` | Replica bucket policy per replicated tier | The same shape for the replica bucket. |
| `replication_policies` | Replication role inline policy per replicated tier | Reads only the tier's source bucket, writes only its replica bucket, uses only its two keys. |

## Why the inputs are five separate maps

The root feeds the key ARNs back into the replication policies while the key policies read the replication role ARNs. A single object input, or one local holding all the ARNs, would make every output depend on every ARN, so a key's policy would depend on the key it protects. Each document is built from its own local that reads only the variables it renders. Cross-variable consistency (every tier has an entry in each map it needs) is enforced by output preconditions that reference only variables the same output already depends on.

## Usage

```hcl
module "policies" {
  source = "git::https://github.com/hatan4ik/aws.modules.state.git//modules/policies?ref=<commit-sha>" # v1.0.0

  tiers                       = ["prod"]
  state_access_principal_arns = ["arn:aws:iam::111122223333:role/ci-terraform", "arn:aws:iam::111122223333:role/break-glass"]
  key_administrator_arns      = ["arn:aws:iam::111122223333:role/key-admin"]

  bucket_arns = { prod = "arn:aws:s3:::acme-prod-tfstate" }
  key_arns    = { prod = "arn:aws:kms:us-east-2:111122223333:key/mrk-0123456789abcdef0123456789abcdef" }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_arns"></a> [bucket\_arns](#input\_bucket\_arns) | Primary state bucket ARN by tier (arn:<partition>:s3:::<name>). Keys must equal tiers. | `map(string)` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM role ARNs that administer the state KMS keys. Rendered as a sorted list. | `set(string)` | n/a | yes |
| <a name="input_key_arns"></a> [key\_arns](#input\_key\_arns) | Primary KMS key ARN by tier. Keys must equal tiers. Used only by the replication policies, so that a key policy never depends on the key it protects. | `map(string)` | n/a | yes |
| <a name="input_replica_bucket_arns"></a> [replica\_bucket\_arns](#input\_replica\_bucket\_arns) | Replica state bucket ARN by tier. Keys must equal the keys of replication\_role\_arns. | `map(string)` | `{}` | no |
| <a name="input_replica_key_arns"></a> [replica\_key\_arns](#input\_replica\_key\_arns) | KMS replica key ARN by tier. Keys must equal the keys of replication\_role\_arns. Used only by the replication policies. | `map(string)` | `{}` | no |
| <a name="input_replication_role_arns"></a> [replication\_role\_arns](#input\_replication\_role\_arns) | Replication role ARN by tier, only for tiers that replicate. The keys select which tiers get replica documents and add the tier's role to that tier's key and bucket policies. | `map(string)` | `{}` | no |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | IAM role ARNs of the CI deployment roles and the break-glass role allowed to use state objects, locks and keys. Rendered as a sorted list. | `set(string)` | n/a | yes |
| <a name="input_tiers"></a> [tiers](#input\_tiers) | Names of every state tier to render a primary key policy and a primary bucket policy for. | `set(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_policies"></a> [bucket\_policies](#output\_bucket\_policies) | Primary bucket policy document by tier: TLS-only, deny every principal outside the state roles (and the tier's own replication role), allow the state roles to use state and lock objects. |
| <a name="output_key_policies"></a> [key\_policies](#output\_key\_policies) | Primary KMS key policy document by tier: key administration for the administrators, encryption use for the CI and break-glass roles and, on a replicated tier, that tier's replication role. |
| <a name="output_replica_bucket_policies"></a> [replica\_bucket\_policies](#output\_replica\_bucket\_policies) | Replica bucket policy document by replicated tier, with the same deny and allow rules as the primary bucket policy. |
| <a name="output_replica_key_policies"></a> [replica\_key\_policies](#output\_replica\_key\_policies) | KMS replica key policy document by replicated tier, with the same principals as the tier's primary key policy. |
| <a name="output_replication_policies"></a> [replication\_policies](#output\_replication\_policies) | Replication role inline policy document by replicated tier: read only that tier's source bucket, write only its replica bucket, use only its two keys. |
<!-- END_TF_DOCS -->
