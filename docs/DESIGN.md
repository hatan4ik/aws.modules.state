# Design: aws.modules.state v1

Status: accepted 2026-09-27. A hardening-and-standards uplift of v0.1.0 that
**preserves** the accepted design. It is not a redesign: every input, output,
validation contract and resource address of v0.1.0 keeps its meaning, so a
consumer upgrades by changing the `ref` and nothing else.

## Purpose

`aws.modules.state` is the Terraform-state-backend composition module. For every
caller-defined state **tier** (a key of `state_tiers`) it creates:

- one primary S3 state bucket in the primary Region;
- one multi-Region KMS key with rotation, and an alias;
- one DynamoDB lock table encrypted with that key.

A tier may opt into a same-tier **replica**: a replica bucket and a KMS replica
key in a second Region (through the `aws.replica` provider alias), with an IAM
replication role scoped to that tier alone. Every bucket is versioned, private,
owner-enforced, TLS-only, lifecycle-managed, restricted by a resource policy to
the approved CI, break-glass and replication roles, access-logged to a
**pre-existing** central log bucket, and publishes S3 events to EventBridge.
Object Lock is an explicit per-tier decision applied to both copies.

The module is bootstrapped from a specially approved local root and must never
use the backend it creates (ADR 0008: "no backend bucket is created by a root
that already relies on it").

## What is preserved from the ADRs

The accepted ADRs are the contract. None of these behaviours changed.

| ADR | Decision preserved | Where it is enforced in v1 |
|---|---|---|
| 0008 (state, and its 2026-09-20 amendment) | One isolated backend per environment tier: SSE-KMS, versioning, restrictive CI and break-glass bucket policies, DynamoDB locking, lifecycle, Object Lock where required. | `kms.tf`, `buckets.tf`, `replica_buckets.tf`, `locks.tf`, `modules/policies`; `tests/posture.tftest.hcl`, `tests/replication.tftest.hcl`. |
| 0008 amendment | State buckets, keys and lock tables are protected from Terraform destruction (`prevent_destroy`). | Every stateful resource keeps `lifecycle { prevent_destroy = true }`. `scripts/check-destroy-guards.sh` (part of `make check` and CI) fails when one is removed, because `terraform test` cannot see lifecycle settings. |
| 0008 amendment | Provider aliases are bound to their declared primary and replica Regions. | New in v1: two `aws_region` data sources and one precondition each on `aws_kms_key.state` and `aws_kms_replica_key.state` turn the obligation into a plan-time error. |
| 0016 (Proposed) | The S3 native lockfile is emitted (`use_lockfile = true`) and the DynamoDB lock table is kept, protected from destruction, for the transition. Retirement needs its own ADR amendment. | `outputs.tf` is unchanged; `locks.tf` keeps the table. No lock-table removal path exists. |
| 0008 | The central access-log bucket is an **input** (`access_log_bucket_name`), owned by Log Archive. The module never creates it. | `variables.tf`; the fixtures in `tests/integration/setup` create a throwaway one for the smoke suite only. |
| 0008 | Object Lock is an explicit per-tier decision (`object_lock = { enabled, retention_mode, retention_days }`) and applies to both copies of a replicated tier. | `buckets.tf`, `replica_buckets.tf`. |
| 0008 | Multi-tier map interface; per-tier replica opt-in; replica provider alias `aws.replica`. | `variables.tf`, `versions.tf` (`configuration_aliases = [aws.replica]`). |
| 0010, 0014 | Consumers pin a signed release commit; reusable implementation lives in an `aws.modules.*` repository; nothing here authorizes an apply. | README "Versioning and releases"; the integration suite is dispatch-only. |

### A discrepancy to resolve outside this repository

ADR 0015 (`adopt-legacy-state-bootstrap`) is now **Closed**: the historical
adoption is complete and "no reusable procedure remains". `modules/legacy-adoption`
was published in v0.1.0 as that adoption composition, and removing it would
change the module's public source paths. v1 therefore keeps it unchanged in
behaviour, adds contract tests and a plan-only example so the composition stays
valid, and labels it historical in its README. It must not be used for a new
backend. Retiring it is a v2 candidate that needs an ADR 0015 amendment (see
[Deferred to v2](#deferred-to-v2)).

## What changed and why

| v0.1.0 | Problem | v1 |
|---|---|---|
| Five concerns (KMS, buckets, replication, lock table, policy documents) shared one 422-line `main.tf` and a 233-line `locals.tf`. | A reviewer could not read one concern without scrolling past four others. | One file per concern: `kms.tf`, `buckets.tf`, `replica_buckets.tf`, `replication.tf`, `locks.tf`, `regions.tf`, `checks.tf`. Resource addresses are unchanged, so no `moved` block exists or is needed. |
| Policy documents were `jsonencode` locals built from resource ARNs. | The ARNs are unknown at plan time, so no test could assert the content of a bucket, key or replication policy; and `prevent_destroy` makes a mock `apply` run impossible, because `terraform test` fails its own teardown on a protected resource. The security-critical documents were untested. | `modules/policies` is a pure renderer (no resources, no provider). It receives ARNs as inputs and returns the five document maps, byte-identical to v0.1.0's. Its tests assert every statement of every variant with known ARNs. |
| One `validation` carried six conditions and one message. | "Every tier needs a valid primary bucket, an optional distinct valid replica bucket, and positive whole-number lifecycle periods" does not say which tier or which rule failed. | Separate validations with precise messages: bucket naming rules, replica distinct from primary, unique names across all tiers and replicas, whole-number lifecycle periods, Object Lock rules. |
| The 2026-09-20 ADR amendment says provider aliases must be bound to their declared Regions. | Nothing checked it: a mis-bound alias would create the replica in the wrong Region while the outputs claimed the declared one. | Preconditions compare `data.aws_region` of each provider with `primary_region` and `replica_region`. |
| The replication role name is `<prefix>-<tier>-terraform-state-replication`. | IAM limits role names to 64 characters; a 31-character prefix and tier overflow it and fail at apply. | A precondition on `aws_iam_role.state_replication` names the tier and the limit at plan time. |
| `access_log_bucket_name` could name one of the state buckets. | A state bucket logging into itself, or a replica logging into the primary, creates a log-of-log feedback loop on the most sensitive buckets. | A precondition on `aws_s3_bucket_logging.state` rejects it. |
| Silent behaviours: Object Lock retention fields ignored when Object Lock is off; module-owned tags overwriting the caller's; administrators who are also routine state users; noncurrent-version expiry shorter than the Object Lock retention. | Each is valid but usually unintended. | Four advisory `check` blocks (`checks.tf`), each with a test. |
| Tests: three `plan` runs. | No variant, validation or policy assertion. | Seven root test files (posture, replication, documents, outputs, preconditions, validation, checks), a policies suite with a byte-for-byte v0.1.0 golden, a legacy-adoption suite, and a guard-lifted mock-apply suite that proves the root wires the right document to the right resource for every variant. |
| No examples, no upgrade guide, no design record. | Behaviour was unpinned and undocumented. | Five examples validated in CI, `docs/UPGRADE-1.0.md`, this document. |
| The legacy submodule committed its `.terraform.lock.hcl`, and its README linked into a monorepo path that does not exist here. | CI's lock expectations (root only) and dead links. | The file is untracked (gitignored); links point at the ADRs on GitHub and state that ADR 0015 is closed. |
| CI: an inline workflow that formatted, validated (skipping alias modules) and tested. | No tflint, Checkov, Trivy or docs-drift check; no per-submodule and per-example matrix. | The standard quality matrix through the shared pipeline for every directory the shared workflow can validate, plus an inline job for the root (see [CI and the provider alias](#ci-and-the-provider-alias)). |

## Principles and how the module applies them

- **Single responsibility.** One file per concern in the root. `modules/policies`
  owns the shape of every policy document and nothing else; it creates no
  resources and declares no provider.
- **Open/closed.** A new tier is a new map entry; a new replica is one more
  attribute on a tier. No behaviour requires editing the module.
- **Liskov substitution.** Every tier, replicated or not, exposes the same
  output shape; the replica fields are `null` for a tier without a replica.
- **Interface segregation.** A tier that does not replicate needs no replica
  bucket name and receives no replica resource, replication role or replica
  key.
- **Dependency inversion.** The root depends on identifiers (role ARNs, a log
  bucket name), never on how they were produced. `modules/policies` depends on
  ARN strings only, so it can be tested with no provider.
- **Secure by default, no escape hatch.** There is no input that weakens a
  control: public access blocks, ownership enforcement, versioning, SSE-KMS with
  a Bucket Key, the TLS deny, the role deny, key rotation and PITR are not
  configurable.

## Architecture

```text
root (one call = all tiers)
├── versions.tf         terraform >= 1.7.0, aws >= 6.35.0 with configuration_aliases = [aws.replica]
├── variables.tf        typed inputs, validations
├── locals.tf           replication_tiers, common_tags, lock-table names
├── regions.tf          data.aws_region.primary, data.aws_region.replica (provider-region binding)
├── kms.tf              aws_kms_key.state, aws_kms_replica_key.state, aliases
├── buckets.tf          aws_s3_bucket.state and its nine configuration resources, policy, logging, notification
├── replica_buckets.tf  the same set for the replica copy (aws.replica), only for replicated tiers
├── replication.tf      aws_iam_role.state_replication, its inline policy, aws_s3_bucket_replication_configuration.state
├── locks.tf            aws_dynamodb_table.state_lock
├── policies.tf         module "policies" -> modules/policies (pure)
├── checks.tf           advisory checks
├── outputs.tf          backend_configuration, state_access_policy_arns (unchanged)
└── modules/
    ├── policies/         pure renderer of the five policy document maps
    └── legacy-adoption/  ADR 0015 adoption composition (historical, behaviour unchanged)
```

Data flow: the root creates buckets, keys and roles, then hands their ARNs to
`modules/policies` as five separate maps (`bucket_arns`, `key_arns`,
`replication_role_arns`, `replica_bucket_arns`, `replica_key_arns`). They are
separate on purpose: a single object input would make every output depend on
every ARN, and the key policy (which names the replication role) would then
depend on the key it protects, a cycle. Each policy output depends only on the
inputs it renders, so the graph stays acyclic.

### Interface summary

Required inputs: `name_prefix`, `primary_region`, `replica_region`,
`access_log_bucket_name`, `access_log_prefix`, `state_tiers`,
`state_access_principal_arns` (at least two roles), `kms_key_deletion_window_in_days`,
`key_administrator_arns`. Optional: `tags`.

`state_tiers` is a map keyed by tier name; each value is
`{ bucket_name, replica_bucket_name (optional), noncurrent_version_expiration_in_days,
abort_incomplete_multipart_upload_after_days, object_lock = { enabled, retention_mode, retention_days } }`.

Outputs (unchanged): `backend_configuration` and `state_access_policy_arns`, both
keyed by tier.

## Security posture

Asserted per tier variant (replica on and off, Object Lock on and off):

- Primary and replica buckets: all four public access blocks, `BucketOwnerEnforced`,
  versioning `Enabled`, SSE-KMS with a Bucket Key under the tier's own key
  (replica bucket under the replica key), lifecycle rule for noncurrent versions
  and incomplete multipart uploads, server access logging under
  `<prefix>/primary/<tier>/` and `<prefix>/replica/<tier>/`, EventBridge
  notifications, Object Lock default retention exactly as declared for the tier.
- Bucket policies: `DenyInsecureTransport` on the bucket and its objects;
  `Deny s3:*` for every principal that is not one of the CI and break-glass roles
  plus the tier's own replication role (`aws:PrincipalArn` `ArnNotEquals`); allow
  statements only for the CI and break-glass roles. Another tier's replication
  role never appears in this tier's documents.
- KMS: multi-Region primary, rotation on, deletion window as declared, an
  administration statement for `key_administrator_arns` and a use statement for
  the CI, break-glass and (when replicated) the tier's replication role. There is
  deliberately no account-root statement: only the named roles can use or manage
  a state key.
- Replication role: assumable only by `s3.amazonaws.com`; its policy reads only
  the tier's source bucket, writes only the tier's replica bucket, and uses only
  the tier's two keys.
- Lock table: on-demand, `LockID` hash key, SSE with the tier's key, point-in-time
  recovery on.
- Every stateful resource keeps `prevent_destroy`.

## Testing strategy

Terraform 1.7's `terraform test` has two limits that shaped the layout:

1. Computed attributes (ARNs) are unknown at plan time, so a plan-only test cannot
   read a policy that embeds one.
2. A `command = apply` run tears down what it created, and the teardown fails on a
   `prevent_destroy` resource (`Instance cannot be destroyed`). Every stateful
   resource here is protected by ADR 0008, so the root cannot be applied under
   `mock_provider` as it is committed.

Layers:

| Layer | Runs in | What it proves |
|---|---|---|
| `modules/policies/tests` | `terraform test` in the submodule; plan only, no provider | Every statement of every document for every variant, with known ARNs: TLS deny, role deny, allow lists, per-tier role scoping across two tiers, key policies, replication policy, and the input consistency rules. |
| `tests/*.tftest.hcl` (root) | `terraform test`; `mock_provider`, plan only | Everything known at plan: resource counts per tier variant, every configuration attribute, Object Lock on both copies, lifecycle, logging prefixes, notifications, tags, names, the replication rule, the role's trust policy, the non-replicated tiers' key policies, every validation and precondition through `expect_failures`, every advisory check. |
| `tests/wired/*.tftest.hcl` | `make test-wired` and the CI root job; `mock_provider`, apply, run against a temporary copy with the destroy guards lifted (`scripts/lift-destroy-guards.sh`) | The composition: with distinct ARNs per instance, the right document reaches the right resource for every variant (per-tier role scoping in the rendered bucket, key and replication documents). |
| `scripts/check-destroy-guards.sh` | `make check` and CI | Every stateful resource, in the root and in `modules/legacy-adoption`, keeps `prevent_destroy = true`. |
| `tests/integration/smoke.tftest.hcl` | Dispatch only, real AWS | A non-replicated tier is accepted by the real APIs and destroyed. It also runs against a guard-lifted copy. |

The guard-lifted copy is a test harness, never a deployable variant: the script
rewrites `prevent_destroy = true` to `false` in a temporary directory and refuses
to run when it finds none, so it cannot silently test an unguarded tree that no
longer matches the committed one.

## CI and the provider alias

`configuration_aliases` makes the root module require a provider it cannot
configure itself, so `terraform validate` in the module directory fails with
"Provider configuration not present". The commit `ci: support provider alias
modules` (940cd58) dealt with it by skipping validate for such modules. The shared
pipeline (`terraform-pipelines` v0.1.0 quality, v0.1.1 release) validates the
module directory unconditionally, so it cannot go green on this root.

v1 keeps the standard matrix for `modules/*` and `examples/*` (every example
calls the root through real provider wiring, so `terraform validate` there
validates the whole root) and runs the root itself in an inline job that mirrors
the shared workflow's steps at the same pinned action commits, minus the
standalone validate, plus the guard checks and the wired tests. The release
workflow is inline for the same reason and differs from
`terraform-pipelines/.github/workflows/module-release.yml@8fc2a04` only in its
verification step: it validates through `examples/minimal` instead of the root,
keeps the lock file read-only, and runs the destroy-guard check. The tag
verification and the publish step are the shared workflow's, unchanged. Both should return to the shared pipeline once it skips validate for alias
modules; that change belongs in `terraform-pipelines` and is outside this
repository. Replacing the alias (see Deferred) removes the need altogether.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0` (the platform pins 1.7.5); AWS provider
  `>= 6.35.0, < 7.0.0` (`aws_region.region` needs 6.x).
- Upgrade from v0.1.0: change the `ref`. Inputs, outputs, resource addresses and
  every rendered resource argument and policy document are unchanged, so the
  first plan is expected to be a no-op. See `docs/UPGRADE-1.0.md`.
- `infra/active` in the platform repository does not consume this module today.

## Deferred to v2

Each item would change an input, an output, a resource address or a live policy
or resource argument, so it is out of scope for an interface-preserving v1.

| Candidate | Why it is deferred |
|---|---|
| Remove `modules/legacy-adoption`. | ADR 0015 is Closed; removal changes public source paths. Needs an ADR amendment and a major version. |
| Drop the `aws.replica` alias in favour of the provider v6 per-resource `region` argument. | Removes `configuration_aliases`, so the root would validate and the shared pipeline would apply unchanged. It changes the provider interface every consumer wires, and ADR 0008's amendment names the aliases explicitly. |
| Additional outputs: KMS alias names, replication role ARNs, lock-table ARNs as a separate map, region per tier. | Adding outputs alters the output set; a consumer diff is small but it is an interface change. |
| TLS 1.2 minimum in the bucket policy (`s3:TlsVersion`), and a deny for uploads that are not SSE-KMS under the tier's key. | Changes rendered policy documents of a backend that protects state; needs Security review and a lockout analysis against S3 backend clients. |
| `deletion_protection_enabled` on the lock table. | An in-place change to a live table, and it would also block the guard-lifted integration teardown; ADR 0016 governs the lock table's lifecycle. |
| Retire the DynamoDB lock table and `use_lockfile`-only outputs. | ADR 0016 forbids it until the transition evidence exists; it removes an output field. |
| Bring-your-own replica key, replication time control and metrics, replication role path and permissions boundary, per-tier key administrators. | New optional inputs; each needs a decision on its default and on Object Lock and KMS interaction. |
| An account-root statement in the KMS key policy, or an explicit orphaned-key recovery role. | Deliberately absent today (only named roles can manage a state key); revisiting it is a security decision, not a refactor. |
| Derive bucket ARNs from name and partition instead of the resource attribute. | Only useful to make more policy content known at plan time; the guard-lifted wired suite already covers the composition. |
