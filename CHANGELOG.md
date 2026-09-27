# Changelog

All notable changes to this module are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-27

A hardening-and-standards uplift that preserves the ADR-accepted design. Inputs, outputs, resource addresses and every rendered resource argument and policy document are unchanged; upgrade by changing the `ref` (see [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md)).

### Added

- `modules/policies`: a pure renderer (no resources, no provider) for the key, replica key, bucket, replica bucket and replication policy documents, with a golden test proving they are byte-identical to the documents 0.1.0 built inline.
- Plan-time preconditions: the default provider must be bound to `primary_region` and the `aws.replica` provider to `replica_region` (ADR 0008's 2026-09-20 amendment); the replication role name must fit IAM's 64-character limit; `access_log_bucket_name` must not be one of the module's own buckets.
- Stricter and more precise variable validation: general purpose bucket naming rules, unique bucket names across every tier and replica, separate validations for each lifecycle period and Object Lock field, valid tag keys.
- Advisory `check` blocks: `key_administrators_are_not_routine_state_users`, `object_lock_settings_are_used`, `object_lock_retention_outlives_noncurrent_expiration`, `tags_are_not_overwritten_by_the_module`.
- Contract tests for every tier variant and every validation, precondition and check; a wiring suite that applies the root under mock providers with the destroy guards lifted; `scripts/check-destroy-guards.sh` to keep `prevent_destroy` on every stateful resource.
- Examples: `minimal`, `replicated-tier`, `object-lock-tier`, `multiple-tiers` and the historical, plan-only `legacy-adoption`.
- A credential-driven, dispatch-only integration suite (`tests/integration`) that applies one non-replicated tier with a throwaway access-log bucket and destroys it.
- `docs/DESIGN.md`, `docs/UPGRADE-1.0.md`, a README written from scratch, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (Apache-2.0), issue and pull request templates, CODEOWNERS, Dependabot, pre-commit, tflint, Checkov and Trivy configuration and a `Makefile` quality gate.

### Changed

- The root is split into one file per concern (`kms.tf`, `buckets.tf`, `replica_buckets.tf`, `replication.tf`, `locks.tf`, `regions.tf`, `policies.tf`, `checks.tf`). Resource addresses are unchanged.
- The quality workflow runs the standard matrix (fmt, validate, tflint, `terraform test`, Checkov, Trivy, docs drift) for every submodule and example through the shared pipeline, and an inline job for the root, because a root that declares `configuration_aliases` cannot be validated standalone. The release workflow is inline for the same reason.
- Descriptions of `state_tiers`, `primary_region`, `replica_region`, `access_log_bucket_name`, `access_log_prefix`, `state_access_principal_arns`, `key_administrator_arns` and `tags` are more precise.
- `modules/legacy-adoption` is unchanged in behaviour, now has deeper contract tests, and its README states that ADR 0015 is closed and it must not be used for a new backend.

### Removed

- The committed `modules/legacy-adoption/.terraform.lock.hcl`; only the repository root commits a lock file.

### Fixed

- The root `.terraform.lock.hcl` carries checksums for linux and macOS on amd64 and arm64.
- The `legacy-adoption` README linked into a monorepo path that does not exist in this repository.

## [0.1.0] - 2026-09-22

### Added

- Multi-tier state-backend module: a primary S3 bucket, multi-Region KMS key and DynamoDB lock table per tier, optional same-tier cross-Region replication with a tier-scoped replication role, Object Lock as an explicit per-tier decision, TLS-only and role-restricted bucket policies, access logging to a pre-existing central log bucket, and EventBridge notifications.
- `modules/legacy-adoption` for the ADR 0015 adoption of the prototype's state resources.
- The quality workflow tests modules that declare `configuration_aliases` with the provider alias supplied by their test file.

[Unreleased]: https://github.com/hatan4ik/aws.modules.state/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.state/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/hatan4ik/aws.modules.state/releases/tag/v0.1.0
