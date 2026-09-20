#!/usr/bin/env bash
set -euo pipefail

cutover_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$cutover_test_root"

for cutover_step in \
  'Verify Field Chat admission cutover from database time' \
  'Activate Field Chat admission after all bundles deploy'; do
  cutover_env_flag="$(
    awk -v step="$cutover_step" '
      /- name:/ { active = index($0, "- name: " step) > 0 }
      active && /--allow-env=/ {
        sub(/^[[:space:]]*/, "")
        sub(/[[:space:]]*\\$/, "")
        gsub(/"/, "")
        print
      }
    ' .github/workflows/deploy.yml
  )"
  if [ "$cutover_env_flag" != '--allow-env=MERIAN_DATABASE_URL,GITHUB_SHA,PG*' ]; then
    printf 'Unexpected environment permission scope for %s.\n' "$cutover_step" >&2
    exit 1
  fi

  # Exercise the pinned driver with the actual workflow permission argument.
  # postgres.js connects lazily; deny networking to prove no database is touched.
  deno run --frozen --config services/supabase/functions/deno.json \
    "$cutover_env_flag" --deny-net - <<'TS'
import postgres from "npm:postgres@3.4.7";
const sql = postgres({
  host: "127.0.0.1",
  username: "cutover_permission_test",
  database: "test",
  max: 1,
  connect_timeout: 10,
  idle_timeout: 2,
  max_lifetime: 30,
});
await sql.end();
TS
done

printf '%s\n' 'Field Chat cutover driver permission tests passed.'
