#!/usr/bin/env bash
set -euo pipefail

catalog_test_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog_test_temp_dir="$(mktemp -d)"
trap 'rm -rf "$catalog_test_temp_dir"' EXIT

catalog_test_fake_bin="$catalog_test_temp_dir/bin"
catalog_test_fake_log="$catalog_test_temp_dir/supabase.log"
mkdir -p "$catalog_test_fake_bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "telemetry=%s command=%s\n" "${SUPABASE_TELEMETRY_DISABLED:-}" "$*" >> "$FAKE_SUPABASE_LOG"' \
  'if [ "$*" = "--version" ]; then' \
  '  printf "%s\n" "${FAKE_SUPABASE_VERSION:-2.109.1}"' \
  '  exit 0' \
  'fi' \
  'if [[ "$*" == *" test db --local "* ]]; then' \
  '  mode="${FAKE_CATALOG_MODE:-pass}"' \
  '  if [ "$mode" = "false_zero" ]; then' \
  '    echo "EPERM: telemetry write failed"' \
  '    exit 0' \
  '  fi' \
  '  file_count=0' \
  '  for argument in "$@"; do' \
  '    if [[ "$argument" == services/supabase/tests/*.sql ]]; then' \
  '      file_count=$((file_count + 1))' \
  '      last_catalog_test="$argument"' \
  '    fi' \
  '  done' \
  '  if [ "$mode" = "fixture_failure" ]; then' \
  '    if [ "$file_count" -gt 1 ]; then' \
  '      printf "/tmp/work/services/supabase/tests/purchase_principal_security.sql (Wstat: 768 (exited 3) Tests: 0 Failed: 0)\n"' \
  '      printf "/tmp/work/services/supabase/tests/../migrations/20260812144948_introduce_stable_purchase_principals.sql (Wstat: 768 (exited 3) Tests: 0 Failed: 0)\n"' \
  '    else' \
  '      printf "psql:%s:42: ERROR: isolated fixture diagnostic\n" "$last_catalog_test"' \
  '    fi' \
  '    exit 1' \
  '  fi' \
  '  printf "Files=%s, Tests=%s, 1 wallclock secs\n" "$file_count" "$file_count"' \
  '  if [ "$mode" != "files_only" ]; then' \
  '    printf "Result: PASS\n"' \
  '  fi' \
  'fi' \
  'exit 0' > "$catalog_test_fake_bin/supabase"
chmod +x "$catalog_test_fake_bin/supabase"

PATH="$catalog_test_fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$catalog_test_fake_log" \
  bash "$catalog_test_script_dir/test_database_catalogs.sh" >/dev/null

if ! grep -q '^telemetry=1 command=' "$catalog_test_fake_log"; then
  echo "Catalog runner must disable Supabase telemetry by default." >&2
  exit 1
fi

: > "$catalog_test_fake_log"

if PATH="$catalog_test_fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$catalog_test_fake_log" \
  FAKE_SUPABASE_VERSION=2.110.0 \
  bash "$catalog_test_script_dir/test_database_catalogs.sh" >/dev/null 2>&1; then
  echo "Catalog runner accepted an unreviewed Supabase CLI version." >&2
  exit 1
fi

if grep -Eq 'command=.*(db push|test db)' "$catalog_test_fake_log"; then
  echo "Catalog runner reached the database after rejecting the CLI version." >&2
  exit 1
fi

if PATH="$catalog_test_fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$catalog_test_fake_log" \
  FAKE_CATALOG_MODE=false_zero \
  bash "$catalog_test_script_dir/test_database_catalogs.sh" >/dev/null 2>&1; then
  echo "Catalog runner accepted a zero exit without passing pg_prove evidence." >&2
  exit 1
fi

if PATH="$catalog_test_fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$catalog_test_fake_log" \
  FAKE_CATALOG_MODE=files_only \
  bash "$catalog_test_script_dir/test_database_catalogs.sh" >/dev/null 2>&1; then
  echo "Catalog runner accepted incomplete pg_prove summary evidence." >&2
  exit 1
fi

: > "$catalog_test_fake_log"
set +e
catalog_failure_output="$({
  PATH="$catalog_test_fake_bin:$PATH" \
    FAKE_SUPABASE_LOG="$catalog_test_fake_log" \
    FAKE_CATALOG_MODE=fixture_failure \
    bash "$catalog_test_script_dir/test_database_catalogs.sh"
} 2>&1)"
catalog_failure_status=$?
set -e

if [ "$catalog_failure_status" -eq 0 ]; then
  echo "Catalog runner converted a failed aggregate run into success." >&2
  exit 1
fi

if ! grep -q \
  'Rerunning failed catalog fixture services/supabase/tests/purchase_principal_security.sql' \
  <<< "$catalog_failure_output" || \
  ! grep -q \
  'Refusing to rerun a catalog path outside the discovered suite: services/supabase/tests/../migrations/20260812144948_introduce_stable_purchase_principals.sql' \
  <<< "$catalog_failure_output" || \
  ! grep -q 'ERROR: isolated fixture diagnostic' \
  <<< "$catalog_failure_output"; then
  echo "Catalog runner did not isolate a failed fixture for actionable diagnostics." >&2
  exit 1
fi

if grep -q 'tests/../migrations' "$catalog_test_fake_log"; then
  echo "Catalog runner executed an out-of-suite path recovered from output." >&2
  exit 1
fi

if [ "$(grep -c 'purchase_principal_security.sql' "$catalog_test_fake_log")" -ne 2 ]; then
  echo "Catalog runner did not execute exactly one aggregate and one isolated fixture call." >&2
  exit 1
fi

printf '%s\n' "test_database_catalogs tests passed."
