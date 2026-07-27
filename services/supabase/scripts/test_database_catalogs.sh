#!/usr/bin/env bash
set -euo pipefail

catalog_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog_repository_root="$(cd -- "$catalog_script_dir/../../.." && pwd)"
cd "$catalog_repository_root"

export SUPABASE_TELEMETRY_DISABLED="${SUPABASE_TELEMETRY_DISABLED:-1}"

shopt -s nullglob

catalog_tests=(services/supabase/tests/*.sql)
if [ "${#catalog_tests[@]}" -eq 0 ]; then
  echo "No Supabase database catalog tests were discovered." >&2
  exit 1
fi

for catalog_test in "${catalog_tests[@]}"; do
  if [ ! -f "$catalog_test" ]; then
    echo "Discovered database catalog test is not a regular file: $catalog_test" >&2
    exit 1
  fi
done

printf 'Discovered %s Supabase database catalog test file(s).\n' \
  "${#catalog_tests[@]}"

supabase --workdir services db push --local

catalog_output="$(mktemp "${TMPDIR:-/tmp}/merian-catalog-tests.XXXXXX")"
trap 'rm -f "$catalog_output"' EXIT

if ! supabase --workdir services test db --local "${catalog_tests[@]}" \
  2>&1 | tee "$catalog_output"; then
  echo "Supabase database catalog tests returned a non-zero status." >&2
  exit 1
fi

expected_file_count="${#catalog_tests[@]}"
if ! grep -Eq \
  "^Files=${expected_file_count}, Tests=[1-9][0-9]*," \
  "$catalog_output" ||
  ! grep -Eq "^Result: PASS[[:space:]]*$" "$catalog_output"; then
  echo "Supabase database catalog tests did not produce complete passing pg_prove evidence." >&2
  exit 1
fi
