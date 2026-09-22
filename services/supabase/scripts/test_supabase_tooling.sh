#!/usr/bin/env bash
set -euo pipefail

tooling_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tooling_repository_root="$(cd -- "$tooling_script_dir/../../.." && pwd)"
cd "$tooling_repository_root"

shopt -s nullglob

# Most tooling shares the reviewed Edge Function dependency graph. The DTO
# validator is checked separately below with its narrower filesystem
# permissions and dedicated frozen dependency graph.
tooling_sources=()
tooling_tests=()
for source in services/supabase/scripts/*.ts; do
  case "$source" in
    */validate_edge_dtos.ts | */validate_edge_dtos_test.ts | \
      */validate_captured_media_dtos.ts | */validate_captured_media_dtos_test.ts)
      continue
      ;;
  esac
  tooling_sources+=("$source")
done
for test_file in services/supabase/scripts/*_test.ts; do
  case "$test_file" in
    */validate_edge_dtos_test.ts | */validate_captured_media_dtos_test.ts | \
      */identification_evaluation_runner_test.ts)
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
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase,.github/workflows,.github/actions/setup-deno,.github/CODEOWNERS,.github/dependabot.yml,.agents,AGENTS.md,Makefile,README.md,CHANGELOG.md,docs,apps,skills,scripts/check-ios-release-prep.sh,scripts/validate-ios-archive.sh,scripts/validate-ios-critical-test-results.sh,scripts/test-validate-ios-critical-test-results.sh,scripts/config/ios-runtime-audit.json,resources \
  --allow-run=bash \
  "${tooling_tests[@]}"

# The evaluator exercises fsync, exclusive locks, crash recovery and bounded
# asset loading only inside a disposable private directory. No model/network or
# environment permissions are granted. A Deno child proves cross-process locks;
# Git and repository reads allow the actual CLI to fingerprint its source.
evaluation_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/merian-evaluation-test.XXXXXX")"
evaluation_test_directory="$(cd -- "$evaluation_test_directory" && pwd -P)"
trap 'rm -rf -- "$evaluation_test_directory"' EXIT
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_test_directory" --allow-write="$evaluation_test_directory" \
  --allow-run=deno,ln,git \
  services/supabase/scripts/identification_evaluation_runner_test.ts \
  -- "$evaluation_test_directory"

bash services/supabase/scripts/validate_edge_dto_contract.sh
bash services/supabase/scripts/check_secret_shaped_literals.sh

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

printf 'Validated %s standard TypeScript sources, %s standard TypeScript test files, 2 isolated DTO test files, 1 isolated evaluation test file, %s shell sources, and %s shell test file(s).\n' \
  "${#tooling_sources[@]}" \
  "${#tooling_tests[@]}" \
  "${#shell_sources[@]}" \
  "${#shell_tests[@]}"
