#!/usr/bin/env bash
set -euo pipefail

migration_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migration_repository_root="$(cd -- "$migration_script_dir/../../.." && pwd)"
cd "$migration_repository_root"

shopt -s nullglob

migration_contract_tests=()
for candidate in \
  services/supabase/functions/_tests/*Migration*.test.ts \
  services/supabase/functions/_tests/migration*.test.ts; do
  already_discovered=false
  if [ "${#migration_contract_tests[@]}" -gt 0 ]; then
    for discovered in "${migration_contract_tests[@]}"; do
      if [ "$candidate" = "$discovered" ]; then
        already_discovered=true
        break
      fi
    done
  fi
  if [ "$already_discovered" = false ]; then
    migration_contract_tests+=("$candidate")
  fi
done

if [ "${#migration_contract_tests[@]}" -eq 0 ]; then
  echo "No Supabase migration contract tests were discovered." >&2
  exit 1
fi

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase \
  "${migration_contract_tests[@]}"

printf 'Validated %s discovered Supabase migration contract test file(s).\n' \
  "${#migration_contract_tests[@]}"
