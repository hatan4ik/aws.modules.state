# Contributing

Thank you for improving `aws.modules.state`. This module protects Terraform state, so changes are held to a higher bar than most: nothing may loosen a control, every policy statement is a reviewed decision, and every behaviour is pinned by a test. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy (CI runs 3.3.19) | `pip install checkov==3.3.19` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## The root cannot be validated standalone

The root declares `configuration_aliases = [aws.replica]`, so `terraform validate` in the repository root reports "Provider configuration not present": a root module cannot configure the provider it expects a caller to pass. That is why `make validate` skips the root (every example calls it with real provider wiring, so validating the examples validates the whole root), why the CI quality job for the root is inline instead of the shared workflow, and why the release workflow validates through `examples/minimal`. Do not "fix" it by adding a provider block to the root.

## The destroy guards

Every bucket, KMS key and lock table carries `lifecycle { prevent_destroy = true }` (ADR 0008). Two consequences shape the tests:

- `terraform test` cannot see lifecycle settings, so `scripts/check-destroy-guards.sh` (`make guards`) fails when a stateful resource loses its guard. Adding a stateful resource type means adding it to that script.
- A `command = apply` run tears down what it applied, and the teardown fails on a protected resource. Apply-based suites therefore run against a **temporary copy** with the guards lifted (`scripts/lift-destroy-guards.sh`): `tests/wired` (mock providers, `make test-wired`) and `tests/integration` (real account). The committed tree is never modified, and the script refuses to run if it finds no guard to lift. Never put a `command = apply` run in `tests/`.

## Integration suites

`tests/integration/` holds credential-driven suites that apply the module for real and destroy everything afterwards. They are never part of `make check` or the quality pipeline. Run them against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>   # credentials of an IAM ROLE (assumed-role session)
make integration-smoke   # a few minutes; one non-replicated tier, a throwaway log bucket and role, all destroyed
```

The suite must run as an IAM role because the module accepts role ARNs only. The KMS key it creates stays in pending deletion for the 7-day minimum. Keep every value derived from the environment or from disposable fixtures the suite creates, and never reference a real bucket, key, role or account. Fixtures live in `tests/integration/setup`, which the policy scans exclude. The permissions the suite needs are in `tests/integration/iam/`.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in every directory except the root (see above): the submodules, the examples and the integration fixture. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root and in each submodule. No credentials are needed. |
| `make test-wired` | The wiring suite against a guard-lifted temporary copy (see above). No credentials are needed. |
| `make guards` | `scripts/check-destroy-guards.sh`. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init -lockfile=readonly` for the root, so a lock file missing the Linux hash fails. Only the root commits a lock file; submodule and example lock files are gitignored, and `terraform init -test-directory=tests/integration` at the root would add `hashicorp/random` to it, which must never be committed (the integration script runs in a temporary copy for this reason). |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment (or an entry with a reason in `.checkov.yml`) and must be a real, accepted finding or a proven analysis limitation; never suppress a real finding to go green. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `test-wired`, `guards`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Root tests live in `tests/*.tftest.hcl`, one file per concern: `posture` (the security posture of every tier variant), `replication`, `documents` and `outputs` (what is known at plan time), `preconditions` (Region binding and the other cross-input rules), `validation` (every variable validation) and `checks`. Each file starts with two `mock_provider "aws"` blocks (the default and `alias = "replica"`), each with a `mock_data "aws_region"` default so the Region-binding preconditions see the Region the test intends, and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan`. Computed attributes (ARNs, ids) are unknown at plan time, so assert on what the module knows by construction: names, tags, flags, periods, counts and `keys()`, never on a computed value.
- **Policy documents** are asserted in `modules/policies/tests` with known ARNs; `policies.tftest.hcl` there holds a golden comparison with the documents v0.1.0 built. A change to a statement is a change to the live policy of a backend that protects state: update the golden strings only as a reviewed decision, and record it in the changelog. Wiring (the right document on the right resource) is asserted in `tests/wired`.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.state_tiers]` for a variable validation, `[aws_kms_key.state]` for a precondition, `[check.object_lock_settings_are_used]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail, so list every failing object; add a positive run alongside so the accepted boundary is covered too.
- A `check` block that fires fails the run unless it is in `expect_failures`; the baseline must satisfy every check.
- `||` and `&&` do not short-circuit in Terraform 1.7. Guard nulls with a conditional: `x == null ? true : x.field > 0`.
- Whole-object equality between objects with null fields fails because the types differ; compare field by field.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

| Concern | Lives in |
| --- | --- |
| A KMS key setting | `kms.tf`, guarded so the fixed controls stay fixed; a case in `tests/posture.tftest.hcl`. |
| A bucket setting or resource | `buckets.tf` and `replica_buckets.tf` together (the replica has the same controls); cases in `tests/posture.tftest.hcl` and `tests/replication.tftest.hcl`. |
| Replication | `replication.tf`; `tests/replication.tftest.hcl`; the policy in `modules/policies`. |
| A policy statement | `modules/policies/main.tf`, its tests and golden strings, `tests/wired`, and a Security review. |
| The lock table | `locks.tf`; ADR 0016 governs its lifecycle. |
| A new input | `variables.tf` with a description, type and validation, and cases in `tests/validation.tftest.hcl`. |
| A cross-input rule | A precondition on the resource it guards (Terraform 1.7 has no cross-variable validation) and a case in `tests/preconditions.tftest.hcl`; `checks.tf` when the situation is valid but usually unintended. |
| Outputs | `outputs.tf`; both existing outputs are a stable interface, and adding one is a minor release. |

Rules that apply everywhere: no data source that an input could replace (the two `aws_region` data sources bind the providers to the declared Regions and cannot be replaced by an input), every variable has a description, a type and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, no input weakens a control, and no stateful resource loses `prevent_destroy`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(validation): reject a replica bucket that reuses another tier's primary
fix(policies): keep the replication role out of another tier's key policy
docs: explain the bootstrap identity requirements
test(wired): cover a replicated tier without Object Lock
feat!: rename state_tiers.object_lock to state_tiers.retention
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] No policy statement, encryption, public access or destroy-guard setting is loosened; a changed statement has a reviewed golden update.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] Inputs, outputs and resource addresses are unchanged, or the change is a documented major release.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.state vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, configuration (through `examples/minimal`), tests, destroy guards and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out, and a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag (ADR 0010):

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.state.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
