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
recovery_workdir=""
cleanup() {
  if [ -n "$recovery_workdir" ]; then
    supabase --workdir "$recovery_workdir" stop --no-backup
    rm -rf -- "$recovery_workdir"
  fi
}
trap cleanup EXIT
plan() {
  deno run --quiet --frozen --no-prompt \
    --config services/supabase/functions/deno.json \
    --allow-env=SUPABASE_DB_PUSH_URL,PGHOST,PGPORT,PGUSERNAME,PGUSER,PGDATABASE,PGPASSWORD,PGSSL,PGMAX_PIPELINE,PGBACKOFF,PGKEEP_ALIVE,PGPUBLICATIONS,PGTARGET_SESSION_ATTRS,PGAPPNAME,PGTARGETSESSIONATTRS --allow-net=127.0.0.1:55432 \
    --allow-read=services/supabase/migrations \
    services/supabase/scripts/plan_database_migration_push.ts
}
run_recovery() {
  local scenario="$1" tip="$2" missing_versions="$3"
  shift 3
  recovery_workdir="$(mktemp -d "${TMPDIR:-/tmp}/merian-migration-recovery.XXXXXX")"
  mkdir -p "$recovery_workdir/supabase/migrations"
  sed -e "s/^project_id = .*/project_id = \"merian-migration-recovery-$$-$scenario\"/" \
    -e 's/5432/5543/g' \
    services/supabase/config.toml > "$recovery_workdir/supabase/config.toml"
  for migration in services/supabase/migrations/*.sql; do
    filename="$(basename "$migration")"
    version="${filename%%_*}"
    if [[ "$version" > "$tip" || " $missing_versions " == *" $version "* ]]; then
      continue
    fi
    cp "$migration" "$recovery_workdir/supabase/migrations/"
  done
  # Reproduce the deployed history using real SQL, never migration repair.
  supabase --workdir "$recovery_workdir" db start
  cp services/supabase/migrations/*.sql "$recovery_workdir/supabase/migrations/"
  export SUPABASE_DB_PUSH_URL=postgresql://postgres:postgres@127.0.0.1:55432/postgres
  [ "$(plan)" = reviewed-backfill ]
  if supabase --workdir "$recovery_workdir" db push --local --dry-run; then
    echo "Expected the ordinary push to reject the out-of-order migrations." >&2
    exit 1
  fi
  supabase --workdir "$recovery_workdir" db push --local --include-all --dry-run
  supabase --workdir "$recovery_workdir" db push --local --include-all --yes
  [ "$(plan)" = normal ]
  # Exercise the actual delayed order, preserving the already-applied tip's
  # behavior and the history rollout's closed defaults.
  local recovery_output="$recovery_workdir/catalog-results.txt"
  local fixtures=()
  for fixture in "$@"; do
    fixtures+=("$recovery_repository_root/services/supabase/tests/$fixture.sql")
  done
  supabase --workdir "$recovery_workdir" test db --local "${fixtures[@]}" \
    2>&1 | tee "$recovery_output"
  grep -Eq "^Files=${#fixtures[@]}, Tests=[1-9][0-9]*," "$recovery_output"
  grep -Eq '^Result: PASS[[:space:]]*$' "$recovery_output"
  cleanup
  recovery_workdir=""
  echo "Reviewed $scenario out-of-order migration replay and catalog checks passed."
}

run_recovery explore 20260927230801 '20260927220537' \
  reported_post_visibility identification_invocation_accounting privileged_routine_security

run_recovery history 20261003063950 \
  '20261002213257 20261002215330 20261002215809 20261003034325 20261003043015 20261003051251 20261003054717 20261003063309' \
  gemini_photo_return observation_analysis_history observation_analysis_reader \
  observation_analysis_append observation_evidence observation_analysis_funding \
  observation_protected_analysis privileged_routine_security
