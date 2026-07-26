#!/usr/bin/env bash
set -euo pipefail

tooling_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tooling_repository_root="$(cd -- "$tooling_script_dir/../../.." && pwd)"
cd "$tooling_repository_root"

shopt -s nullglob

# Most tooling shares the reviewed Edge Function dependency graph. The DTO
# validator is checked separately below because its compiler dependency is
# intentionally isolated from deployable function graphs.
tooling_sources=()
tooling_tests=()
for source in services/supabase/scripts/*.ts; do
  case "$source" in
    */validate_edge_dtos.ts | */validate_edge_dtos_test.ts)
      continue
      ;;
  esac
  tooling_sources+=("$source")
done
for test_file in services/supabase/scripts/*_test.ts; do
  case "$test_file" in
    */validate_edge_dtos_test.ts)
      continue
      ;;
  esac
  tooling_tests+=("$test_file")
done

if [ "${#tooling_sources[@]}" -eq 0 ]; then
  echo "No standard Supabase TypeScript tooling sources were discovered." >&2
  exit 1
fi
if [ "${#tooling_tests[@]}" -eq 0 ]; then
  echo "No standard Supabase TypeScript tooling tests were discovered." >&2
  exit 1
fi

deno check --frozen \
  --config services/supabase/functions/deno.json \
  "${tooling_sources[@]}"
deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase,.github/workflows \
  "${tooling_tests[@]}"

dto_validator_env_allowlist="TSC_WATCHFILE,TSC_NONPOLLING_WATCHER,TSC_WATCHDIRECTORY,NODE_INSPECTOR_IPC,VSCODE_INSPECTOR_OPTIONS,TSC_WATCH_POLLINGINTERVAL_LOW,TSC_WATCH_POLLINGINTERVAL_MEDIUM,TSC_WATCH_POLLINGINTERVAL_HIGH,TSC_WATCH_POLLINGCHUNKSIZE_LOW,TSC_WATCH_POLLINGCHUNKSIZE_MEDIUM,TSC_WATCH_POLLINGCHUNKSIZE_HIGH,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_LOW,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_MEDIUM,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_HIGH,NODE_ENV"
dto_validator_read_allowlist="services/supabase/functions/_shared/identify/schema.ts,apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift"

deno test --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-env="$dto_validator_env_allowlist" \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos_test.ts
deno run --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-env="$dto_validator_env_allowlist" \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos.ts

shell_sources=(services/supabase/scripts/*.sh)
shell_tests=(services/supabase/scripts/*_test.sh)
if [ "${#shell_sources[@]}" -eq 0 ]; then
  echo "No Supabase shell tooling sources were discovered." >&2
  exit 1
fi
if [ "${#shell_tests[@]}" -eq 0 ]; then
  echo "No Supabase shell tooling tests were discovered." >&2
  exit 1
fi

for shell_source in "${shell_sources[@]}"; do
  bash -n "$shell_source"
done
for shell_test in "${shell_tests[@]}"; do
  bash "$shell_test"
done

printf 'Validated %s standard TypeScript sources, %s standard TypeScript test files, 1 isolated DTO test file, %s shell sources, and %s shell test file(s).\n' \
  "${#tooling_sources[@]}" \
  "${#tooling_tests[@]}" \
  "${#shell_sources[@]}" \
  "${#shell_tests[@]}"
