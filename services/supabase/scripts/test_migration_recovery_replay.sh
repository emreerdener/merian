#!/usr/bin/env bash
set -euo pipefail

# Only a private disposable project on fixed loopback ports. Never accepts a
# hosted target, never changes the checkout's config or migration files.
recovery_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
recovery_repository_root="$(cd -- "$recovery_script_dir/../../.." && pwd)"
cd "$recovery_repository_root"
export SUPABASE_TELEMETRY_DISABLED=1
export SUPABASE_AUTH_EXTERNAL_APPLE_SECRET=ci-schema-validation-placeholder
bash "$recovery_script_dir/require_supabase_cli_version.sh"
recovery_workdir="$(mktemp -d "${TMPDIR:-/tmp}/merian-migration-recovery.XXXXXX")"
cleanup() {
  supabase --workdir "$recovery_workdir" stop --no-backup
  rm -rf -- "$recovery_workdir"
}
trap cleanup EXIT
mkdir -p "$recovery_workdir/supabase/migrations"
sed -e "s/^project_id = .*/project_id = \"merian-migration-recovery-$$\"/" \
  -e 's/5432/5543/g' \
  services/supabase/config.toml > "$recovery_workdir/supabase/config.toml"
recovery_missing=20260927220537_hide_reported_explore_posts.sql
for migration in services/supabase/migrations/*.sql; do
  filename="$(basename "$migration")"
  if [[ "$filename" != "$recovery_missing" && "${filename:0:14}" < "20260927230802" ]]; then
    cp "$migration" "$recovery_workdir/supabase/migrations/"
  fi
done
# Reproduce the actual divergent history using real SQL, not migration repair.
supabase --workdir "$recovery_workdir" db start
cp services/supabase/migrations/*.sql "$recovery_workdir/supabase/migrations/"
export SUPABASE_DB_PUSH_URL=postgresql://postgres:postgres@127.0.0.1:55432/postgres
plan() {
  deno run --quiet --frozen --no-prompt \
    --config services/supabase/functions/deno.json \
    --allow-env=SUPABASE_DB_PUSH_URL,PGHOST,PGPORT,PGUSERNAME,PGUSER,PGDATABASE,PGPASSWORD,PGSSL,PGMAX_PIPELINE,PGBACKOFF,PGKEEP_ALIVE,PGPUBLICATIONS,PGTARGET_SESSION_ATTRS,PGAPPNAME,PGTARGETSESSIONATTRS --allow-net=127.0.0.1:55432 \
    --allow-read=services/supabase/migrations \
    services/supabase/scripts/plan_database_migration_push.ts
}
[ "$(plan)" = reviewed-backfill ]
if supabase --workdir "$recovery_workdir" db push --local --dry-run; then
  echo "Expected the ordinary push to reject the out-of-order migration." >&2
  exit 1
fi
supabase --workdir "$recovery_workdir" db push --local --include-all --dry-run
supabase --workdir "$recovery_workdir" db push --local --include-all --yes
[ "$(plan)" = normal ]
# Exercise report filtering and the already-applied accounting contract, plus
# the privileged routine allowlist, after recovery rather than sorted replay.
recovery_output="$recovery_workdir/catalog-results.txt"
supabase --workdir "$recovery_workdir" test db --local \
  "$recovery_repository_root/services/supabase/tests/reported_post_visibility.sql" \
  "$recovery_repository_root/services/supabase/tests/identification_invocation_accounting.sql" \
  "$recovery_repository_root/services/supabase/tests/privileged_routine_security.sql" \
  2>&1 | tee "$recovery_output"
grep -Eq '^Files=3, Tests=[1-9][0-9]*,' "$recovery_output"
grep -Eq '^Result: PASS[[:space:]]*$' "$recovery_output"
echo "Reviewed out-of-order migration replay and catalog checks passed."
