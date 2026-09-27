#!/usr/bin/env bash
# Copies this module into a NEW directory and rewrites `prevent_destroy = true`
# to `false` there. The copy is a test harness for two things `terraform test`
# cannot do against the committed tree:
#
#   * mock `apply` runs (tests/wired): the test runner tears down what it created,
#     and that teardown fails with "Instance cannot be destroyed" on a protected
#     resource;
#   * the real-account integration suite (tests/integration): the disposable tier
#     must be destroyable.
#
# The committed source is never modified and the copy is never deployable: use
# it only for the suites above. The script refuses to run when it finds no guard
# to lift, so it cannot silently test a tree that no longer matches the source.
#
# Usage: scripts/lift-destroy-guards.sh <destination-directory-that-does-not-exist>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <destination-directory>" >&2
  exit 64
fi

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
destination="$1"

if [ -e "$destination" ]; then
  echo "error: $destination already exists" >&2
  exit 73
fi
mkdir -p "$destination"

tar -C "$source_dir" --exclude=.git --exclude=.terraform --exclude=.cache -cf - . | tar -C "$destination" -xf -

lifted=0
while IFS= read -r file; do
  count="$(grep -c 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$file" || true)"
  if [ "$count" -gt 0 ]; then
    sed -i.bak 's/prevent_destroy[[:space:]]*=[[:space:]]*true/prevent_destroy = false/' "$file"
    rm -f "$file.bak"
    lifted=$((lifted + count))
  fi
done < <(find "$destination" -maxdepth 3 -name '*.tf' -not -path '*/tests/*' -not -path '*/examples/*' -not -path '*/.terraform/*')

if [ "$lifted" -lt 1 ]; then
  echo "error: no prevent_destroy guard found to lift; the harness no longer matches the module" >&2
  exit 1
fi
if grep -rq 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$destination" --include='*.tf' --exclude-dir=tests --exclude-dir=examples; then
  echo "error: a prevent_destroy guard survived in $destination" >&2
  exit 1
fi
echo "lifted $lifted prevent_destroy guard(s) in $destination"
