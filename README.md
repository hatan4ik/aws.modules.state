# aws.modules.state

The Terraform-state-backend composition module. For every caller-defined state **tier** it creates a primary S3 state bucket, a multi-Region KMS key and a DynamoDB lock table; a tier can opt into a same-tier replica bucket and replica KMS key in a second Region (through the `aws.replica` provider alias) with an IAM replication role scoped to that tier alone. Every bucket is versioned, private, owner-enforced, TLS-only, lifecycle-managed, restricted by resource policy to the approved CI, break-glass and replication roles, access-logged to a **pre-existing** central log bucket, and publishes S3 events to EventBridge. Object Lock is an explicit per-tier decision applied to both copies. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

> **Bootstrap warning.** This module is applied from a specially approved bootstrap root and **must never use the backend it creates**. A root whose `backend "s3"` points at a bucket, key or lock table created by this module has a circular dependency: it cannot be created without the state it would store there (ADR 0008). Never add such a backend to the bootstrap root, and never run a workload root against a tier before that tier exists and has been reviewed. Every stateful resource is protected with `prevent_destroy`, so a mistake here cannot be undone by `terraform destroy` either. See [Bootstrapping](#bootstrapping).

## Why this module

What every tier gets, without setting anything else:

- **Private, owner-enforced, versioned buckets.** All four public access block settings on, `BucketOwnerEnforced` ownership (ACLs disabled), versioning `Enabled`. None of it is an input: a state bucket has no other valid shape.
- **SSE-KMS under the tier's own multi-Region key**, with an S3 Bucket Key. The key rotates, has a declared deletion window, and its policy has no account-root statement: only the named key administrators can manage it and only the CI, break-glass and (when replicated) the tier's replication role can use it.
- **A TLS-only, role-restricted bucket policy.** `DenyInsecureTransport` on the bucket and its objects, a `Deny s3:*` for every principal outside the CI and break-glass roles (and the tier's own replication role), and allow statements only for the CI and break-glass roles.
- **A DynamoDB lock table** (on-demand, `LockID`, SSE with the tier's key, point-in-time recovery) **and the S3 native lockfile flag** in the same output, for the ADR 0016 transition. The lock table is kept because the platform requires it and is not retired by this module.
- **Lifecycle, logging and events.** A per-tier lifecycle rule for noncurrent versions and incomplete multipart uploads; server access logging to the central log bucket under `<prefix>/primary/<tier>/`; S3 events published to EventBridge.
- **Explicit Object Lock per tier**, `COMPLIANCE` or `GOVERNANCE` with a retention in days, applied to the primary and, when replicated, the replica.
- **Optional, tier-scoped replication.** Naming `replica_bucket_name` adds a replica bucket with the same controls, a KMS replica key and alias in the replica Region, and a replication role that reads only this tier's source bucket, writes only its replica bucket and uses only its two keys. A tier without one has no replica resource at all.
- **Protected from destruction.** Every bucket, key and lock table keeps `prevent_destroy` (ADR 0008); a static check guards it because `terraform test` cannot see lifecycle settings.
- **Plan-time validation.** Bucket naming rules and uniqueness across every tier and replica, whole-number lifecycle periods, Object Lock rules, role ARNs, the replica Region distinct from the primary, each provider bound to the Region the module is told about, the replication role name within IAM's 64-character limit, and an access-log bucket that is not one of the state buckets. Four advisory `check` blocks warn about valid-but-unintended settings.

## Quick start

```hcl
provider "aws" {
  region = "us-east-2"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

module "state" {
  source = "git::https://github.com/hatan4ik/aws.modules.state.git?ref=<commit-sha>" # v1.0.0

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  name_prefix            = "acme"
  primary_region         = "us-east-2"
  replica_region         = "us-west-2"
  access_log_bucket_name = "acme-central-access-logs" # pre-existing, owned by Log Archive
  access_log_prefix      = "acme/terraform-state"

  state_tiers = {
    dev = {
      bucket_name                                  = "acme-dev-tfstate-111122223333"
      noncurrent_version_expiration_in_days        = 30
      abort_incomplete_multipart_upload_after_days = 7
      object_lock                                  = { enabled = false }
    }
    prod = {
      bucket_name                                  = "acme-prod-tfstate-111122223333"
      replica_bucket_name                          = "acme-prod-tfstate-replica-111122223333"
      noncurrent_version_expiration_in_days        = 120
      abort_incomplete_multipart_upload_after_days = 7
      object_lock = {
        enabled        = true
        retention_mode = "COMPLIANCE"
        retention_days = 90
      }
    }
  }

  state_access_principal_arns = [
    "arn:aws:iam::111122223333:role/ci-terraform",
    "arn:aws:iam::111122223333:role/break-glass",
  ]
  key_administrator_arns          = ["arn:aws:iam::111122223333:role/key-admin"]
  kms_key_deletion_window_in_days = 30
}
```

This creates, for `dev`, a bucket, a KMS key with an alias and a lock table; for `prod`, the same plus a replica bucket and KMS replica key in `us-west-2` and a replication role of its own. `module.state.backend_configuration` then holds, per tier, the bucket, KMS key ARN, lock table name, `use_lockfile = true` and the replica identifiers (`null` for `dev`).

The module always receives the `aws.replica` provider. A deployment with no replicated tier binds it to the primary provider (`aws.replica = aws`) and repeats `primary_region` as `replica_region`; see [`examples/minimal`](examples/minimal).

## Bootstrapping

- The module is applied from a **specially approved bootstrap root**, separate from every workload root, through the protected delivery lifecycle. This repository only provides the module; it authorizes no apply.
- **The bootstrap root must not use the backend this module creates.** Where the bootstrap root's own state lives is decided by that root's approval record, not by this module.
- The identity that applies (and later plans) the module must be named in `state_access_principal_arns`: the bucket policy denies every other principal after it is attached. It must also be able to call `kms:PutKeyPolicy` under the key policy, which has no account-root statement, so in practice it is also a key administrator; KMS rejects a key policy that would lock its creator out. The `key_administrators_are_not_routine_state_users` check warns about that overlap; it is expected only for this bootstrap identity.
- `access_log_bucket_name` must already exist and allow S3 server access log delivery; the module never creates it (a state bucket must not log into itself, and a precondition rejects it).
- A workload root then consumes `backend_configuration` for its `backend "s3"` block: `bucket`, `kms_key_id`, `dynamodb_table` and `use_lockfile`, with its own `key` and `region`. During the ADR 0016 transition both lock mechanisms are configured; the lock table is not removed by this module.

## Architecture

```text
root (one call = all tiers)
├── kms.tf              aws_kms_key.state[tier], aws_kms_alias.state[tier]
│                       aws_kms_replica_key.state[tier], aws_kms_alias.state_replica[tier]     replicated tiers only
├── buckets.tf          aws_s3_bucket.state[tier] + public access block, ownership, versioning, SSE-KMS,
│                       lifecycle, Object Lock (if enabled), logging, EventBridge notification, bucket policy
├── replica_buckets.tf  the same set for the replica bucket (aws.replica)                      replicated tiers only
├── replication.tf      aws_iam_role.state_replication[tier] + inline policy,
│                       aws_s3_bucket_replication_configuration.state[tier]                    replicated tiers only
├── locks.tf            aws_dynamodb_table.state_lock[tier]
├── regions.tf          data.aws_region.primary / .replica (provider-Region binding)
├── policies.tf         module "policies" -> modules/policies (pure renderer of every policy document)
├── checks.tf           advisory checks
└── modules/
    ├── policies/         pure: ARNs in, key / bucket / replication policy documents out
    └── legacy-adoption/  ADR 0015 adoption composition (historical, do not use for a new backend)
```

The root creates buckets, keys and roles and hands their ARNs to `modules/policies`, which returns five maps of policy documents keyed by tier; the root attaches each to its resource. The renderer has no resources, so the security-critical documents are tested with known ARNs. They are byte-identical to the documents v0.1.0 built inline, except that a replicated tier's primary key policy also carries the `KeyReplication` statement added in 1.0.1.

### Resources per tier

| Resource | Every tier | Replicated tier only |
| --- | :---: | :---: |
| Primary bucket, public access block, ownership controls, versioning, SSE-KMS, lifecycle, logging, EventBridge notification, bucket policy | yes | |
| Object Lock configuration (default retention) | when `object_lock.enabled` | |
| Multi-Region KMS key and alias, DynamoDB lock table | yes | |
| Replica bucket and the same nine configuration resources, Object Lock configuration when enabled | | yes |
| KMS replica key and alias | | yes |
| Replication IAM role, inline policy, replication configuration | | yes |

## The `state_tiers` schema

`state_tiers` is a map keyed by tier name (2-31 lowercase letters, digits and hyphens, starting with a letter). Every tier is isolated: nothing is shared between tiers except the module's other inputs.

| Field | Type | Required | Meaning |
| --- | --- | :---: | --- |
| `bucket_name` | `string` | yes | Globally unique primary bucket name; general purpose bucket naming rules apply and no name may repeat across tiers. |
| `replica_bucket_name` | `string` | no | Naming a replica bucket opts the tier into cross-Region replication. Must differ from every other bucket name. |
| `noncurrent_version_expiration_in_days` | `number` | yes | Positive whole number; days after which noncurrent versions expire, on every bucket of the tier. |
| `abort_incomplete_multipart_upload_after_days` | `number` | yes | Positive whole number; days after which incomplete multipart uploads are aborted. |
| `object_lock.enabled` | `bool` | yes | Explicit Object Lock decision, applied to both copies. Only settable when a bucket is created. |
| `object_lock.retention_mode` | `string` | when enabled | `COMPLIANCE` or `GOVERNANCE`. |
| `object_lock.retention_days` | `number` | when enabled | Positive whole number of days of default retention. |

Other inputs: `name_prefix`, `primary_region`, `replica_region` (required even without a replicated tier), `access_log_bucket_name`, `access_log_prefix`, `state_access_principal_arns` (at least two role ARNs: CI and break-glass), `key_administrator_arns`, `kms_key_deletion_window_in_days` (7-30) and optional `tags`. The generated reference below has every type and description.

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | One tier, no replica, no Object Lock; the `aws.replica` alias bound to the primary provider. |
| [`examples/replicated-tier`](examples/replicated-tier) | One tier that replicates: replica bucket, KMS replica key and tier-scoped role, with both providers bound to their Regions. |
| [`examples/object-lock-tier`](examples/object-lock-tier) | A replicated tier with Object Lock on both copies, and why the noncurrent expiry must not be shorter than the retention. |
| [`examples/multiple-tiers`](examples/multiple-tiers) | `dev` (no replica), `staging` (replica, `GOVERNANCE`) and `prod` (replica, `COMPLIANCE`) in one call, plus how a workload root consumes the result. |
| [`examples/legacy-adoption`](examples/legacy-adoption) | Historical, plan-only: the ADR 0015 adoption submodule kept valid while it exists. Not a template for a new backend. |

## Security model

- **Buckets.** Public access fully blocked, ownership enforced, versioning on, SSE-KMS with a Bucket Key under the tier's key (the replica bucket under the replica key). None is configurable.
- **Bucket policy** (rendered by `modules/policies`): `DenyInsecureTransport` (`Deny s3:*` for every principal when `aws:SecureTransport` is false), `DenyPrincipalsOutsideStateRoles` (`Deny s3:*` unless `aws:PrincipalArn` is one of the CI and break-glass roles or the tier's own replication role), and two allows for the CI and break-glass roles only: bucket metadata and `s3:DeleteObject`, `s3:GetObject`, `s3:PutObject`. The replica bucket has the same shape.
- **KMS.** A multi-Region key per tier with rotation on; a policy with a `KeyAdministration` statement for `key_administrator_arns` (no data-plane use) and a `StateEncryptionUse` statement for the CI, break-glass and the tier's replication role; on a replicated tier, a `KeyReplication` statement grants `kms:ReplicateKey` to `key_administrator_arns`, because AWS only honours that permission from the primary key's own policy when there is no account-root statement. The identity that applies the module, through both the default and the `aws.replica` provider, must therefore be a key administrator. There is deliberately no account-root statement. Consequence: only the named roles can manage the key, so keep the administrator role healthy; a deleted-and-recreated role does not recover access by itself.
- **Replication role.** One per replicated tier, assumable only by `s3.amazonaws.com`. Its policy reads the tier's source bucket and object versions (including Object Lock metadata), writes only the tier's replica bucket, and uses only the tier's primary key to decrypt and replica key to encrypt. It never appears in another tier's documents.
- **Lock table.** On-demand, SSE with the tier's key, point-in-time recovery.
- **Provider binding.** Preconditions compare each provider's Region with `primary_region` and `replica_region`, so replicas cannot silently land in the wrong Region while the outputs name the declared one.
- **No escape hatches.** No input weakens a control, and there is no `force_destroy`.
- **Protected from destruction.** `prevent_destroy` on every bucket, KMS key and lock table, enforced by a static check in CI.

## Lifecycle notes

- **State protection.** `terraform destroy` fails on every stateful resource by design. Removing a tier means removing `prevent_destroy` in a reviewed change, and a bucket with Object Lock in `COMPLIANCE` mode cannot be emptied until its retention expires.
- **Object Lock** can only be enabled when a bucket is created; changing `object_lock.enabled` for an existing tier forces replacement of the (protected) bucket, which the guard blocks. Decide it up front. Retention is also a floor for noncurrent expiry: lifecycle cannot remove a locked version, and a `check` warns when the retention outlives the expiry.
- **KMS keys** are protected too; the deletion window applies only after an approved removal of the guard.
- **The lock table** stays until ADR 0016 is amended with the retirement evidence; no removal path exists in this module.
- **Failover and failback** are a manual, documented procedure; see [Replication failover and failback](#replication-failover-and-failback).
- **Adding a replica to an existing tier** adds resources (replica bucket, key, role, replication configuration) and replicates new objects only; existing objects are not replicated retroactively by this module. S3 Batch Replication is out of scope.
- **The `Component`, `Name`, `EnvironmentTier` and `ReplicaRegion` tags** are computed by the module and win over the same keys in `tags`; a check warns when a caller sets one.

## Replication failover and failback

This section is an operating procedure, not module behaviour: the module creates the replica and keeps it current, and nothing in it switches Regions automatically. Run it with the break-glass role unless your runbook names another state access principal.

### What the replica is for

- **Replication is one-way and asynchronous.** S3 replicates every new object version and delete marker from the primary bucket to the replica bucket, re-encrypted under the tier's KMS replica key. There is no replication time control, so the replica can lag the primary by seconds to (rarely) longer; there is **no reverse replication**, so nothing written to the replica ever reaches the primary on its own.
- **The lock table is not replicated.** `aws_dynamodb_table.state_lock` exists in the primary Region only. During a primary-Region outage, `use_lockfile` (an S3 lock object next to the state) is the only lock mechanism available.
- **The replica is writable on purpose.** The replica bucket policy's `AllowStateRecoveryBucketMetadata` and `AllowReplicatedStateRecoveryObjects` statements (in `modules/policies`) give the CI and break-glass roles the same bucket-metadata and `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` rights they have on the primary, and the replica key policy gives them the same key use. That "StateRecovery" access exists so that, during a primary-Region outage, those roles can (1) read the last replicated state and (2) keep operating against the replica as a temporary backend, including writing state and the `.tflock` lock object. Outside a declared failover, nothing should write to the replica; the replication role is the only routine writer.

### Failover: primary Region unavailable

1. **Declare it and freeze.** Stop every pipeline for the affected tier. Record the failover start time; failback depends on it.
2. **Check what the replica holds.** For each state key you need, compare the latest replica version (`aws s3api list-object-versions --bucket <replica_bucket> --prefix <key>`) with what you expect. With no replication time control, the newest primary writes may not have arrived; if the replica copy's `serial` is behind the last known apply, treat those changes as lost and plan to reconcile them, do not hand-edit state.
3. **Point the workload root at the replica.** Use the tier's replica outputs and lockfile locking only:

   ```hcl
   terraform {
     backend "s3" {
       bucket       = "<backend_configuration[tier].replica_bucket>"
       region       = "<backend_configuration[tier].replica_region>"
       kms_key_id   = "<backend_configuration[tier].replica_key_id>"
       key          = "<the same key as in the primary>"
       encrypt      = true
       use_lockfile = true
       # no dynamodb_table: the lock table lives in the primary Region
     }
   }
   ```

   Run `terraform init -reconfigure` (not `-migrate-state`: the state is already in the replica bucket, and migration would try to read the unavailable primary). Then `terraform plan` and confirm it reflects the infrastructure you expect before any apply.
4. **Operate minimally.** Every apply now writes a state version that exists **only** in the replica Region. Keep a list of the state keys you wrote; failback needs it.
5. **Do not** apply this module (its own bootstrap root targets the primary Region), promote the replica key with `kms:UpdatePrimaryRegion`, or change the replication configuration during the outage. Promoting the key would diverge from this module's state and is not needed: a multi-Region replica key encrypts and decrypts in its own Region on its own.

### Failback: primary Region restored

There is no reverse replication, so failback is a reviewed, manual copy of the state written during the outage.

1. **Freeze again.** Stop every pipeline for the tier and make sure no `.tflock` object is held in the replica bucket.
2. **Detect split brain.** List object versions in the **primary** bucket for each state key you wrote in step 4 above. If any primary version is newer than the failover start time, someone wrote to both copies: stop and reconcile by hand (compare `lineage` and `serial`, run plans against each), do not overwrite either copy.
3. **Copy the replica's latest state back.** For each key written during the outage, copy the latest replica version over the primary key, in the primary Region, letting the primary bucket's default SSE-KMS encryption apply the tier's primary key:

   ```sh
   aws s3 cp "s3://<replica_bucket>/<key>" "s3://<primary_bucket>/<key>" \
     --source-region <replica_region> --region <primary_region> \
     --sse aws:kms --sse-kms-key-id <backend_configuration[tier].kms_key_id>
   ```

   Verify the copied object's `serial` and `lineage` match the replica's. The copy is itself replicated back to the replica as a new version with the same content, which is expected.
4. **Clear the stale lock-table digest.** With `dynamodb_table` configured, the S3 backend stores an MD5 digest of each state object in the lock table under the item `LockID = "<primary_bucket>/<key>-md5"`. That digest still describes the pre-outage state, and `terraform init`/`plan` will refuse the newer object ("state data in S3 does not have the expected content"). Delete that item for every key you copied back (`aws dynamodb delete-item --table-name <dynamodb_table> --key '{"LockID":{"S":"<primary_bucket>/<key>-md5"}}'`); Terraform writes a fresh digest on the next state write.
5. **Switch back.** Restore the primary `backend "s3"` block (bucket, `kms_key_id`, `dynamodb_table`, `use_lockfile`), run `terraform init -reconfigure` and then `terraform plan`, which must show no changes caused by the switch. Remove any leftover `.tflock` objects from the replica bucket.
6. **Record it.** Note the failover window, the keys copied back and any changes lost to replication lag in the incident record.

The procedure has not been exercised against real AWS for this module; rehearse it on a non-production replicated tier before relying on it.

## Testing

Layered, because `terraform test` in Terraform 1.7 has two limits here: computed ARNs are unknown at plan time, and a mock `apply` fails its own teardown on a `prevent_destroy` resource.

- **Contract tests** (`make test`, run by CI; `mock_provider`, no credentials): `tests/` covers the security posture of every tier variant (replica on and off, Object Lock off, `GOVERNANCE` and `COMPLIANCE`), replication and the replica copy, every variable validation and cross-input precondition with a failing case, the provider-Region binding, every advisory check, and the outputs. `modules/policies/tests` asserts every statement of every policy document with known ARNs, including per-tier role scoping and a byte-for-byte comparison with the documents v0.1.0 built. `modules/legacy-adoption/tests` pins the historical composition.
- **Wiring suite** (`make test-wired`, run by CI): applies the whole root under mock providers with distinct ARNs per instance, in a temporary copy with the destroy guards lifted (`scripts/lift-destroy-guards.sh`), and asserts that each document reaches the right resource. The committed tree is never modified.
- **Destroy guards** (`make guards`, run by CI): `scripts/check-destroy-guards.sh` fails when a bucket, key or lock table loses `prevent_destroy`.
- **Integration suite** (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow): applies one non-replicated tier for real in **your** account with a throwaway access-log bucket and stand-in role, asserts against the real APIs, and destroys everything (also through a guard-lifted temporary copy). See [`tests/integration`](tests/integration).

## Design principles

- **Single responsibility.** One file per concern; `modules/policies` owns the shape of every policy document and creates no resources.
- **Open/closed.** A new tier is a new map entry; a replica is one more attribute. No behaviour requires editing the module.
- **Liskov substitution.** Every tier exposes the same output shape; replica fields are `null` when there is no replica.
- **Interface segregation.** A tier without a replica needs no replica name and receives no replica resource, role or key.
- **Dependency inversion.** The root depends on identifiers (role ARNs, a log bucket name), never on how they were produced; the renderer depends on ARN strings only.

The full rationale, what is preserved from the ADRs, and what is deferred to v2 are in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`, with `configuration_aliases = [aws.replica]`. Because of the alias the module directory cannot be validated standalone (`terraform validate` reports the missing provider configuration); use an example or your own root.
- Upgrading from v0.1.0 is a `ref` change only: inputs, outputs, resource addresses and every rendered argument and policy document are unchanged. See [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md).
- Out of scope and deferred to v2: extra outputs, TLS 1.2 minimum and encryption-enforcing bucket policy statements, lock-table deletion protection, retirement of the lock table (ADR 0016), replacing the provider alias with the provider's per-resource `region`, bring-your-own replica keys, and retiring `modules/legacy-adoption` (ADR 0015 is closed).
- `modules/legacy-adoption` is historical and must not be used for a new backend.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you (ADR 0010):

```hcl
module "state" {
  source = "git::https://github.com/hatan4ik/aws.modules.state.git?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out, and a maintenance release for an older line is cut from that line's commit.

Upgrading from 0.x: read [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md). All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, the destroy-guard constraint, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_aws.replica"></a> [aws.replica](#provider\_aws.replica) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_policies"></a> [policies](#module\_policies) | ./modules/policies | n/a |

## Resources

| Name | Type |
|------|------|
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
| [aws_region.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_bucket_name"></a> [access\_log\_bucket\_name](#input\_access\_log\_bucket\_name) | Pre-existing approved centralized S3 access-log bucket, normally owned by Log Archive; this module does not create the shared log destination. It must not be one of the state or replica buckets. | `string` | n/a | yes |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Approved non-empty access-log prefix inside the centralized log bucket. Logs land under <prefix>/primary/<tier>/ and <prefix>/replica/<tier>/. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | Approved IAM role ARNs that administer state KMS keys; they must be distinct from routine state use where possible (a check warns on overlap). | `set(string)` | n/a | yes |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | Approved KMS pending-deletion window for state keys. A key must remain recoverable long enough for the organization's break-glass process. | `number` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Approved lowercase prefix for state buckets, keys, aliases, and lock tables. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Approved AWS Region containing the primary state buckets and KMS multi-Region primary keys. The default aws provider must be configured for this Region; a precondition rejects a mismatch. | `string` | n/a | yes |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | Approved, distinct AWS Region containing the state-bucket replicas and KMS replica keys. The aws.replica provider must be configured for this Region; a precondition rejects a mismatch. Required even when no tier replicates, because the aws.replica provider is always passed. | `string` | n/a | yes |
| <a name="input_state_access_principal_arns"></a> [state\_access\_principal\_arns](#input\_state\_access\_principal\_arns) | Only CI deployment roles and the approved break-glass role allowed to read or write state objects and locks. At least two IAM role ARNs: the CI role and the break-glass role. | `set(string)` | n/a | yes |
| <a name="input_state_tiers"></a> [state\_tiers](#input\_state\_tiers) | One or more isolated state tier configurations, keyed by a lowercase tier name.<br/>Every tier gets a primary bucket, a multi-Region KMS key and a lock table.<br/>- bucket\_name: globally unique primary bucket name.<br/>- replica\_bucket\_name: optional; naming a replica bucket opts the tier into cross-Region replication (replica bucket, replica key, tier-scoped replication role).<br/>- noncurrent\_version\_expiration\_in\_days, abort\_incomplete\_multipart\_upload\_after\_days: positive whole numbers for the lifecycle rule on every bucket of the tier.<br/>- object\_lock: an explicit per-tier decision applied to both copies. When enabled, retention\_mode (COMPLIANCE or GOVERNANCE) and retention\_days set the default retention. Object Lock can only be enabled when a bucket is created. | <pre>map(object({<br/>    bucket_name                                  = string<br/>    replica_bucket_name                          = optional(string)<br/>    noncurrent_version_expiration_in_days        = number<br/>    abort_incomplete_multipart_upload_after_days = number<br/>    object_lock = object({<br/>      enabled        = bool<br/>      retention_mode = optional(string)<br/>      retention_days = optional(number)<br/>    })<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional required allocation and ownership tags. Name, Component, EnvironmentTier and ReplicaRegion tags are computed by the module and win over the same keys here (a check warns). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_configuration"></a> [backend\_configuration](#output\_backend\_configuration) | Non-secret S3 backend values for each environment tier. Configure both S3 lockfile and DynamoDB during the documented locking migration period. |
| <a name="output_state_access_policy_arns"></a> [state\_access\_policy\_arns](#output\_state\_access\_policy\_arns) | State bucket and KMS ARNs to scope the CI and break-glass identity policies. |
<!-- END_TF_DOCS -->
