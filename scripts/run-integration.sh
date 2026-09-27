#!/usr/bin/env bash
# Runs one integration suite (tests/integration/<suite>.tftest.hcl) for real, in
# the account and region the environment points at, against a temporary copy of
# the module with the destroy guards lifted so the disposable tier can be torn
# down (see scripts/lift-destroy-guards.sh). The committed tree is untouched.
#
# The suite creates only resources with a random suffix and a throwaway access-log
# bucket; it never reads or changes anything else. The KMS key it creates stays
# in pending deletion for the 7-day minimum.
#
# Usage: scripts/run-integration.sh <suite> [extra terraform test arguments]
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <suite> [terraform test arguments]" >&2
  exit 64
fi
suite="$1"
shift

cd "$(dirname "$0")/.."
if [ ! -f "tests/integration/${suite}.tftest.hcl" ]; then
  echo "error: no such suite: tests/integration/${suite}.tftest.hcl" >&2
  exit 66
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
copy="$work/module"

scripts/lift-destroy-guards.sh "$copy"
cd "$copy"
terraform init -backend=false -input=false -no-color -test-directory=tests/integration >/dev/null
terraform test -test-directory=tests/integration -filter="tests/integration/${suite}.tftest.hcl" -no-color "$@"
