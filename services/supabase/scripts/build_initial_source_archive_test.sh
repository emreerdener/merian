#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository="$(cd "$script_dir/../../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-source-archive-tests.XXXXXX")"
test_root="$(cd "$test_root" && pwd -P)"
trap 'rm -rf -- "$test_root"' EXIT
cd "$repository"
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$repository,$test_root" --allow-write="$test_root" \
  --allow-run=git,ln \
  services/supabase/scripts/build_initial_source_archive_integration.ts -- "$test_root"
