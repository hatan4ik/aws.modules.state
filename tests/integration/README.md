# Integration suites

The suites in this directory apply the module for real in **your** AWS account and destroy everything afterwards. They complement the contract tests in `tests/`, which run with `mock_provider`, need no credentials, and use the AWS documentation account `111122223333` and placeholder ARNs on purpose: they prove the module's interface, rendering and wiring, not that AWS accepts it. These suites prove the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and the region come from the environment. Everything else is created by [`setup/`](setup/) with a random suffix so concurrent runs never collide: a throwaway central access-log bucket (the module requires a pre-existing one and deliberately never creates it), a stand-in break-glass role, and unique names.

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | One non-replicated tier without Object Lock is accepted by the real APIs: a multi-Region KMS key with rotation and the module's key policy, a private, owner-enforced, versioned bucket with the TLS-only, role-restricted policy, access logging that S3 accepts against the fixture's log bucket, EventBridge notifications, and an on-demand encrypted lock table with point-in-time recovery. Then everything is destroyed. | credentials of an IAM role, region | a few minutes |

## Two things that differ from other modules' suites

**The suite runs in a guard-lifted temporary copy.** Every bucket, key and lock table keeps `prevent_destroy = true` (ADR 0008), and Terraform refuses to destroy a protected resource, so `terraform test` against the committed tree would leave the whole tier behind. `scripts/run-integration.sh` copies the module to a temporary directory, rewrites the guards to `false` **there**, runs the suite, and deletes the copy; the committed tree is never modified and the script refuses to run when it finds no guard to lift. Run suites through `make integration-smoke` or the workflow, never with a bare `terraform test -test-directory=tests/integration` from the repository root (that would also add `hashicorp/random` to the committed root lock file).

**The suite must run as an IAM role.** The module accepts role ARNs only, and its bucket policy denies every principal that is not a state access principal while its key policy has no account-root statement. The identity that applies it therefore has to be named in `state_access_principal_arns` and `key_administrator_arns`; the fixture resolves the role behind the assumed-role session and names it in both, which fires the advisory `key_administrators_are_not_routine_state_users` check by construction (the suite expects it). A plain IAM user fails early with the module's role-ARN validation message.

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN of an assumed role
export AWS_REGION=<region>
make integration-smoke              # scripts/run-integration.sh smoke
```

The credentials need the permissions in [`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json) (replace `<ACCOUNT_ID>` and `<INTEGRATION_ROLE_NAME>`), scoped to resource names starting with `state-it-`, which is what the fixture produces. KMS data-plane and key-management actions are governed by the key policy the module renders, not by this policy; only `kms:CreateKey` and alias management need it. The policy was derived from the calls the AWS provider makes for these resources and has not been exercised against a live account by its author: the first run may reveal an action to add.

The KMS key the suite creates cannot be deleted immediately: it stays in pending deletion for the 7-day minimum window. A freshly created IAM role can take a moment to become usable as a principal in a key or bucket policy; the provider retries, so a slow first apply is not a failure.

`terraform test` runs `tests/` only by default, so these suites never run in the credential-free quality pipeline. The fixture module is excluded from the Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`) because it is short-lived test scaffolding, not a deployable pattern.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is dispatch-only and assumes a role through GitHub OIDC. It reads everything account-specific from the protected `integration` environment of the repository, so the code stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the disposable tier. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the environment with required reviewers so a run cannot be started from a pull request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox region; the role ARN is added once the role exists in the sandbox account, created through the platform's delivery IAM module with the trust policy above and the subject `repo:hatan4ik/aws.modules.state:environment:integration`.
