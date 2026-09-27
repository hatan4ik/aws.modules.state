# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| 0.1.x | Security fixes only, until 2026-12-31. Upgrade with [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md); the upgrade changes only the `ref`. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact account IDs, role ARNs, bucket names and KMS key IDs.

## What counts

- A module default that weakens a control: a bucket without the public access block, ownership enforcement, versioning or SSE-KMS; a bucket policy that admits a principal outside the CI, break-glass and the tier's own replication role, or allows non-TLS access; a key without rotation, or with a policy that grants use or administration to a principal it should not.
- A tier boundary bypass: one tier's replication role, key, bucket or lock table appearing in another tier's documents or being reachable through another tier's role.
- A stateful resource that can be destroyed by a plain `terraform destroy` (a lost `prevent_destroy`), or a lock table, bucket or key that the module removes without an explicit, reviewed change.
- A validation bypass: an input the module claims to reject at plan time (a mis-bound provider Region, a non-role principal, a bucket name reused across tiers, an access-log bucket that is a state bucket) but that reaches the provider.
- A replication scope bypass: a replication role able to read or write outside its own tier's source bucket, replica bucket and two keys.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example an administrator role you chose to also make a CI role) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release of every supported line with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default and offers no input that weakens a control: private, owner-enforced, versioned, SSE-KMS buckets; a TLS-only bucket policy that denies every principal outside the state roles; multi-Region keys with rotation and no account-root statement; a tier-scoped replication role assumable only by S3; an on-demand, encrypted, recoverable lock table; `prevent_destroy` on every bucket, key and lock table, enforced by a CI check; providers bound to the Regions the module is told about. Every claim is enforced by a validation, a precondition, a `check` block, or a `terraform test` case behind it, and the policy documents are compared byte for byte with the ones the accepted design produced. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).

This module is bootstrapped from a specially approved root and must never use the backend it creates; see the [Bootstrapping](README.md#bootstrapping) section.
