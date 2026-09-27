# Upgrading from 0.1.0 to 1.0.0

## What changed and why

Version 1.0.0 is a hardening-and-standards uplift that **preserves the accepted design** ([docs/DESIGN.md](DESIGN.md)). Its inputs, outputs, resource addresses and every rendered resource argument and policy document are unchanged. You upgrade by changing the `ref` of the module source and nothing else.

What is different is around the resources: the root is split into one file per concern, the policy documents are rendered by a pure submodule (`modules/policies`) with byte-identical output, the plan-time validation is stricter and more precise, each provider is checked against the Region the module is told about, four advisory checks warn about valid-but-unintended settings, and the module ships tests, examples, documentation and the quality gate.

Two things are verified rather than assumed:

- Every one of the 28 resource blocks of 0.1.0 was compared with its 1.0.0 counterpart. The only differences are the source of the `policy` argument (`local.*` became `module.policies.*`, with identical JSON) and added `lifecycle { precondition }` blocks. No attribute, name, tag or dependency changed.
- The five policy documents (primary key, replica key, primary bucket, replica bucket, replication role) are compared byte for byte with the documents 0.1.0 built, for a non-replicated tier and for replicated `GOVERNANCE` and `COMPLIANCE` tiers, by a golden test in `modules/policies/tests`.

The expected result of the first plan against existing 0.1.0 state is therefore **no changes**. Nothing in `infra/active` of the platform repository consumes this module today, so no live state is known to exist; treat the statement as verified against the source, and confirm it with the plan in step 4 below.

## Input mapping

Root inputs of 0.1.0, all unchanged in name, type, nullability and meaning:

| 0.1.0 input | 1.0.0 equivalent |
| --- | --- |
| `name_prefix` | `name_prefix`, unchanged. |
| `primary_region` | `primary_region`, unchanged. The default `aws` provider must now be bound to it (precondition, see below). |
| `replica_region` | `replica_region`, unchanged. The `aws.replica` provider must now be bound to it when any tier replicates. |
| `access_log_bucket_name` | `access_log_bucket_name`, unchanged. It must not be one of the module's own state or replica buckets. |
| `access_log_prefix` | `access_log_prefix`, unchanged. |
| `state_tiers` | `state_tiers`, unchanged schema (`bucket_name`, `replica_bucket_name`, `noncurrent_version_expiration_in_days`, `abort_incomplete_multipart_upload_after_days`, `object_lock`). Validation is stricter, see below. |
| `state_access_principal_arns` | `state_access_principal_arns`, unchanged. Still at least two role ARNs. |
| `kms_key_deletion_window_in_days` | `kms_key_deletion_window_in_days`, unchanged. |
| `key_administrator_arns` | `key_administrator_arns`, unchanged. |
| `tags` | `tags`, unchanged. Tag keys are now validated (1-128 characters, no `aws:` prefix). |

Outputs of 0.1.0, unchanged in name and shape:

| 0.1.0 output | 1.0.0 equivalent |
| --- | --- |
| `backend_configuration` | `backend_configuration`, unchanged: per tier `bucket`, `kms_key_id`, `dynamodb_table`, `use_lockfile`, `replica_bucket`, `replica_region`, `replica_key_id`. |
| `state_access_policy_arns` | `state_access_policy_arns`, unchanged: per tier `bucket_arn`, `key_arn`, `lock_arn`, `replica_bucket_arn`, `replica_key_arn`. |

Providers: unchanged. The module still declares `configuration_aliases = [aws.replica]` and requires `providers = { aws = aws, aws.replica = aws.replica }`.

A call before and after, for a consumer whose block is `module "state"`; only the `ref` moves:

```hcl
# 0.1.0
module "state" {
  source = "git::https://github.com/hatan4ik/aws.modules.state.git?ref=<v0.1.0 commit>" # v0.1.0
  # ... unchanged inputs and providers ...
}

# 1.0.0
module "state" {
  source = "git::https://github.com/hatan4ik/aws.modules.state.git?ref=<v1.0.0 commit>" # v1.0.0
  # ... unchanged inputs and providers ...
}
```

## Stricter validation (configurations that could not have applied)

These are rejected at plan time in 1.0.0. Each describes an input that 0.1.0 accepted at plan time but that AWS would have rejected at apply time, or that is a misconfiguration the ADRs forbid.

| New rule | Where | Fix |
| --- | --- | --- |
| Bucket names follow the general purpose bucket rules: no adjacent dots, not shaped like an IP address, no `xn--`, `sthree-`, `amzn-s3-demo-` prefix, no `-s3alias`, `--ol-s3`, `.mrap`, `--x-s3`, `--table-s3` suffix. | `var.state_tiers` | Rename the bucket; S3 would have refused it. |
| Bucket names are unique across every tier's `bucket_name` and `replica_bucket_name`. | `var.state_tiers` | Give every bucket its own name. |
| Tag keys are 1-128 characters and do not start with `aws:`. | `var.tags` | Rename the tag; AWS would have refused it. |
| The default provider is bound to `primary_region`; the `aws.replica` provider is bound to `replica_region` (only checked when a tier replicates). | precondition on `aws_kms_key.state`, `aws_kms_replica_key.state` | Configure the providers for the Regions passed to the module. This is ADR 0008's 2026-09-20 requirement; a mis-bound alias would have created replicas in the wrong Region while the outputs named the declared one. |
| The replication role name `<name_prefix>-<tier>-terraform-state-replication` is at most 64 characters. | precondition on `aws_iam_role.state_replication` | Shorten `name_prefix` or the tier name; IAM would have refused it. |
| `access_log_bucket_name` is not one of the module's own buckets. | precondition on `aws_s3_bucket_logging.state` | Point it at the separate central log bucket. |

Advisory checks (warnings only, never block): a key administrator that is also a state access principal; Object Lock retention settings set while Object Lock is disabled; Object Lock retention longer than `noncurrent_version_expiration_in_days`; a `tags` key that the module computes itself (`Name`, `Component`, `EnvironmentTier`, `ReplicaRegion`).

## State addresses

No resource address changed, so no `moved` block is needed or provided. The 28 resource types of 0.1.0 keep their addresses (`aws_kms_key.state["<tier>"]`, `aws_s3_bucket.state["<tier>"]`, `aws_s3_bucket.state_replica["<tier>"]`, `aws_dynamodb_table.state_lock["<tier>"]`, `aws_iam_role.state_replication["<tier>"]`, and so on).

New objects in 1.0.0 and their state impact:

| New object | Kind | State impact |
| --- | --- | --- |
| `module.state.module.policies` | module with no resources | None; it only renders documents. |
| `data.aws_region.primary`, `data.aws_region.replica` | data sources | Read-only, no API call; nothing is created. |

## Procedure

1. Read [docs/DESIGN.md](DESIGN.md) and the ADRs it cites; nothing here authorizes an apply.
2. In your approved bootstrap root, change the module `ref` to the v1.0.0 commit SHA and update the version comment. Change nothing else.
3. `terraform init -upgrade` (only the module source changes; the provider constraint `>= 6.35.0, < 7.0.0` is the same).
4. `terraform plan`. The expected result is **no changes**. Any planned create, update, delete or replacement of a state bucket, key, lock table, role or policy is unexpected: stop and investigate before doing anything else. Warnings from the new advisory checks are expected to be reviewed, not to block.
5. If the plan fails a new validation or precondition, fix the input as described in the table above; do not work around it.
6. Roll back by restoring the previous `ref`; nothing in state changes on upgrade, so rollback is symmetric.

Every stateful resource stays protected by `prevent_destroy`, so an upgrade cannot destroy state infrastructure; a plan that proposes it fails on the guard.
