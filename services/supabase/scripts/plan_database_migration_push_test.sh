#!/usr/bin/env bash
set -euo pipefail
migration_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
migration_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-migration-plan-test.XXXXXX")"
trap 'rm -rf -- "$migration_test_dir"' EXIT
mkdir -p "$migration_test_dir/bin"
# Execute the workflow's actual shell block with inert commands. This proves
# failure propagation and option selection without a database or credentials.
awk '
  /- name: Push Database Migrations/ { step=1; next }
  step && /run: \|/ { body=1; next }
  body && /^        if:/ { exit }
  body { sub(/^          /, ""); print }
' "$migration_test_root/.github/workflows/deploy.yml" > "$migration_test_dir/push.sh"
cat > "$migration_test_dir/bin/deno" <<'EOF'
#!/usr/bin/env bash
case "$MIGRATION_TEST_MODE" in
  failure) exit 1 ;;
  *) printf '%s\n' "$MIGRATION_TEST_MODE" ;;
esac
EOF
cat > "$migration_test_dir/bin/supabase" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MIGRATION_TEST_LOG"
if [[ "$*" == *--dry-run* && "$MIGRATION_TEST_DRY_RUN_FAIL" == true ]]; then
  exit 1
fi
EOF
chmod +x "$migration_test_dir/bin/deno" "$migration_test_dir/bin/supabase"
export PATH="$migration_test_dir/bin:$PATH"
export SUPABASE_DB_PUSH_URL=disposable-fixture
export MIGRATION_TEST_LOG="$migration_test_dir/calls"
export MIGRATION_TEST_DRY_RUN_FAIL=false
run_case() {
  export MIGRATION_TEST_MODE="$1"
  : > "$MIGRATION_TEST_LOG"
  bash -e -o pipefail "$migration_test_dir/push.sh" > "$migration_test_dir/output" 2>&1
}
run_case normal
[ "$(wc -l < "$MIGRATION_TEST_LOG" | tr -d ' ')" = 2 ]
! grep -q -- '--include-all' "$MIGRATION_TEST_LOG"
head -1 "$MIGRATION_TEST_LOG" | grep -q -- '--dry-run'
! tail -1 "$MIGRATION_TEST_LOG" | grep -q -- '--dry-run'
run_case reviewed-backfill
[ "$(grep -c -- '--include-all' "$MIGRATION_TEST_LOG")" = 2 ]
head -1 "$MIGRATION_TEST_LOG" | grep -q -- '--dry-run'
! tail -1 "$MIGRATION_TEST_LOG" | grep -q -- '--dry-run'
for mode in failure '' unexpected 'reviewed-backfill --include-seed'; do
  if run_case "$mode"; then
    echo "Invalid or failed preflight unexpectedly passed." >&2
    exit 1
  fi
  [ ! -s "$MIGRATION_TEST_LOG" ]
done
export MIGRATION_TEST_DRY_RUN_FAIL=true
for mode in normal reviewed-backfill; do
  if run_case "$mode"; then
    echo "Failed dry run unexpectedly allowed a push." >&2
    exit 1
  fi
  [ "$(wc -l < "$MIGRATION_TEST_LOG" | tr -d ' ')" = 1 ]
done
echo "Migration push workflow: exact modes and preflight/dry-run failure fences passed."
