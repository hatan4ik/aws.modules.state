SHELL := /bin/bash
.DEFAULT_GOAL := check

ROOT_DIRS     := . modules/policies modules/legacy-adoption
# Only example directories that contain Terraform, so a stray file under examples/ is ignored.
EXAMPLE_DIRS  := $(sort $(patsubst %/,%,$(dir $(wildcard examples/*/*.tf))))
# Disposable fixtures for the credential-driven integration suites; validated
# and linted like any module, excluded from policy scans (see .checkov.yml).
FIXTURE_DIRS  := tests/integration/setup
ALL_DIRS      := $(ROOT_DIRS) $(EXAMPLE_DIRS) $(FIXTURE_DIRS)
TFLINT_CONFIG := $(CURDIR)/.tflint.hcl
TFDOCS_CONFIG := $(CURDIR)/.terraform-docs.yml
# Must match the terraform-docs bundled by the CI action (terraform-docs/gh-actions
# v1.4.1 ships 0.20.0); newer versions change table formatting and fail the
# docs drift check in CI.
TFDOCS_VERSION := v0.20.0

.PHONY: check fmt fmt-fix init validate lint test test-wired guards docs-version docs docs-check security lock integration-smoke clean

check: fmt validate lint test test-wired guards docs-check security

fmt:
	@echo "==> fmt ."
	@terraform fmt -check -recursive -diff

fmt-fix:
	@echo "==> fmt-fix ."
	@terraform fmt -recursive

init:
	@for dir in $(ALL_DIRS); do \
	  echo "==> init $$dir"; \
	  (cd "$$dir" && terraform init -backend=false -input=false >/dev/null) || exit 1; \
	done

# The root declares configuration_aliases = [aws.replica], so `terraform validate`
# cannot run in it: a root module cannot configure the provider it expects a
# caller to pass. Every example calls the root through real provider wiring, so
# validating the examples validates the whole root.
validate: init
	@for dir in $(ALL_DIRS); do \
	  if grep -qs configuration_aliases "$$dir/versions.tf"; then \
	    echo "==> validate $$dir (skipped: declares configuration_aliases; validated through the examples)"; \
	  else \
	    echo "==> validate $$dir"; \
	    (cd "$$dir" && terraform validate) || exit 1; \
	  fi; \
	done

lint:
	@echo "==> lint (tflint --init)"
	@tflint --init --config="$(TFLINT_CONFIG)"
	@for dir in $(ALL_DIRS); do \
	  echo "==> lint $$dir"; \
	  (cd "$$dir" && tflint --config="$(TFLINT_CONFIG)" --format compact) || exit 1; \
	done

test:
	@for dir in $(ROOT_DIRS); do \
	  echo "==> test $$dir"; \
	  (cd "$$dir" && terraform test) || exit 1; \
	done

# Applies the whole root under mock providers, in a temporary copy with the
# prevent_destroy guards lifted, and asserts every policy document is wired to
# the right resource. See tests/wired and docs/DESIGN.md, "Testing strategy".
test-wired:
	@echo "==> test-wired (guard-lifted temporary copy)"
	@scripts/test-wired.sh

# ADR 0008 requires state buckets, keys and lock tables to keep prevent_destroy;
# terraform test cannot see lifecycle settings, so this static check guards them.
guards:
	@echo "==> guards"
	@scripts/check-destroy-guards.sh

docs-version:
	@terraform-docs --version | grep -q "$(TFDOCS_VERSION)" || { \
	  echo "error: terraform-docs $(TFDOCS_VERSION) is required (found: $$(terraform-docs --version)); CI generates docs with that version" >&2; exit 1; }

docs: docs-version
	@for dir in $(ALL_DIRS); do \
	  echo "==> docs $$dir"; \
	  terraform-docs -c "$(TFDOCS_CONFIG)" "$$dir" || exit 1; \
	done

docs-check: docs-version
	@for dir in $(ALL_DIRS); do \
	  echo "==> docs-check $$dir"; \
	  terraform-docs -c "$(TFDOCS_CONFIG)" --output-check "$$dir" || exit 1; \
	done

security:
	@echo "==> security checkov ."
	@checkov -d . --framework terraform --quiet --compact
	@if command -v trivy >/dev/null 2>&1; then \
	  echo "==> security trivy ."; \
	  trivy config --severity HIGH,CRITICAL --exit-code 1 .; \
	else \
	  echo "==> security trivy . (skipped: trivy not on PATH)"; \
	fi

# Integration suites apply the module for real in the caller's own account and
# destroy everything afterwards, against a temporary copy of the module with the
# prevent_destroy guards lifted so the disposable tier can be torn down.
# Credentials and region come from the environment; see tests/integration/README.md.
integration-smoke: integration-%:
	@[ -n "$$AWS_REGION$$AWS_DEFAULT_REGION" ] || { echo "error: set AWS_REGION (and credentials of an IAM role) for the account that will host the disposable state tier" >&2; exit 1; }
	@echo "==> integration $* (real apply in $${AWS_REGION:-$$AWS_DEFAULT_REGION})"
	@scripts/run-integration.sh "$*" -verbose

# The root lock file is committed. It must carry hashes for every platform CI
# and contributors use, otherwise `terraform init` rewrites it and the docs
# drift check fails on the modified tree.
lock:
	@echo "==> lock ."
	@terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64

clean:
	@echo "==> clean ."
	@find . -type d -name .terraform -prune -exec rm -rf {} +
	@find . -mindepth 2 -name .terraform.lock.hcl -not -path '*/.terraform/*' -delete
