#!/usr/bin/env bash
# Fails when a stateful resource loses `lifecycle { prevent_destroy = true }`.
#
# ADR 0008 (2026-09-20 amendment) and ADR 0016 require state buckets, keys and
# lock tables to be protected from Terraform destruction. `terraform test` cannot
# see lifecycle settings, so this static check is the regression guard. It covers
# the root module and modules/legacy-adoption.
set -euo pipefail

cd "$(dirname "$0")/.."

protected='aws_kms_key|aws_kms_replica_key|aws_s3_bucket|aws_dynamodb_table'
minimum=8 # root: 5 (key, replica key, two buckets, lock table); legacy-adoption: 3
checked=0
missing=0

for file in ./*.tf modules/legacy-adoption/*.tf; do
  while IFS= read -r line; do
    case "$line" in
      "ok "*) checked=$((checked + 1)) ;;
      "MISSING "*)
        checked=$((checked + 1))
        missing=$((missing + 1))
        echo "error: ${file#./}: ${line#MISSING } has no lifecycle { prevent_destroy = true }" >&2
        ;;
    esac
  done < <(awk -v re="^resource \"(${protected})\" \"" '
    $0 ~ re { name = $0; sub(/ *\{.*/, "", name); inblock = 1; depth = 0; found = 0 }
    inblock {
      opened = gsub(/\{/, "{"); closed = gsub(/\}/, "}"); depth += opened - closed
      if ($0 ~ /^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true[[:space:]]*$/) found = 1
      if (depth == 0) { print (found ? "ok " : "MISSING ") name; inblock = 0 }
    }' "$file")
done

if [ "$missing" -gt 0 ]; then
  echo "error: $missing stateful resource(s) lost prevent_destroy; ADR 0008 requires it." >&2
  exit 1
fi
if [ "$checked" -lt "$minimum" ]; then
  echo "error: found $checked protected resources, expected at least $minimum; update scripts/check-destroy-guards.sh if resources were renamed or removed on purpose." >&2
  exit 1
fi
echo "destroy guards: $checked stateful resources keep prevent_destroy = true"
