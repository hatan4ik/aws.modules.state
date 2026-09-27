#!/usr/bin/env bash
# Runs tests/wired against a temporary copy of the module with the destroy guards
# lifted (see scripts/lift-destroy-guards.sh). The suite applies the whole root
# under mock providers with distinct ARNs per instance and asserts that each
# policy document reaches the right resource. It needs no credentials.
set -euo pipefail

cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
copy="$work/module"

scripts/lift-destroy-guards.sh "$copy"
cd "$copy"
terraform init -backend=false -input=false -no-color >/dev/null
terraform test -test-directory=tests/wired -no-color
