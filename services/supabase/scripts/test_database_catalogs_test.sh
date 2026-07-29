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
  '    fi' \
  '  done' \
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

printf '%s\n' "test_database_catalogs tests passed."
