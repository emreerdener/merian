#!/usr/bin/env bash
set -euo pipefail

catalog_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog_repository_root="$(cd -- "$catalog_script_dir/../../.." && pwd)"
cd "$catalog_repository_root"

export SUPABASE_TELEMETRY_DISABLED="${SUPABASE_TELEMETRY_DISABLED:-1}"

bash "$catalog_script_dir/require_supabase_cli_version.sh"

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

  failed_catalog_count=0
  while IFS= read -r failed_catalog_test; do
    catalog_test_known=false
    for catalog_test in "${catalog_tests[@]}"; do
      if [ "$failed_catalog_test" = "$catalog_test" ]; then
        catalog_test_known=true
        break
      fi
    done
    if [ "$catalog_test_known" != true ] || [ ! -f "$failed_catalog_test" ]; then
      echo "Refusing to rerun a catalog path outside the discovered suite: $failed_catalog_test" >&2
      continue
    fi

    failed_catalog_count=$((failed_catalog_count + 1))
    printf '\nRerunning failed catalog fixture %s for isolated diagnostics.\n' \
      "$failed_catalog_test" >&2
    if supabase --workdir services test db --local "$failed_catalog_test"; then
      echo "The isolated fixture passed after the aggregate failure; inspect it for ordering or shared-state dependence." >&2
    fi
  done < <(
    awk '
      /services\/supabase\/tests\/[^[:space:]]+[.]sql[[:space:]]+[(]Wstat:/ {
        path = $1
        sub(/^.*services\//, "services/", path)
        if (!seen[path]++) print path
      }
    ' "$catalog_output"
  )

  if [ "$failed_catalog_count" -eq 0 ]; then
    echo "No failed fixture path could be recovered from pg_prove output." >&2
  fi
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
