# Supabase Deployment Runbook

Naturebook's long-term Supabase release path is GitHub Actions, while backend
function, RPC, migration, and storage identifiers retain their Merian technical
identity. Local `supabase login` is useful for emergency maintenance, but
production deploys should be repeatable from CI with explicit secrets and
validation.

## Legacy Location-Label Repair

If a scan has exact coordinates but no `semantic_location`, changing an Explore
post’s `location_sharing` cannot produce a label. Preview a targeted repair
with:

```bash
SCAN_ID=<scan-uuid> DRY_RUN=true deno run --allow-net --allow-env \
  services/supabase/scripts/retroactive_geocoding.ts
```

Remove `DRY_RUN=true` to write the resolved label. Omit `SCAN_ID` for the
resumable, paginated full backfill. The script requires `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`, rate-limits Nominatim requests, and updates only
scans that have exact coordinates and a missing semantic location. Existing
database triggers sanitize the scan label and reproject every linked Explore
post while preserving its saved post-level location-sharing choice.

## Production Path

Pushes to `main` that touch Supabase backend or deployment-support paths, plus
manual `workflow_dispatch` runs, execute `.github/workflows/deploy.yml`.
Frontend-only and docs-only commits do not automatically deploy production
backend changes.

The deploy workflow is a backend production gate only. It must not wait for the
iOS simulator startup-safety lane, and the iOS lane must not be treated as proof
that Supabase migrations or Edge Functions deployed. The deployment and iOS
guardrail workflows write a **Workflow context** summary that shows purpose,
trigger, commit, attempt, and changed-file categories so an operator can quickly
tell whether a visible failure belongs to backend deployment, iOS startup
safety, or another independent check. Large commits render at most 100
changed-file bullets and then append a truncation marker.
`test-ci-run-summary.sh` locks that behavior without an early-closing pipeline,
because `set -o pipefail` would otherwise turn an expected SIGPIPE into exit 141
before validation or deployment begins.

The workflow performs the following steps:

1. Writes the workflow context summary and exercises its large-change regression
   test.
2. Uses every third-party action by an immutable reviewed 40-character commit
   SHA, under explicit workflow-level `contents: read` permission.
   `_tests/workflowSecurity.test.ts` enforces those pins and permissions across
   every checked-in workflow, rejects job-scoped secret references, and limits
   `contents: write` to the taxonomy checklist workflow that commits its result.
3. Installs the exact reviewed Deno `2.9.2` runtime and Supabase CLI `2.109.1`.
4. Fails fast if required deployment, RevenueCat, or DwC-A pseudonym credentials
   are missing; if either webhook credential is shorter than 32 characters; if
   the DwC-A key is invalid Base64 or decodes below 32 bytes; or if an
   explicitly configured AI quota HMAC override is shorter than 32 characters.
5. Validates whole-tree Edge Function formatting and lint, then shared runtime
   type checks. Deployment/provider secrets are scoped only to the individual
   steps that consume them; they are not job-wide environment values and are
   never persisted through `GITHUB_ENV`.
6. Confirms exact set parity between function entrypoints and
   `[functions.<name>]` entries, then verifies every function has a current
   generated local `deno.json`, only approved aliased runtime imports, and a
   graph fully represented by the shared frozen `dependencies.lock`; finally it
   type-checks all entrypoints with the exact local config Supabase will
   discover.
7. Runs focused workflow-policy, shared-helper, deployment-planner, AI quota,
   RevenueCat webhook, DwC-A claim/stream/idempotency, and static
   migration-contract tests. The migration execution contract enumerates every
   SQL migration and rejects pipeline-incompatible concurrent index DDL. The
   species-count contract separately requires its explicit
   `BEGIN → LOCK TABLE → final trigger → COMMIT` cutover ordering.
   Source-inspection tests receive explicit read grants because Deno does not
   grant `readTextFile` access merely because a source is in the import graph.
8. Starts a disposable local Postgres instance, applies all pending migrations,
   and runs the account deletion, privileged-routine, AI quota, RevenueCat,
   DwC-A, species-count, public-species-stats, and waitlist pgTAP catalog gates.
   It then invokes the checked-in recursive `deno task test` with an explicit
   database URL, so route-local tests cannot be omitted by a curated CI list and
   database-backed tests cannot silently skip.
9. Builds an affected-function deployment plan from the pushed Git diff. Manual
   dispatch and an unresolvable Git diff safely select the full fleet.
10. Prepares a Postgres connection string for database migrations without
    calling `supabase link`. The workflow prefers a full `SUPABASE_DB_URL`, but
    can also construct a session-pooler URL from `SUPABASE_DB_POOLER_HOST` plus
    `SUPABASE_DB_PASSWORD`.
11. Runs a read-only production `pg_proc.proacl`, `has_function_privilege()`,
    search-path, owner, allowlist, and default-privilege report before any
    database write.
12. Pushes database migrations with `supabase db push --db-url`.
13. Re-runs the production catalog audit in enforcement mode and stops the
    release if any privileged-routine invariant fails.
14. Synchronizes the reviewed `AI_QUOTA_IP_HASH_SECRET` override when present;
    otherwise the functions use a built-in server-only Supabase key.
15. Synchronizes all three required RevenueCat credentials from the GitHub
    `Production` environment to Supabase Edge secrets.
16. Synchronizes the required version-1 DwC-A pseudonym HMAC key from the GitHub
    `Production` environment to Supabase Edge secrets.
17. Deploys the planned functions in bounded batches. A failed batch is retried
    function-by-function, so a transient graph failure cannot restart the whole
    fleet deployment.
18. Smoke-tests the Community Taxonomy status endpoint, the scan-media health
    endpoint, and a dry-run bounded GBIF import with the production service-role
    credential.

Local and CI database rebuilds require Supabase CLI `2.109.0` or newer, and CI
pins `2.109.1`. The migration history itself remains compatible with
fresh-schema statement-pipeline replay: checked-in migrations may not contain
`CREATE INDEX CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, or
`REINDEX ... CONCURRENTLY`. Although migration versions already recorded in
production are skipped by `db push`, fresh databases replay every file. The
historical index files therefore use ordinary idempotent index DDL, which is
fast on an empty rebuild.

For a future index on a populated table where blocking writes is unacceptable,
run `CREATE INDEX CONCURRENTLY IF NOT EXISTS` as a separately reviewed,
supervised operation through a direct session. Verify the resulting index is
valid in `pg_index`, then retain `CREATE INDEX IF NOT EXISTS` in the migration
so clean environments converge without relying on out-of-band state.

Actual GBIF taxonomy imports are intentionally separated into
`.github/workflows/import-community-taxonomy.yml`. The deploy workflow only
smoke-tests a dry run; it does not write taxonomy rows or advance import
cursors.

The deployment subset is computed from the TypeScript import graph rather than a
hand-maintained list. A route-local runtime change selects that route. A
shared-module change selects every function that transitively imports it. A
function-local `deno.json` change selects that function. Changes to
`config.toml`, the root dependency manifest, or the shared lock select the full
fleet because they can affect any bundle. New, deleted, or otherwise
unresolvable shared runtime files also fall back to the full fleet. Docs and
test-only changes select no functions. This preserves shared-helper consistency
without paying for an unconditional full-fleet deployment on every backend
commit.

The graph/configuration test compares the sorted function names discovered from
`functions/*/index.ts` with the sorted `[functions.<name>]` names parsed from
`config.toml`. It deliberately has no numeric fleet-size assertion: adding or
retiring a function changes the fleet naturally, while a missing or stale
configuration entry fails with the differing names. Do not repair this class of
failure by changing a count.

For a planner or graph-parity failure, run:

```bash
deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase \
  services/supabase/scripts/function_dependency_tools_test.ts

deno run --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase \
  services/supabase/scripts/validate_function_dependencies.ts
```

If the reported function is new, add its reviewed `config.toml` entry and
generate its local `deno.json`. If the configuration is stale, follow the
explicit decommission procedure below before removing it. A green parity test
means every configured route has a discoverable graph; it does not authorize a
remote deletion or weaken the route's JWT policy.

Deleting a function directory is intentionally not treated as a zero-function
deploy: the planner fails with an explicit-decommission message because normal
deploys do not prove that the remote route was removed. Retire a function as a
reviewed operational change, confirm all clients and schedules are off the
route, delete the remote function explicitly, and then remove its source and
config. Do not silently rely on source deletion or enable fleet-wide `--prune`
in the routine deployment path.

Database/function releases use an expand/migrate/contract sequence. A migration
in the deploy workflow must be backward-compatible with the function versions
already serving traffic: add nullable columns, new tables, or compatible RPCs
first; deploy readers/writers that understand both shapes; backfill or observe;
then remove old columns, constraints, RPC signatures, or compatibility code in a
later release. The workflow deliberately does not pretend migrations and Edge
bundles switch atomically.

## Privileged Routine ACL Release Gate

Migration `20260723144640_harden_privileged_routine_execution.sql` is the
deny-by-default boundary for public-schema `SECURITY DEFINER` functions. It
revokes historical execution, installs owner-only function defaults for the
`postgres` migration owner, applies an empty `search_path`, and restores only
the exact authenticated/service entries in `internal.privileged_routine_grants`.
Every authenticated entry has a caller-bound check; every service entry calls
`internal.require_service_role()`.

Before a manual production push, run:

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines

export MERIAN_DATABASE_URL='postgresql://...'
deno run --frozen \
  --config services/supabase/functions/deno.json \
  --allow-env --allow-net \
  services/supabase/scripts/audit_privileged_routine_acl.ts \
  --report
```

The report is read-only and intentionally includes every public definer's
identity, owner, language, raw `proacl`, `proconfig`, and effective
`has_function_privilege()` result for `anon`, `authenticated`, and
`service_role`. It also reports default-privilege leaks, API roles with `CREATE`
on `public`, and API roles able to read the private allowlist. Retain this JSON
with the release evidence.

For an independent SQL spot-check, use an owner connection:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    function_row.oid::REGPROCEDURE::TEXT AS signature,
    owner_row.rolname AS owner,
    function_row.proacl,
    function_row.proconfig,
    HAS_FUNCTION_PRIVILEGE(
        'anon',
        function_row.oid,
        'EXECUTE'
    ) AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        function_row.oid,
        'EXECUTE'
    ) AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        function_row.oid,
        'EXECUTE'
    ) AS service_role_can_execute
FROM pg_proc AS function_row
JOIN pg_namespace AS namespace_row
  ON namespace_row.oid = function_row.pronamespace
JOIN pg_roles AS owner_row
  ON owner_row.oid = function_row.proowner
WHERE namespace_row.nspname = 'public'
  AND function_row.prosecdef
ORDER BY signature;

ROLLBACK;
```

After `db push`, enforcement is mandatory:

```bash
MERIAN_DATABASE_URL='postgresql://...' \
  make audit-supabase-privileged-routines
```

Expected invariants are zero `PUBLIC`/`anon` execution, no unlisted
authenticated or service execution, no missing reviewed grants, empty search
paths, caller checks in every exposed routine, owner-safe defaults, no API-role
schema creation, and no non-`postgres` application definer owner. Counts may
change as reviewed RPCs are added; the allowlist, not a hard-coded count, is the
source of truth.

Treat a pre-deploy `PUBLIC` or `anon` finding as an active security incident.
Apply the reviewed hardening migration as soon as an owner connection is
available; do not wait for an Edge release. If post-deploy enforcement fails, do
not deploy functions. Preserve the revocations and default privileges, fix the
allowlist/body/search path with a forward migration, and rerun enforcement.
Never recover availability by granting `PUBLIC`, `anon`, or a blanket
`authenticated` grant. Any emergency out-of-band ACL correction must be captured
immediately in an idempotent repository migration so the next rebuild cannot
reintroduce drift.

The repository migration role cannot alter a Supabase-managed owner's default
privileges. If the audit finds a public application definer owned by
`supabase_admin` or another role, stop the release and resolve ownership or that
creator's defaults with the appropriate platform authority; do not exempt it
from the audit.

### Disposable Catalog-Gate Failure Triage

A successful `supabase db push --local` proves that the migration DDL replayed;
it does not prove that every SQL statement embedded in a PL/pgSQL routine can be
planned. The next workflow step deliberately runs `plpgsql_check` over every
public application `SECURITY DEFINER` routine and trigger.

When this gate fails, use the first PostgreSQL exception as the root cause. The
ordinary-routine and trigger diagnostics include the exact signature, source
line, SQLSTATE, statement, query, detail, and hint. The later pg_prove output
(`Dubious`, `Bad plan`, or `planned 1 tests but ran 0`) only means the exception
aborted the pgTAP block before its planned assertion.

For SQLSTATE `42883`, compare both the function name and argument types with the
actual `pg_proc` identity. An explicit schema does not repair a misspelling or
select an unavailable overload. The AI quota advisory key intentionally calls
`pg_catalog.HASHTEXTEXTENDED(text, bigint)` and casts its seed as `0::BIGINT`;
`aiQuotaMigrationContract.test.ts` prevents either part from drifting.

Do not schema-qualify PostgreSQL conditional expressions as though they were
entries in `pg_proc`. For example, `COALESCE` is syntax, so
`pg_catalog.COALESCE(...)` fails static validation with SQLSTATE `42883`. For an
idempotent insert using
`ON CONFLICT DO NOTHING RETURNING TRUE INTO event_inserted`, use
`event_inserted IS NOT TRUE` to recognize the null left when no row is returned.

If any catalog fixture instead fails a `public.users` identity constraint,
update the owner-only fixture to include `public_username`,
`public_author_name`, and `public_identity_source`. Direct table inserts bypass
the Auth trigger that normally derives those fields. A fixture username must
pass `public.is_valid_public_username(...)`: it is currently 3–24 lowercase
characters, starts with a letter, ends with an alphanumeric character, contains
no `__`, and is not reserved. Keep it deterministic and unique. Do not relax a
production identity constraint to make a fixture pass.

Repair the routine or fixture, preserve the ACL/search-path/constraint checks,
and rerun the same disposable-database sequence:

```bash
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/ai_quota_security.sql \
  services/supabase/tests/revenuecat_webhook_security.sql \
  services/supabase/tests/species_observation_stats_security.sql
```

## Authoritative AI Quota Release Gate

Migration `20260723160229_enforce_server_ai_quotas.sql` must land before the
Edge bundles that import `_shared/aiQuota.ts`. It adds only compatible columns,
private tables, RPCs, grants, and triggers, so the previously deployed functions
continue serving during the migration. The new functions fail closed until both
RPCs exist. `AI_QUOTA_IP_HASH_SECRET` is an optional key-separation override;
without it, Edge uses the built-in server-only Supabase secret/service-role key
with a quota-specific HMAC domain.

Preflight:

```bash
# Optional: generate a dedicated override. If used, store it as the GitHub
# Production environment secret AI_QUOTA_IP_HASH_SECRET. Never paste it into
# source, docs, or logs.
openssl rand -hex 32

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,.github/workflows/deploy.yml \
  services/supabase/functions/_shared/aiQuota_test.ts \
  services/supabase/functions/_shared/entitlement_test.ts \
  services/supabase/functions/_tests/aiQuotaCoverage.test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/aiQuotaMigrationContract.test.ts

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/ai_quota_security.sql
```

After the production migration and before treating the Edge deploy as healthy,
run these read-only checks with an owner connection:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    routine.oid::REGPROCEDURE::TEXT AS signature,
    routine.proacl,
    HAS_FUNCTION_PRIVILEGE('anon', routine.oid, 'EXECUTE')
        AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE('authenticated', routine.oid, 'EXECUTE')
        AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE('service_role', routine.oid, 'EXECUTE')
        AS service_role_can_execute,
    routine.proconfig
FROM pg_proc AS routine
WHERE routine.oid IN (
    'public.reserve_ai_quota(uuid,text,uuid,text)'::REGPROCEDURE,
    'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)'::REGPROCEDURE
)
ORDER BY signature;

SELECT
    attribute.attname AS column_name,
    HAS_COLUMN_PRIVILEGE(
        'anon',
        'public.users',
        attribute.attname,
        'INSERT'
    ) AS anon_can_insert,
    HAS_COLUMN_PRIVILEGE(
        'anon',
        'public.users',
        attribute.attname,
        'UPDATE'
    ) AS anon_can_update,
    HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        attribute.attname,
        'INSERT'
    ) AS authenticated_can_insert,
    HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        attribute.attname,
        'UPDATE'
    ) AS authenticated_can_update
FROM pg_attribute AS attribute
WHERE attribute.attrelid = 'public.users'::REGCLASS
  AND attribute.attnum > 0
  AND NOT attribute.attisdropped
  AND (
      HAS_COLUMN_PRIVILEGE(
          'anon',
          'public.users',
          attribute.attname,
          'INSERT'
      )
      OR HAS_COLUMN_PRIVILEGE(
          'anon',
          'public.users',
          attribute.attname,
          'UPDATE'
      )
      OR HAS_COLUMN_PRIVILEGE(
          'authenticated',
          'public.users',
          attribute.attname,
          'INSERT'
      )
      OR (
          attribute.attname NOT IN ('default_geoprivacy', 'marketing_opt_in')
          AND HAS_COLUMN_PRIVILEGE(
              'authenticated',
              'public.users',
              attribute.attname,
              'UPDATE'
          )
      )
  )
ORDER BY attribute.attnum;

SELECT
    operation,
    effective_plan,
    model,
    allowed,
    enabled,
    policy_version,
    daily_bucket,
    daily_limit,
    user_window_seconds,
    user_window_limit,
    ip_window_seconds,
    ip_window_limit
FROM internal.ai_quota_policies
ORDER BY operation, effective_plan;

SELECT
    state,
    operation,
    COUNT(*) AS reservations,
    MIN(updated_at) AS oldest,
    MAX(updated_at) AS newest
FROM internal.ai_quota_reservations
WHERE updated_at >= NOW() - INTERVAL '1 hour'
GROUP BY state, operation
ORDER BY operation, state;

ROLLBACK;
```

Expected routine ACLs are `false`, `false`, `true` for
anon/authenticated/service-role, with `search_path=""`. The unexpected
`public.users` column-ACL query must return zero rows. The policy query must
return all 30 reviewed rows. Shortly after deploy, normal traffic should create
`committed` reservations; provider failures create `failed` rows without
refunding counters, and cache/no-op or expired pre-provider paths create
`refunded` rows. `reserved` rows are cost-safe because their counters remain
consumed, but none should remain beyond the ten-minute lease plus one
five-minute cleanup interval. A growing older population indicates cron,
settlement, or database availability problems.

Monitor Edge logs for `ai_quota_reservation_failed`,
`ai_quota_reservation_invalid_response`, and `ai_quota_finalization_failed`, and
API responses for:

- elevated `503 ai_entitlement_unavailable` (database/profile/policy incident);
- elevated `429 ai_user_rate_limit_exceeded` or `ai_ip_rate_limit_exceeded`
  (automation or ceilings too low);
- unexpected `409 ai_request_already_completed` (client reused a key for a new
  logical request);
- provider traffic without a corresponding reservation (release blocker).

Do not recover availability by granting the RPCs to `authenticated`, lowering
caller checks, restoring a process-local cache, or treating database failure as
trial Pro. If a partial function deployment leaves an older unguarded provider
route live, stop the release and fail provider access closed (including
temporarily removing the provider secret if necessary) until every affected
route is on the guarded bundle. Fix forward; keep the quota schema and durable
reservation evidence.

### Incremental Species-Count Release Gate

Migration `20260724222838_optimize_species_count_trigger.sql` is database-only.
It replaces the `unified_species_count_sync` row trigger with the private
`internal.user_species_scan_counts` ledger and four statement-level transition
triggers. No Edge Function deployment or new secret is required.

The migration deliberately takes `SHARE ROW EXCLUSIVE` on `public.scans`.
Existing writes finish first; new scan inserts, updates, deletes, and cascading
owner/species changes wait while one grouped backfill runs, projected totals are
repaired, and the trigger set is swapped. The lock is held until the migration
transaction commits. The migration file must retain its explicit `BEGIN` before
`LOCK TABLE` and final `COMMIT`; PostgreSQL rejects a table lock outside a
transaction block, and removing either boundary also destroys the atomic cutover
guarantee. Before production deployment, inspect the planner estimate and
physical size:

```sql
SELECT
    relation.reltuples::BIGINT AS estimated_scan_rows,
    pg_size_pretty(
        pg_total_relation_size('public.scans'::REGCLASS)
    ) AS total_scan_storage
FROM pg_class AS relation
WHERE relation.oid = 'public.scans'::REGCLASS;
```

For a materially larger table than the local/preview fixtures, deploy in a
low-write window and watch active transactions before the push. Do not remove
the lock to make the migration appear non-blocking: an unlocked backfill leaves
a cutover interval where committed scan writes are absent from the ledger.

Run the complete local contract before deployment:

```bash
make validate-supabase-migrations
supabase --workdir services db start
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/species_count_trigger_security.sql
```

The dictionary-delete case forces the deferred ledger foreign key after the
scan's `ON DELETE SET NULL` transition. Its constraint name must remain
schema-qualified as `internal.user_species_scan_counts_species_id_fkey`; an
unqualified name is not visible when the fixture's search path excludes
`internal`.

Workflow run 1458 failed during disposable `supabase db start` with
`SQLSTATE 25P01: LOCK TABLE can only be used in transaction blocks`. Treat that
signature as an explicit-boundary regression: restore `BEGIN` before the scan
lock and keep `COMMIT` after the final trigger. Do not remove the lock, split
the backfill from the trigger swap, or run `supabase migration repair`.
Disposable database validation runs before the production `db push`, so this
failure does not create a hosted migration-history entry; fix the unapplied
migration file and rerun the workflow.

After production migration history confirms the file, use a direct read-only
database session—not PostgREST—to verify the trigger catalog:

```sql
SELECT
    trigger_row.tgname,
    (trigger_row.tgtype::INTEGER & 1) = 0 AS statement_level,
    trigger_row.tgoldtable,
    trigger_row.tgnewtable
FROM pg_trigger AS trigger_row
JOIN pg_class AS relation_row
  ON relation_row.oid = trigger_row.tgrelid
JOIN pg_namespace AS namespace_row
  ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND relation_row.relname = 'scans'
  AND NOT trigger_row.tgisinternal
  AND trigger_row.tgname LIKE 'sync_user_species_counts_after_%'
ORDER BY trigger_row.tgname;
```

Expected: four rows, every `statement_level` is true, insert/delete/update have
their documented transition aliases, and truncate has no transition alias.
`unified_species_count_sync` and `public.sync_global_species_count()` must be
absent.

Then verify the public projection against the private ledger:

```sql
WITH ledger_totals AS (
    SELECT
        users.id AS user_id,
        COUNT(counts.species_id)::INTEGER AS species_count
    FROM public.users AS users
    LEFT JOIN internal.user_species_scan_counts AS counts
      ON counts.user_id = users.id
    WHERE users.id
        <> '00000000-0000-0000-0000-000000000000'::UUID
    GROUP BY users.id
)
SELECT COUNT(*) AS projection_mismatches
FROM public.users AS users
JOIN ledger_totals AS totals
  ON totals.user_id = users.id
WHERE users.total_species_discovered
    IS DISTINCT FROM totals.species_count;

SELECT
    (
        SELECT COALESCE(SUM(counts.scan_count), 0)
        FROM internal.user_species_scan_counts AS counts
    ) AS ledger_assigned_scans,
    (
        SELECT COUNT(*)
        FROM public.scans AS scans
        WHERE scans.species_id IS NOT NULL
          AND scans.user_id
              <> '00000000-0000-0000-0000-000000000000'::UUID
    ) AS source_assigned_scans;
```

Expected: zero projection mismatches and equal assigned-scan totals. The second
query reads the scan index/table and should be run once during the same
low-traffic verification window. Also confirm API roles have neither table
access nor EXECUTE on the five internal routines; the disposable pgTAP test owns
the exact signatures.

If the migration fails before commit, PostgreSQL rolls back the table, backfill,
function, and trigger changes together. If a post-commit invariant is nonzero,
stop the release and write a forward repair migration that takes the same scan
lock and rebuilds the ledger. Never run an unlocked manual backfill, enable the
legacy row trigger alongside the new triggers, grant API access to the ledger,
or edit `total_species_discovered` independently.

### Public Species Observation Stats Release Gate

Migration `20260724170709_harden_species_observation_stats.sql` must land before
the hardened `species-observation-stats` bundle. The migration adds private rate
counters, fenced population leases, and four service-only RPCs without breaking
the older cache table. The IP preflight is consumed before optional user-token
validation, so invalid-token floods are bounded before reaching Supabase Auth.
No new production secret is required: daily purpose-separated IP HMACs use the
built-in server-only Supabase secret/service key. The iOS change may ship after
the backend; it adds the user bucket by sending the existing valid session with
its GET.

Preflight:

```bash
deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/config.toml \
  services/supabase/functions/_shared/clientAddress_test.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/species-observation-stats/db.test.ts \
  services/supabase/functions/species-observation-stats/security.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/species_observation_stats_security.sql

xcrun swiftc -frontend -parse \
  apps/ios/Merian/Core/Network/MerianNetworkClient.swift \
  apps/ios/Merian/Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift \
  apps/ios/MerianTests/Features/SpeciesDictionary/SpeciesDictionaryTests.swift
swiftlint lint --strict \
  apps/ios/Merian/Core/Network/MerianNetworkClient.swift \
  apps/ios/Merian/Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift \
  apps/ios/MerianTests/Features/SpeciesDictionary/SpeciesDictionaryTests.swift
```

After production deploy, request one known dictionary UUID/name pair. Expect
`200`, `schema_version: 2`, the canonical name, and either a positive
`source.inaturalist_taxon_id` or a bounded `no_data`/`unavailable` result.
Request the same UUID with a forged name and expect
`404 species_stats_species_not_found` with no iNaturalist call. A burst past a
reviewed limit must return `429` with `Retry-After`. A compatibility POST body
larger than 4 KiB must return `413` without attempting JSON allocation beyond
that bound.

Confirm public traffic still reaches the function through the hosted Supabase
gateway. If a custom proxy or CDN is introduced, it must overwrite `x-real-ip`,
`cf-connecting-ip`, and `x-forwarded-for`; forwarding caller-supplied values
would make the IP rate boundary untrustworthy. A request without a trusted
address deliberately joins the shared `unavailable` bucket.

The iOS client must reject malformed UUIDs and empty/overlong names before
networking. It must also reject—and not memoize—a response below schema version
2 or whose returned UUID/normalized scientific name differs from the request.
Inspect a successful response and confirm `Vary: Accept-Encoding` does not
include Authorization; the body is public and identity-independent. Error
responses must instead remain `Cache-Control: private, no-store` and vary by
Authorization.

Use an owner connection for the read-only catalog check:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    checks.routine_signature,
    HAS_FUNCTION_PRIVILEGE(
        'anon',
        checks.routine_signature,
        'EXECUTE'
    ) AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        checks.routine_signature,
        'EXECUTE'
    ) AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        checks.routine_signature,
        'EXECUTE'
    ) AS service_role_can_execute
FROM (
    VALUES
        ('public.preflight_species_observation_stats_request(text)'),
        ('public.authorize_species_observation_stats_request(uuid,text,uuid)'),
        ('public.claim_species_observation_stats_population(uuid,uuid,text)'),
        ('public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)')
) AS checks(routine_signature)
ORDER BY checks.routine_signature;

SELECT
    COUNT(*) FILTER (
        WHERE lease_expires_at > NOW()
    ) AS active_population_leases,
    COUNT(*) FILTER (
        WHERE lease_expires_at <= NOW()
    ) AS expired_population_leases,
    MIN(lease_expires_at) AS oldest_expiry,
    MAX(lease_expires_at) AS newest_expiry
FROM internal.species_observation_stats_population_leases;

SELECT
    scope_type,
    bucket,
    COUNT(*) AS counter_rows,
    MAX(request_count) AS peak_count
FROM internal.species_observation_stats_rate_counters
WHERE updated_at > NOW() - INTERVAL '15 minutes'
GROUP BY scope_type, bucket
ORDER BY scope_type, bucket;

SELECT
    species_id,
    scientific_name,
    status,
    fetched_at,
    expires_at,
    updated_at,
    pg_catalog.ROUND(
        EXTRACT(
            EPOCH FROM (pg_catalog.NOW() - fetched_at)
        )::NUMERIC / 86400,
        2
    ) AS payload_age_days,
    provider_error
FROM public.species_observation_stats_cache
ORDER BY updated_at DESC
LIMIT 25;

ROLLBACK;
```

Expected ACLs are `false`, `false`, `true` for all four routines. Monitor Edge
logs and API metrics for `species_stats_rate_limited`,
`species_stats_refresh_in_progress`, `species_stats_unavailable`, provider
timeouts, oversized request/provider responses, and superseded lease
finalization. Expired lease rows older than the ten-minute cleanup horizon
indicate a cron or deployment problem.

The local pgTAP fixture deliberately expires a positive row and finalizes a
failed refresh. It must retain the old payload and `fetched_at`, mark both cache
and payload `stale`, record the new provider error, remove the lease, and set a
roughly five-minute retry backoff. It separately proves an exact taxon miss
receives the 24-hour `no_data` TTL. In production, recent `stale` rows with an
older `fetched_at`, a newer `updated_at`, and a short `expires_at` are therefore
expected during a provider incident; an empty `partial` row is not.

Do not recover an incident by restoring `taxon_name`, raising/removing the
global cold-population ceiling, granting internal tables to API roles, writing
the cache directly, or making finalization ignore the lease token. Serve stale
positive data, preserve negative caching, and fix forward.

### Durable Account Deletion Release Gate

Migrations `20260725030308_durable_account_deletion.sql`,
`20260725035737_repair_tombstone_profile_seed.sql`,
`20260725041308_ownerless_account_deletion_tombstones.sql`, and
`20260725052337_enforce_account_storage_erasure.sql`, plus `safe-delete`,
`reconcile-account-deletions`, `generate-upload-urls`, and
`replay-scan-ingestion`, form one release unit. No new secret is required: the
reaper uses the existing Supabase service-role and R2 values.

The `20260725035737` file is an explicit executable no-op. It is a compatibility
bridge for production run 1461, where its superseded public-only sentinel insert
failed the existing profile-to-Auth foreign key before the migration version was
recorded. The no-op ensures the failed timestamp is recorded without mutating
data. The following forward migration converges both production and any
preview/local catalog that happened to accept the earlier sentinel. Together the
migrations:

- creates private `internal.account_deletion_jobs`;
- blocks public-profile recreation while an account-deletion job is active;
- deduplicates `pending_storage_deletions` and adds one-row-per-user
  idempotency;
- makes `scans.user_id` nullable under a validated constraint that allows only
  tombstoned ownerless rows;
- migrates any legacy all-zero-owner scans to ownerless tombstones, clears exact
  coordinates/elevation and intervention notes, and removes the invalid
  public-only sentinel;
- fails closed if an operator previously manufactured an all-zero Auth user,
  which must be reviewed and removed through Auth Admin before retry;
- normalizes `public.users.id → auth.users.id` as a validated
  `ON DELETE RESTRICT` foreign key, blocking Auth-first deletion without
  creating an Auth identity;
- excludes tombstoned scans from the broad anonymous scans policy;
- removes all synthetic-profile behavior from `apply_user_tombstone`;
- excludes the public profile's own Auth foreign key from generic Ghost
  reparenting;
- clears every compatibility media URL, captured-media reference, semantic
  location, device locale/time-zone context, exact location/elevation, free-form
  note, and custom tag on retained tombstones;
- upgrades the storage marker to a five-prefix cursor-persisted sweep, capped at
  four 50-key pages per Edge invocation, followed by a delayed 25-hour
  verification sweep;
- prevents new signed uploads while deletion is active;
- adds `storage_pending` and requires completed storage before `auth_pending`;
- installs service-only account and storage claim/advance/failure RPCs; and
- schedules `reconcile_account_deletions_every_five_minutes`.

The ownerless migration takes bounded `SHARE ROW EXCLUSIVE` locks in Auth →
scans → public-profile order. A lock timeout is a safe deployment failure; retry
the unchanged migration after the conflicting transaction finishes.

Run before deployment:

```bash
cd services/supabase/functions
deno task test
cd ../../..

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/tests/account_deletion_security.sql,services/supabase/config.toml,.github/workflows/deploy.yml \
  services/supabase/functions/_tests/safeDelete.test.ts \
  services/supabase/functions/_tests/accountDeletionCoverage.test.ts \
  services/supabase/functions/_tests/accountDeletionMigrationContract.test.ts \
  services/supabase/functions/safe-delete/storageWorker_test.ts

make validate-supabase-migrations
make test-supabase-privileged-routines
```

The production workflow applies migrations before Edge bundles. During that
short interval the previous `safe-delete` bundle still has its historical
Auth-first behavior; avoid deliberately exercising account deletion until both
new functions are deployed. The `functions/deno.json` permission correction is a
deployment control-path change and deliberately selects the complete function
fleet, ensuring the current `safe-delete`, `reconcile-account-deletions`, and
`replay-scan-ingestion` bundles are installed after run 1461 stopped before Edge
deployment.

After deployment, confirm the relational invariants, cron, and aggregate state
without printing user identifiers:

```sql
SELECT
    constraint_row.conname,
    constraint_row.convalidated,
    constraint_row.confdeltype = 'r' AS blocks_auth_first_delete
FROM pg_catalog.pg_constraint AS constraint_row
WHERE constraint_row.contype = 'f'
  AND constraint_row.conrelid = 'public.users'::REGCLASS
  AND constraint_row.confrelid = 'auth.users'::REGCLASS;

SELECT
    attribute.attnotnull = FALSE AS scan_owner_is_nullable,
    constraint_row.convalidated AS ownerless_check_validated
FROM pg_catalog.pg_attribute AS attribute
JOIN pg_catalog.pg_constraint AS constraint_row
  ON constraint_row.conrelid = attribute.attrelid
 AND constraint_row.conname = 'scans_ownerless_requires_tombstone_check'
WHERE attribute.attrelid = 'public.scans'::REGCLASS
  AND attribute.attname = 'user_id'
  AND NOT attribute.attisdropped;

SELECT
    COUNT(*) FILTER (
        WHERE user_id IS NULL AND is_tombstoned IS NOT TRUE
    ) AS invalid_ownerless_scans,
    COUNT(*) FILTER (
        WHERE user_id =
            '00000000-0000-0000-0000-000000000000'::UUID
    ) AS legacy_sentinel_scans
FROM public.scans;

SELECT COUNT(*) AS invalid_sentinel_profiles
FROM public.users
WHERE id = '00000000-0000-0000-0000-000000000000'::UUID;

SELECT COUNT(*) AS invalid_synthetic_auth_users
FROM auth.users
WHERE id = '00000000-0000-0000-0000-000000000000'::UUID;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'reconcile_account_deletions_every_five_minutes';

SELECT
    status,
    COUNT(*) AS jobs,
    MAX(attempt_count) AS max_attempt_count,
    MIN(next_attempt_at) AS oldest_next_attempt
FROM internal.account_deletion_jobs
GROUP BY status
ORDER BY status;

SELECT
    status,
    phase,
    COUNT(*) AS jobs,
    MAX(attempt_count) AS max_attempt_count,
    MIN(next_attempt_at) AS oldest_next_attempt
FROM public.pending_storage_deletions
GROUP BY status, phase
ORDER BY status, phase;
```

Expected: at least one validated restrictive profile/Auth foreign key, a
nullable scan owner plus validated ownerless check, zero invalid ownerless
scans, zero legacy sentinel scans/profiles, zero synthetic all-zero Auth users,
and the active cron.

Smoke-test with a staging-only account that owns at least one scan. Confirm:

1. `/safe-delete` returns `200 completed` or `202 pending`;
2. the retained scan has `user_id IS NULL` and `is_tombstoned = true`;
3. all compatibility media URLs and structured media references are empty, and
   its exact location/elevation, semantic location, device context, notes, and
   custom tags are null/empty;
4. anonymous table access does not return the tombstoned scan;
5. the original public profile is absent and one storage job exists with all
   five canonical prefixes;
6. recreating the original public profile while the job is active is rejected;
7. a new upload-signing request is rejected while deletion is active;
8. Auth remains present through `storage_pending`, and disappears only after an
   empty delayed verification pass permits `auth_pending`; and
9. the terminal job is `completed` with `user_id IS NULL`.

Alert on `account_deletion_attempt_deferred`,
`account_deletion_reconciliation_deferred`, `account_storage_erasure_deferred`,
overdue active account/storage jobs, and repeated attempt growth. Repair the
dependency and let the reaper retry. Never recover a `pending` or
`storage_pending` job by deleting Auth manually. A legacy Auth-first incident
can be placed into the durable pipeline only after an operator verifies the
recorded UUID and invokes `request_account_deletion` through a reviewed
service-role or owner session.

Do not roll back by dropping the private table, unique outbox index, or cron;
that would discard deletion intent. Fix forward while keeping the reaper
available.

#### Run 1461 partial-production recovery

Run 1461 committed the species-count, export, and durable deletion-state
migrations individually, then failed before recording `20260725035737` and
before deploying Edge Functions. Until a corrective workflow succeeds, do not
exercise account deletion in production.

On the next push:

1. Supabase should skip the three already-recorded migrations.
2. It should execute and record the no-op `20260725035737` bridge.
3. It should apply `20260725041308` and the later account/storage hardening
   migration, then deploy the complete function fleet.
4. Run the invariant queries and staging-only smoke test above.

Do not mark the failed version applied with migration repair, insert an all-zero
`auth.users` row, drop/disable the production foreign key, or edit one of the
already-applied migrations. If the forward migration encounters a lock timeout,
stop deliberate account-deletion testing, allow the conflicting transaction to
finish, and rerun the workflow unchanged.

`legacy_auth_sentinel_requires_operator_removal` means an out-of-band workaround
created the forbidden all-zero Auth principal. Verify that exact reserved UUID
has no legitimate identity or sessions, remove it through the Supabase Auth
Admin API/dashboard, and rerun. Do not delete arbitrary Auth rows from SQL.

Workflow run 1460 separately caught two disposable-catalog test regressions:
direct `public.users` fixtures must first create matching transactional Auth
fixtures, and the deferred species-ledger foreign key must be referenced as
`internal.user_species_scan_counts_species_id_fkey`. Keep both protections in
the complete disposable database gate.

### Darwin Core Export Release Gate

Migrations `20260724230849_harden_dwca_export_jobs.sql`,
`20260725052339_bound_dwca_export_work.sql`, and
the ordered source-bound pair
`20260725175312_bound_dwca_export_source_bytes.sql` /
`20260725180321_validate_dwca_export_source_bounds.sql`, and
`20260726025103_snapshot_dwca_export_sources.sql` must land with
`request-export-dwca` and the resumable `export-dwca` bundle. Before the first
deployment, generate a dedicated version-1 pseudonym key:

```bash
openssl rand -base64 32
```

Store the output as `DWCA_PSEUDONYM_HMAC_KEY_V1` in the GitHub `Production`
environment. Do not reuse a JWT secret, service-role key, R2 credential, Resend
key, or an example value. CI requires valid Base64 decoding to at least 32 bytes
and synchronizes the exact value to Supabase before function deployment.

The public request route queues personal exports only. Do not expose global
scope to iOS or ordinary authenticated callers; repository-wide exports require
a reviewed internal workflow. Every job pins immutable canonical budgets: 5,000
CSV rows and an 8 MiB archive by default, with hard database ceilings of 20,000
rows and 16 MiB.

The current worker does not finish a complete export in `waitUntil`. A
minute-level cron resumes one due job, and each invocation performs one
occurrence page, one multimedia page, assembly, or delivery. The database caps
data pages at 100 scans and 256 KiB of serialized source under the active claim;
validated row checks bound media, interactions, and selected taxonomy before
the read. Job insertion examines at most the canonical row budget plus one
lookahead and fixes one scan-ID membership set and three SHA-256 revision
fingerprints per scan for both CSV phases. A later scan is excluded; a
changed/deleted revision terminates the job rather than mixing source states.
Terminal jobs purge those membership rows. A fixed-capacity incremental encoder
caps CSV output at 512 KiB. CSV pages are stored as claim-token-fenced R2 chunks
and committed to a durable cursor/manifest with cumulative budgets. These phase
and byte boundaries are the production memory/time contract.

Before the database push, run this owner-only, read-only legacy-row preflight.
It must return zero rows. Repair invalid source values through the canonical
data path; do not skip validation or weaken the limits:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

WITH violations AS (
    SELECT
        'public.scans'::TEXT AS source_table,
        scans.id::TEXT AS record_id
    FROM public.scans AS scans
    WHERE CARDINALITY(scans.image_storage_urls) > 24
       OR EXISTS (
           SELECT 1
           FROM UNNEST(scans.image_storage_urls) AS media(url)
           WHERE media.url IS NULL
              OR OCTET_LENGTH(media.url) > 4096
              OR media.url ~ '[[:cntrl:]]'
       )
       OR (
           scans.ecological_interactions IS NOT NULL
           AND (
               CARDINALITY(scans.ecological_interactions) > 10
               OR EXISTS (
                   SELECT 1
                   FROM UNNEST(scans.ecological_interactions)
                       AS interactions(value)
                   WHERE interactions.value IS NULL
                      OR OCTET_LENGTH(interactions.value) > 2048
                      OR interactions.value ~ '[[:cntrl:]]'
               )
           )
       )
    UNION ALL

    SELECT
        'public.species_dictionary',
        species.id::TEXT
    FROM public.species_dictionary AS species
    WHERE OCTET_LENGTH(species.scientific_name) > 1024
       OR OCTET_LENGTH(species.kingdom) > 512
       OR OCTET_LENGTH(species.phylum) > 512
       OR OCTET_LENGTH(species.class) > 512
       OR OCTET_LENGTH(species."order") > 512
       OR OCTET_LENGTH(species.family) > 512
       OR OCTET_LENGTH(species.genus) > 512
       OR (
           species.iucn_red_list_status IS NOT NULL
           AND OCTET_LENGTH(species.iucn_red_list_status) > 128
       )
)
SELECT
    violations.source_table,
    COUNT(*) AS violation_count,
    (ARRAY_AGG(violations.record_id ORDER BY violations.record_id))[1:10]
        AS sample_ids
FROM violations
GROUP BY violations.source_table
ORDER BY violations.source_table;

ROLLBACK;
```

Because production migrations precede function bundles, applying the migration
creates a private two-hour legacy payload deadline. Only jobs created in that
finite cohort receive canonical row hints understood by the previous bundle.
Pre-existing nonterminal jobs remain eligible to finish under the same bounded
compatibility path but do not receive a new webhook merely because the migration
landed. After the deadline, new webhook bodies contain `job_id` only and the
database rejects direct processing without a claim. The hardened bundle ignores
the hints at all times. If function deployment has not converged by the
deadline, export intake fails closed: finish or roll forward the function
deployment and let affected jobs reach the watchdog/retry path. Do not extend
the private deadline or weaken the claim trigger out of band. Once a new worker
has claimed a cohort job, the transition trigger rejects an old bundle's
redundant `processing` write, raw failure, and staged-result overwrite; terminal
result fields are immutable. The previous bundle did not inspect update errors
reliably, so do not manually redeliver a cohort job while an old invocation may
still be running. The new worker never claims an unclaimed cohort row already
marked `processing`; let the 30-minute watchdog fail it and then issue a new
request.

The checked-in migration uses ordinary idempotent index DDL because fresh-schema
pipeline replay cannot run `CREATE INDEX CONCURRENTLY`. Before the production
push, inspect `pg_stat_user_tables.n_live_tup` for `public.scans`. If an
ordinary build would hold the scan-write lock for an unacceptable interval, use
an owner connection in a supervised pre-deploy window:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scans_dwca_personal_keyset
    ON public.scans (user_id, id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scans_dwca_global_keyset
    ON public.scans (id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated'
      AND geoprivacy = 'open';

SELECT
    index_class.relname,
    index_row.indisvalid,
    index_row.indisready
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS index_class
  ON index_class.oid = index_row.indexrelid
WHERE index_class.relname IN (
    'idx_scans_dwca_personal_keyset',
    'idx_scans_dwca_global_keyset'
);
```

Both flags must be true before the normal deployment. The migration's
`IF NOT EXISTS` statements then converge without rebuilding those indexes. Do
not run concurrent index DDL inside `supabase db push`.

Preflight:

```bash
deno fmt --check \
  services/supabase/functions/export-dwca \
  services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts \
  services/supabase/functions/_tests/exportDwcaSecurityCoverage.test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,.github/workflows/deploy.yml \
  services/supabase/functions/_tests/exportDwcaSecurityCoverage.test.ts \
  services/supabase/functions/export-dwca/archive_test.ts \
  services/supabase/functions/export-dwca/db_test.ts \
  services/supabase/functions/export-dwca/index_test.ts \
  services/supabase/functions/export-dwca/mail_test.ts \
  services/supabase/functions/export-dwca/pseudonym_test.ts \
  services/supabase/functions/export-dwca/storage_test.ts \
  services/supabase/functions/export-dwca/worker_test.ts \
  services/supabase/functions/export-dwca/zip_test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/export_dwca_security.sql \
  services/supabase/tests/export_dwca_snapshot_security.sql
```

The database test must prove all three source constraints are validated, API
roles cannot read the internal projections or membership fingerprints, only
`service_role` can execute the source-page RPC, a byte ceiling can stop a page
before its row ceiling, the returned completion flag remains false when more
keyset work exists, both phases retain creation-time membership, changed
revisions return no payload, and terminal status purges membership.

Post-deploy, queue one personal test export and deliberately redeliver the same
job UUID while its first phase owns the lease. Both wake-ups return `200`; one
result advances the phase and the duplicate reports `not_claimed` without source
or provider work. Allow the minute cron to advance every phase. The storage test
suite also proves that an S3-compatible HTTP-200 `<Error>` completion body is
rejected and that R2/Resend response bodies stop at their byte ceilings. After
completion, verify with an owner connection:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    jobs.id,
    jobs.user_id,
    jobs.export_scope,
    jobs.pseudonym_key_version,
    jobs.max_export_rows,
    jobs.max_archive_bytes,
    jobs.status,
    jobs.archive_object_key,
    jobs.archive_ready_at,
    jobs.failure_code,
    claims.attempt_count,
    claims.lease_expires_at
FROM public.export_jobs AS jobs
LEFT JOIN internal.export_job_claims AS claims
  ON claims.job_id = jobs.id
WHERE jobs.id = '<test-job-uuid>'::UUID;

SELECT
    work.phase,
    work.occurrence_after_id,
    work.multimedia_after_id,
    work.occurrence_rows,
    work.multimedia_rows,
    work.csv_bytes,
    work.chunk_sequence,
    work.retry_count
FROM internal.export_job_work AS work
WHERE work.job_id = '<test-job-uuid>'::UUID;

SELECT
    source_state.snapshot_version,
    source_state.snapshot_at,
    source_state.source_scan_count,
    source_state.source_too_large,
    source_state.purged_at,
    (
        SELECT COUNT(*)
        FROM internal.export_job_source_membership AS membership
        WHERE membership.job_id = source_state.job_id
    ) AS retained_membership_rows
FROM internal.export_job_source_state AS source_state
WHERE source_state.job_id = '<test-job-uuid>'::UUID;

SELECT
    chunks.phase,
    chunks.sequence,
    chunks.byte_count,
    chunks.object_key ~
        '/work/(occurrence|multimedia)/[0-9]{8}-[0-9a-f-]{36}\.csv$'
        AS claim_fenced_key
FROM internal.export_job_chunks AS chunks
WHERE chunks.job_id = '<test-job-uuid>'::UUID
ORDER BY
    CASE chunks.phase WHEN 'occurrence' THEN 0 ELSE 1 END,
    chunks.sequence;

SELECT
    protocol.legacy_payload_until,
    protocol.legacy_payload_until > NOW() AS rollout_cohort_open
FROM internal.export_worker_protocol AS protocol
WHERE protocol.singleton;

SELECT
    checks.routine_signature,
    HAS_FUNCTION_PRIVILEGE(
        'anon',
        checks.routine_signature,
        'EXECUTE'
    ) AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        checks.routine_signature,
        'EXECUTE'
    ) AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        checks.routine_signature,
        'EXECUTE'
    ) AS service_role_can_execute
FROM (
    VALUES
        ('public.get_due_export_job_ids(integer)'),
        ('public.claim_export_job_step(uuid,uuid)'),
        ('public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,boolean)'),
        ('public.get_export_job_chunks(uuid,uuid)'),
        ('public.stage_prepared_export_archive(uuid,uuid,text,text)'),
        ('public.complete_prepared_export_job(uuid,uuid)'),
        ('public.release_export_job_step(uuid,uuid,text,boolean)'),
        ('public.renew_export_job_claim(uuid,uuid)')
) AS checks(routine_signature)
ORDER BY checks.routine_signature;

ROLLBACK;
```

The completed row must be a personal export within both canonical budgets, use
key version `1`, have an attempt-scoped `exports/{user}/{job}/{claim}.zip` key,
and have no failure code. The work phase must be `completed`; every chunk key
must be claim-fenced. ACL results must be `false`, `false`, `true` for each
routine. Verify the received message contains one 24-hour signed URL and that
duplicate processing did not send a second email. The private
protocol/work/manifest tables are owner-visible operational state only; API
roles, including `service_role`, must lack direct `SELECT`.

For key rotation, first add `DWCA_PSEUDONYM_HMAC_KEY_V2` to GitHub, extend the
workflow to validate/synchronize it, and deploy code capable of reading both
versions. Only then migrate the `export_jobs.pseudonym_key_version` default to
`2`. Keep V1 configured until all V1 jobs are terminal and past operational
retention. Never overwrite V1 with new bytes: doing so silently changes stable
pseudonyms for jobs already pinned to version 1.

If storage or Resend is transiently unavailable, do not bypass the claim RPC,
edit a job to completed, reuse a stale claim token, or restore caller-supplied
scope/user fields. Let the lease/watchdog expose the normal failed/retry path.
Cloudflare's lifecycle policy must remove orphan attempt objects and completed
export objects after their documented retention window. Before release, compare
the live rules with `docs/r2-lifecycle.json`: the bucket must retain the global
seven-day incomplete-multipart abort rule as well as the one-day `exports/`
expiration rule.

### RevenueCat Webhook Release Gate

Migrations `20260723201500_secure_revenuecat_webhook_delivery.sql` and
`20260725052338_reconcile_revenuecat_subscribers.sql`, followed by
`20260726031502_scale_revenuecat_reconciliation.sql`, must land before the
hardened `revenuecat-webhook` and `reconcile-revenuecat-subscribers` bundles.
Populate and configure the credentials before merging the first deployment:

1. Generate at least 32 random characters for `REVENUECAT_WEBHOOK_SECRET`, for
   example `openssl rand -hex 32`. Configure RevenueCat's webhook Authorization
   header as `Bearer <that value>` and store the raw value in the GitHub
   `Production` environment secret.
2. Enable HMAC signing for the webhook in RevenueCat. Copy the signing secret
   shown once into GitHub `Production` as `REVENUECAT_WEBHOOK_SIGNING_SECRET`.
   Do not generate a different local value.
3. Create or select a RevenueCat secret server API key authorized for the same
   project and store it as `REVENUECAT_SECRET_API_KEY`. It must begin with
   `sk_`; do not use any public SDK/Test Store key.
4. Confirm the webhook URL targets the production
   `/functions/v1/revenuecat-webhook` route and that the RevenueCat project
   contains the reviewed `pro` or `Naturalist Tier` entitlement plus `pro_week`.
   If the integration filters event types, it must include `TRANSFER` as well as
   the subscription/purchase lifecycle events; RevenueCat sends no separate
   expiration/renewal pair for a transfer.

Run the complete preflight:

```bash
deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/scripts,services/supabase/config.toml,.github/workflows \
  services/supabase/functions/_tests/revenueCatWebhookCoverage.test.ts \
  services/supabase/functions/_shared/subscriptionPass_test.ts \
  services/supabase/functions/revenuecat-webhook/handler_test.ts \
  services/supabase/functions/revenuecat-webhook/index_test.ts \
  services/supabase/functions/revenuecat-webhook/signature_test.ts \
  services/supabase/functions/revenuecat-webhook/subscriber_test.ts \
  services/supabase/functions/reconcile-revenuecat-subscribers/db_test.ts \
  services/supabase/functions/reconcile-revenuecat-subscribers/worker_test.ts \
  services/supabase/scripts/monitor_revenuecat_reconciliation_test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/revenueCatWebhookMigrationContract.test.ts

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/ai_quota_security.sql \
  services/supabase/tests/revenuecat_webhook_security.sql \
  services/supabase/tests/species_observation_stats_security.sql
```

After production deploy, send a RevenueCat test webhook for a linked test UUID.
The delivery must return `200`, and the following owner-only read should show
one event row, its per-user subject row, and the matching watermark:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    events.event_id,
    events.event_type,
    events.event_timestamp_ms,
    events.outcome,
    events.subject_count,
    events.applied_count,
    events.stale_count,
    subjects.subject_kind,
    subjects.authoritative_snapshot_at_ms,
    subjects.outcome AS subject_outcome,
    subjects.entitlement_version,
    events.received_at
FROM internal.revenuecat_webhook_events AS events
JOIN internal.revenuecat_webhook_event_subjects AS subjects
  ON subjects.event_id = events.event_id
WHERE subjects.merian_user_id = '<test-user-uuid>'::UUID
ORDER BY events.received_at DESC
LIMIT 10;

SELECT
    states.last_event_id,
    states.last_event_timestamp_ms,
    states.last_authoritative_snapshot_at_ms,
    users.subscription_tier,
    users.subscription_expires_at,
    users.entitlement_version
FROM internal.revenuecat_customer_state AS states
JOIN public.users AS users
  ON users.id = states.merian_user_id
WHERE states.merian_user_id = '<test-user-uuid>'::UUID;

SELECT
    queue.next_reconcile_at,
    queue.last_snapshot_at_ms,
    queue.last_reconciled_at,
    queue.attempt_count,
    queue.claim_token IS NULL AS claim_released
FROM internal.revenuecat_reconciliation_queue AS queue
WHERE queue.merian_user_id = '<test-user-uuid>'::UUID;

SELECT *
FROM public.get_revenuecat_reconciliation_health();

SELECT
    index_class.relname,
    PG_GET_INDEXDEF(index_row.indexrelid) AS index_definition,
    PG_GET_EXPR(index_row.indpred, index_row.indrelid) AS predicate
FROM pg_index AS index_row
JOIN pg_class AS index_class
  ON index_class.oid = index_row.indexrelid
JOIN pg_namespace AS namespace_row
  ON namespace_row.oid = index_class.relnamespace
WHERE namespace_row.nspname = 'internal'
  AND index_class.relname IN (
      'revenuecat_reconciliation_due_idx',
      'revenuecat_reconciliation_claim_expiry_idx'
  )
ORDER BY index_class.relname;

SELECT
    checks.routine_signature,
    HAS_FUNCTION_PRIVILEGE(
        'anon',
        checks.routine_signature,
        'EXECUTE'
    ) AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        checks.routine_signature,
        'EXECUTE'
    ) AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        checks.routine_signature,
        'EXECUTE'
    ) AS service_role_can_execute
FROM (
    VALUES
        ('public.get_revenuecat_webhook_event_result(text,bigint,text,text)'),
        ('public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)'),
        ('public.schedule_revenuecat_reconciliation(jsonb)'),
        ('public.claim_revenuecat_reconciliations(integer)'),
        ('public.get_revenuecat_reconciliation_health()'),
        ('public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)'),
        ('public.fail_revenuecat_reconciliation(uuid,uuid,text)')
) AS checks(routine_signature)
ORDER BY checks.routine_signature;

ROLLBACK;
```

Expected ACLs are `false`, `false`, `true` for every row. Redeliver the same
RevenueCat test event: the ledger row count for its ID must remain one, the HTTP
outcome must be `duplicate`, and no second CustomerInfo request should appear in
Edge logs. Compare the projected tier with the RevenueCat CustomerInfo shown for
that App User ID. A recurring entitlement must persist the later of its
expiration and grace-period expiration; only an explicitly lifetime entitlement
may have a null expiry. `pro_week` must have an expiry exactly seven days after
its authoritative purchase time.

Confirm the active `reconcile_revenuecat_subscribers_every_fifteen_minutes`
cron and its 120-second `pg_net` timeout, then invoke the service-only route
once. It must process repeated six-row waves rather than stop after one wave.
Its aggregate response must report no unpersisted failures, its queue claims
must be released, and an equal/older CustomerInfo snapshot must report stale
without changing the tier. Temporarily suppressing a staging webhook and
allowing the sweep to observe a newer authoritative snapshot is the
missed-delivery recovery smoke test. Pro rows should next be due in roughly six
hours and free rows in roughly 24 hours.

Confirm the `RevenueCat Reconciliation Health Monitor` workflow is enabled for
the Production environment. Dispatch it once with the default 30/60-minute
thresholds and `fail_on=warning`; the summary artifact should be `ok` with no
expired claim. During an alert, inspect the structured
`revenuecat_reconciliation_health` Edge event, `last_error_code`, and
`attempt_count`. Restore RevenueCat/database availability and let claim-fenced
retries drain the queue. Never clear leases or edit user tiers manually.

Also exercise the configured RevenueCat restore/transfer behavior with two
disposable test customers. The single `TRANSFER` event must show
`subject_count = 2`, one `transfer_source`, one `transfer_destination`, and the
source/destination tiers must match their two authoritative CustomerInfo
responses. A `mixed` outcome is valid only when one user already has a strictly
newer watermark; there must never be a one-sided database commit after a failed
provider lookup.

Rotate the API key by deploying the new key before revoking the old key. For the
Authorization or HMAC credential, coordinate the RevenueCat dashboard change and
GitHub secret update in one supervised window, immediately dispatch the
workflow, then send a test event. HMAC rotation invalidates the previous signing
secret immediately; non-2xx deliveries during the short window should retry.

Do not recover an incident by disabling HMAC, widening the replay window,
trusting `event.type`, directly editing the private ledger, or restoring direct
service-client tier updates. Keep provider deliveries retrying with non-2xx
responses while fixing forward. Preserve the event ledger during rollback or
repair because it is the durable replay and ordering evidence.

### Naturebook Public Rebrand Release

The rebrand is a forward-only data and response-copy change, not a backend
rename. Deploy it through the normal CI path with:

- `services/supabase/migrations/20260716012046_rebrand_public_surfaces_to_naturebook.sql`
- the affected Edge Functions selected by the deployment planner;
- the production Edge secret
  `RESEND_FROM_EMAIL="Naturebook Data Exports <exports@naturebook.earth>"`.

The migration updates current permission attribution, changes the existing
`refresh_merian_reference_images` function's generated public attribution, and
reserves `naturebook` plus `naturebookearth` usernames. It intentionally keeps
the function name, `source = 'merian'`, database objects, storage paths, RPC
names, and previous migration files unchanged. Never edit historical migrations
to remove old public strings.

After deployment, verify:

```sql
select candidate,
       public.is_reserved_public_username(candidate) as is_reserved
from unnest(array['merian', 'naturebook', 'naturebookearth']) as candidate;

select count(*) as stale_permission_licenses
from public.species_reference_images
where license = 'Used with permission via Merian';

select pg_get_functiondef(
  'public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::regprocedure
)
  like '%Used with permission via Naturebook%' as naturebook_license_active;
```

All three reserved-name results must be true, the stale count must be zero, and
the function check must be true. Smoke-test user-facing response and export
email copy, but continue to expect durable Merian values in internal logs,
headers, analytics, source fields, and route names. See the
[public brand compatibility contract](../system-architecture/08-public-brand-compatibility.md)
and
[rebrand rollout runbook](../development-guides/15-naturebook-rebrand-rollout.md).

## Manual Data Repair Utilities

Processed-material scan pollution must be repaired manually, not as an automatic
migration. If historical scans linked artifacts such as wool rugs, kilims,
textiles, leather goods, or man-made objects to biological species rows, run the
audit script in dry-run mode first:

```sh
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  deno run --allow-net --allow-env \
  services/supabase/scripts/repair_processed_material_scan_pollution.ts
```

Review every planned row before applying:

```sh
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  deno run --allow-net --allow-env \
  services/supabase/scripts/repair_processed_material_scan_pollution.ts --apply
```

The script only plans rows whose scan evidence explicitly contains
artifact/process terms, then nulls scan species links, marks the scan
non-biological, clears biological metadata/candidates, and restores or removes
polluted dictionary English names. It is intentionally narrow and should not be
converted into a broad production migration.

Media-upload contract changes are migration-plus-function releases. For example,
the video staging contract that allows five sampled inference frames plus one
playback clip requires the `scan_media_assets.scan_id` and
`scan_media_assets.url` nullable repair migrations to be pushed before the
updated `/generate-upload-urls` bundle handles six-file signing requests in
production. A database-only deploy leaves clients on the old signing cap; a
function-only deploy can still fail staged row creation if an early production
table kept `scan_id NOT NULL` or `url NOT NULL`.

The scan-media uniqueness repair is database-only. Apply
`20260720230648_repair_scan_media_asset_uniqueness.sql` when reconciliation
reports `23505` against `scan_media_assets_scan_id_order_index_key`. Verify the
legacy table constraint is absent and both partial indexes named in the
migration have the expected definitions. Then invoke
`reconcile-scan-media-assets` with `dryRun: true`; run the live repair only when
the candidate count is expected and `error_count = 0`. The live run should leave
no stale `capture_upload` rows for that incident and should write a `success`
row to `scan_media_reconciliation_runs`.

Video audio-metadata fixes are also migration-plus-function releases. The
`20260707041259_fix_video_has_audio_metadata.sql` helper/backfill and the
composer/share/edit function bundles must deploy together so `scan_media_assets`
and `explore_post_media` only set `has_audio` when `captured_media` proves an
audio companion exists.

Audio moderation-attestation releases are migration-first. Apply
`20260711055524_add_explore_audio_moderation_attestations.sql` before deploying
the updated `_shared/audioModeration.ts`, `share-scan-to-explore`,
`request-community-identification`, and `update-explore-field-notes` bundles.
Functions safely fall back to live Gemini when the table is temporarily
unavailable, but deploying the migration first avoids unnecessary provider calls
and cache-error logs. Never deploy a function that treats a cache error as
approval.

Legacy-audio sharing also requires
`20260711143348_repair_scan_media_assets_audio_constraints.sql` in production.
Without it, `/generate-upload-urls` fails before upload with SQLSTATE `23514`
and `scan_media_assets_kind_check` when it inserts a staged `kind = 'audio'`,
`role = 'audio'` row. Apply the constraint repair before validating the iOS
legacy-recovery flow.

Explore audio spectrogram releases are function-plus-web releases with no new
database migration. Deploy the updated `share-scan-to-explore`,
`update-explore-field-notes`, and `delete-scan` bundles plus the new
`backfill-explore-audio-spectrograms` bundle before deploying `apps/web`.
Because `_shared/audioSpectrogram.ts` and `_shared/aws.ts` are bundled into each
dependent function, partial deployment can leave publication or deletion on an
older lifecycle contract. After function deployment, invoke the service-role
backfill in WAV-only batches while `generated_count` remains greater than zero,
then deploy the web app so cached feed/detail payloads can resolve the persisted
posters. Legacy non-WAV rows are intentionally outside the backfill candidate
set and retain normal playback plus the speaker fallback.

Field trips releases are migration-plus-function releases too. Deploy
`20260708021110_field_trips_v1.sql` before `20260708033451_field_trips_v2.sql`
before `20260708042713_field_trips_v3_community.sql` before
`20260708051414_field_trips_v4_challenges.sql` before
`20260717150222_contextual_outing_objective_guides.sql` before
`20260717195751_active_outing_capture_context.sql` before
`20260717213641_preserve_standard_outings_in_capture_context.sql` before
`20260717224544_retire_forest_edges_outing.sql` before
`20260718043218_expose_field_trip_completion_scan_ids.sql` before
`20260718051748_expose_field_trip_publication_status.sql` before
`20260718150932_add_credited_field_trip_progress.sql` before
`20260718162409_scope_credited_progress_to_current_attempt.sql` before
`20260719045306_first_field_trip_achievement.sql` before
`20260719160750_field_trip_lifecycle_controls.sql` before
`20260720014446_update_backyard_safari_copy.sql` before
`20260722025411_persistent_field_trip_scan_contributions.sql` before
`20260722064704_harden_atomic_field_trip_progress.sql` before
`20260722195453_exclude_ants_from_bee_wasp_goal.sql` before
`20260722211636_tighten_field_trip_goal_matching.sql`, then deploy the updated
scan-ingestion functions, `field-trips`, and the Explore/profile activity
bundles together. V1 creates the Field trip tables, progress/publication/comment
storage, profile visibility helpers, and publication snapshots. V2 adds guided
template detail, explicit starts, Recent compatibility pagination, and profile
pins. V3 adds the Community publication RPC, Field trip in-app activity storage,
and Explore activity union/read/count RPC updates. V4 adds curated seasonal
challenge storage, explicit joins, challenge-specific item completions,
completion badges, challenge entry snapshots, challenge entry comments/likes,
and scan-scoped hashtag suggestion helpers. The contextual-guide migration
supplies the structured Tips content used by focused target navigation. The
capture-context migration adds the private service-role RPC and its active-field
trip/challenge lookup indexes consumed by the Scan indicator. The preservation
migration keeps the shared standard field trip eligible after a Seasonal
Challenge join while leaving challenge-specific progress out of the capture
payload. The Forest retirement migration deactivates the placeholder while
retaining existing progress and evidence. The completion-evidence migration
redefines the private catalog/detail projections to expose the exact completing
scan ID without a media URL and restricts both RPCs to `service_role`. The
publication- status migration keeps template detail private and adds only the
owner's active, non-deleted publication ID/timestamp for the Private/Published
badge. The credited-progress migrations replace the standard/challenge progress
RPC bodies without changing their signatures or permissions and adds optional
credited level/count fields for scan-completion feedback. Those values preserve
the just-completed level when the existing current-level fields have already
advanced to the next level and stay scoped to checklist items matched by the
current attempt when an older scan is re-identified. The first-achievement
migration adds the server-authoritative earliest completion, and the lifecycle
migration adds private active periods plus Stop/Reset. The persistent-
contribution migration enforces one credit per scan per outing/Event, adds the
private selected-goal preference, supports correction removal/move for
unfinished experiences, and creates the service-role-only scan contribution read
model used by Insight. It transactionally aborts if completed trips,
publications, completed/badged Event participations, Event badges, or Event
entries already exist. Confirm the expected empty-artifact assumption before
deployment; an abort is a data/product review blocker and must not be bypassed.
The atomic-hardening migration adds the private scan-revision receipt and
ingestion/correction triggers, combines standard outing progress, joined Event
progress, selected-goal persistence, and first-outing achievement evaluation in
one transaction, repairs completed-outing publication materialization, and
replaces the profile-pin RPC's temporary table with a lintable ordered-array
mutation. It revokes every Field trip/Event `SECURITY DEFINER` routine from
direct client roles. Only `service_role` retains execute. The ant-exclusion
migration introduces the excluded-family matcher and repairs ant-backed Bee or
wasp credit. The goal-hardening migration then makes the final active catalog
authoritative: compound goals require both their taxonomy and their
ecology/habitat/semantic signal; Spider requires `Araneae`; Backyard Butterfly
requires the butterfly category; Bee or wasp requires Hymenoptera plus
`bee|wasp`; unverifiable “near flowers” prompt text is removed; and Pollinator
habitat becomes Meadow plant. It removes newly invalid standard/Event
completions, reopens affected progress, clears stale preferences/receipts and
badges, and withdraws invalid completion publications/entries. A function-only
deploy cannot serve `capture_context` or V4 actions until all migrations are
applied; a database-only deploy leaves the app without the Field trips action
router. Do not release the indicator-enabled iOS client until both the
capture-context migration and updated function are live. Do not release the
completed-goal thumbnail route until the completion-evidence migration is live;
its optional decode keeps older database responses compatible during a staged
rollout. Release the status badge only after the publication-status migration;
its optional fields render Private against the older payload. Deploy both
credited-progress migrations, in order, before the progress-toast iOS client.
The client can decode the legacy shape and fall back to current counts during a
staged rollout. All Field Trip migrations through
`20260722211636_tighten_field_trip_goal_matching.sql`, updated ingestion
functions, and updated `field-trips` must precede the Insight-card iOS client
because that client may send optional `preferred_goal`, retain it until
acknowledgement, and request `scan_contributions`. Older clients omit the hint
and continue to receive deterministic fallback behavior.

Current client rollout (2026-07-22): standard Field trips/Outings are public,
while Seasonal Challenge Events remain staged through the `.fieldTripEvents`
default in the iOS `FeatureFlags` registry. The tester account and simulator
builds bypass that default. This is not a Supabase feature flag or an
authorization boundary, and the current backend remains deployed for both
standard and challenge actions. Publishing Events later requires an iOS build;
do not run migrations or redeploy `field-trips` solely for that flag change.
Follow the canonical release checklist in
[`25-field-trips.md`](../features-and-hardware/25-field-trips.md#rollout-state-and-events-release-checklist).

Each deployed function directory must also have a `[functions.<name>]` entry in
`services/supabase/config.toml` so JWT behavior is explicit. Most
anonymous-compatible app routes set `verify_jwt = false` and then perform manual
auth inside Deno; the known authenticated-only exceptions are documented in
`docs/backend-and-data/02-supabase-edge-and-database.md`.

`services/supabase/functions/deno.json` is the reviewed dependency source, not
the deploy-time parent config. `sync_function_deno_configs.ts` generates a
`deno.json` inside every function directory, and each generated config points at
the tracked frozen `services/supabase/functions/dependencies.lock`. Supabase
discovers the function-local config while bundling. Do not pass the retired
`--import-map` flag. Runtime code imports configured aliases; direct esm.sh,
deno.land, npm, and JSR specifiers are rejected from production graphs. The
fleet uses one exact `@supabase/supabase-js@2.110.6` dependency for both
`getUser` and `getClaims`. `_shared/claimsAuth.ts` remains opt-in to avoid
silently changing authentication policy for unrelated routes, not to isolate a
second SDK. `functions/dependencies.lock` is the only lockfile; do not add a
root or function-local `deno.lock` that can silently diverge from it. The root
and generated configs explicitly set `minimumDependencyAge` to `P1D`. Deno 2.9
applies a one-day default even when the field is absent, but spelling the policy
out prevents toolchain drift. A fresh CI cache may download a version already
integrity-pinned in the frozen lock; newly resolved npm/JSR versions must still
satisfy the one-day delay. Do not disable the protection with
`--minimum-dependency-age=0` to repair CI. Refresh and commit the lock through
the reviewed dependency-update flow instead.

When changing dependencies, update the root manifest, regenerate all local
configs, refresh the lockfile, and commit the three surfaces together:

```bash
deno run --allow-read=services/supabase \
  --allow-write=services/supabase/functions \
  services/supabase/scripts/sync_function_deno_configs.ts

deno install --config services/supabase/functions/deno.json \
  --lock services/supabase/functions/dependencies.lock \
  --frozen=false --lockfile-only --entrypoint \
  $(rg --files services/supabase/functions services/supabase/scripts \
    | rg '\.ts$')

deno run --allow-read=services/supabase \
  services/supabase/scripts/validate_function_dependencies.ts
```

The workflow deploys planned names in batches of eight with four CLI jobs. If a
batch reports failure, only its members enter isolated retries, up to three
attempts each with bounded backoff. A failure can still occur after migrations
and some function versions are live; treat that as a mixed deployment. Do not
roll back an already-applied migration. Fix the graph or runtime issue, run the
full validation suite, and push a new commit. The next dependency-aware plan
will select changed functions; use manual dispatch when an operator deliberately
needs a full-fleet reconciliation. Complete the normal smoke checks before
declaring the release healthy.

## Ghost Account Merge Security Rollout

Migration `20260723043447_secure_atomic_ghost_profile_merge.sql`,
`merge-ghost-profile`, `reconcile-ghost-profile-merges`, and the proof-capable
iOS client form one security contract. The legacy client switches away from the
guest session before it can prove source consent, so the backend must never
accept its arbitrary source UUID payload.

### Compatibility order

1. Release the proof-capable iOS build first. Against the old backend its
   `prepare` request fails before the app switches sessions, preserving guest
   data.
2. Wait for the required adoption threshold or enforce the existing minimum-app
   version on the OAuth-conflict path. Do not let an old build attempt an
   existing-account conflict after the secure endpoint is live.
3. Deploy both new Edge Functions. Before the migration, `prepare` safely fails
   because its RPC is absent.
4. Apply the migration immediately afterward. This activates the RPCs, revokes
   the legacy helper from client roles, and installs the five-minute cleanup
   schedule.
5. Smoke-test both the normal direct-link path and the existing-account conflict
   path before lifting the release gate.

Never restore client execution of `reparent_user_follows` and never add a
compatibility request field that lets the caller nominate `ghost_user_id` or
`target_user_id`.

### Preflight and local verification

Confirm Vault has `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; the scheduled
worker reads those exact names. Confirm the function entries are:

```toml
[functions.merge-ghost-profile]
verify_jwt = true

[functions.reconcile-ghost-profile-merges]
verify_jwt = false
```

Run from the repository root:

```bash
make validate-supabase-migrations

deno fmt --check \
  services/supabase/functions/merge-ghost-profile \
  services/supabase/functions/reconcile-ghost-profile-merges
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions/merge-ghost-profile \
  services/supabase/functions/reconcile-ghost-profile-merges
deno check \
  --config services/supabase/functions/merge-ghost-profile/deno.json \
  services/supabase/functions/merge-ghost-profile/index.ts
deno check \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/index.ts
deno test \
  --config services/supabase/functions/merge-ghost-profile/deno.json \
  services/supabase/functions/_tests/mergeGhostProfile.test.ts
deno test \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/worker_test.ts

supabase --workdir services db reset
supabase --workdir services test db --local \
  services/supabase/tests/ghost_profile_merge_security.sql
supabase --workdir services db lint --local --schema public,internal
supabase --workdir services db advisors --local --type security
supabase --workdir services db advisors --local --type performance
```

The pgTAP case must prove the attacker/provider mismatch is rejected, the same
destination replay is idempotent, every source reference is reparented, AI usage
stays append-only and attributed, client roles lack cleanup grants, and a
service-role cleanup claim can be finalized. It must also prove a live bulk
empty-ghost cleanup reservation blocks handoff issuance. After this migration,
the current audit script must see protected handoff sources and the current
cleanup script must reserve each candidate; do not execute an older script
against production.

Before production:

```bash
supabase --workdir services db push --linked --dry-run
supabase --workdir services functions deploy merge-ghost-profile
supabase --workdir services functions deploy reconcile-ghost-profile-merges
supabase --workdir services db push --linked
supabase --workdir services migration list --linked
```

Do not deploy with `--no-verify-jwt` for `merge-ghost-profile`. The anonymous
prepare caller has a valid user JWT and receives both gateway verification and
the live-user/`auth.uid()` checks.

### Smoke matrix

Use disposable staging identities and no real user data:

- New Apple/Google identity: direct `linkIdentityWithIdToken` preserves the
  guest UUID and creates no handoff.
- Existing identity: prepare returns HTTP 201, `Cache-Control: no-store`, a
  43-character base64url secret, and an expiry approximately 30 days out.
- A different permanent account, including another account using the same
  provider, receives `handoff_forbidden`; source data and receipt remain
  unchanged.
- The bound destination completes once, receives HTTP 200, owns scans,
  collections, Explore/Field trip/social rows and AI attribution, and a replay
  reports `already_merged = true`.
- A transient 503 keeps the iOS Keychain queue item. A terminal 404/410 removes
  only that item; another queued handoff survives.
- The source public profile disappears in the merge transaction. The source Auth
  row is deleted after commit by the foreground call or, if deliberately faulted
  in staging, by the scheduled worker.

### Monitoring and recovery

Run these read-only queries from the SQL editor or another owner-only
operational connection:

```sql
SELECT status, COUNT(*)
FROM internal.ghost_profile_merge_handoffs
GROUP BY status
ORDER BY status;

SELECT
  id,
  ghost_user_id,
  target_user_id,
  merged_at,
  cleanup_attempt_count,
  last_cleanup_error_code,
  cleanup_claimed_at
FROM internal.ghost_profile_merge_handoffs
WHERE status = 'merged'
  AND auth_deleted_at IS NULL
ORDER BY merged_at;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'reconcile_ghost_profile_merges_every_five_minutes';
```

Alert when a merged receipt remains without `auth_deleted_at` for more than 20
minutes, when cleanup attempts continue increasing, or when Edge logs repeatedly
emit `ghost_profile_merge_auth_cleanup_pending`,
`ghost_profile_merge_reconciliation_failed`, or `merge_temporarily_unavailable`.
Investigate the Auth Admin API and database error before manually retrying the
worker. Do not edit `secret_hash`, `target_user_id`, or receipt status by hand.

If the worker itself is faulty, unschedule only the named cron job, retain every
receipt, deploy a forward fix, invoke the worker manually with a small limit,
and restore the schedule. If the merge path is faulty, gate the existing-account
fallback in the client; normal direct identity linking can remain available. Do
not roll back the migration, recreate the arbitrary UUID API, drop receipt rows,
or reparent data manually. Database correction is a forward migration. A client
rollback must keep old conflict-capable builds blocked until they can produce a
source-issued proof.

## Identification Latency Rollout

The image-analysis latency change is a staged operational rollout, not a reason
to change Gemini configuration. Free remains `gemini-2.5-flash`; Pro remains
`gemini-2.5-pro`. Prompts, schema, thinking budgets, image resolution,
`maxOutputTokens`, and the single primary identification model call per scan are
release invariants. Audio and video receive the additive timing instrumentation
but no client behavioral change in this pass.

Release in three observable waves:

1. Deploy compatible timing instrumentation and establish pre-change p50/p95
   baselines for Gemini, non-Gemini Edge work, response-to-first-render,
   failures, missing remote scans, and stuck ingestion jobs.
2. Roll out the iOS critical-path changes: eligible live-camera still-image 150
   ms context grace, pinned-session prewarm, inline/background upload handoff,
   and first-result-before-secondary-work commit.
3. Roll out the Edge/database optimization. Within this wave, apply
   `20260715153946_reduce_identification_latency_round_trips.sql` before
   deploying `identify-multimodal`, `_shared` dependents, and
   `update-scan-context`. The identify handler has a temporary old-helper
   fallback for propagation safety; repeated fallback logs after rollout are an
   incident, not a steady state.

Advance Edge traffic through 10%, 50%, and 100% only when the observation window
meets every gate:

- non-Gemini p95 is at most 1 second (target p50 at most 300 ms);
- response-to-first-render p95 is at most 300 ms;
- identification quality is unchanged;
- failure rate increases by less than 0.5 percentage points;
- missing remote scans and stuck ingestion jobs do not increase.

When measured Gemini p95 is at most 5 seconds, the corresponding end-to-end p95
goal is at most 6 seconds. If the final end-to-end p95 remains high and
`Server-Timing` shows `gemini` dominates, record Gemini as the remaining floor;
do not alter model economics under this rollout.

Keep automatic nearest-user Edge execution as the baseline. Compare it with a
database-region invocation using equivalent traffic, tier/model/image-count/
payload-size/network segments. Force a region only if p95 improves by at least
150 ms without a failure-rate increase. Record the experiment and rollback
decision before changing production region configuration.

Before increasing traffic, verify:

- valid anonymous and authenticated ES256 JWTs succeed;
- expired, malformed, wrong-issuer/audience, and public service-role JWTs fail;
- internal replay still requires the timing-safe service credential and explicit
  replay-user identity;
- `Server-Timing` contains `auth`, `body_read`, `tier`, `pre_gemini_db`,
  `gemini`, `dictionary`, `post_gemini`, and `edge_total` and contains no
  private identifiers;
- the latency event includes only approved aggregate tags;
- a deferred-context call updates an existing owner scan or stages against a
  claimed ingestion job, and cannot update another user;
- WeatherKit, geocoding, awards, Field trips, Wikipedia, and GBIF delays do not
  move the first-render boundary;
- request failure, connectivity loss, backgrounding, termination, the two-second
  fail-safe, and duplicate live/background completion leave no missing or stuck
  scan.

The migration grants can be spot-checked after `db push`:

```sql
select routine_name, routine_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'begin_scan_ingestion',
    'hydrate_identification_dictionary',
    'apply_or_stage_scan_context'
  );

select relname, relrowsecurity
from pg_class
where relname = 'scan_deferred_context_updates';
```

Do not describe the latency targets as production-validated until all three
waves and the final observation window complete. After validation, update the
changelog and latency/AI/API/logging/offline-queue docs with the measured
p50/p95 and the chosen Edge-region policy.

## Public Waitlist Security Rollout

Migration `20260724192124_harden_json_endpoints_and_waitlist.sql` and the
secured Next.js waitlist route are one compatibility unit. Deploy the database
boundary first. The old direct table upsert cannot work after revocation, while
the new route cannot work before `claim_beta_waitlist_challenge_attempt(...)`
and `submit_beta_waitlist_signup(...)` exist.

### One-time production setup

1. In Cloudflare Turnstile, create a **Managed** widget for `naturebook.earth`.
   Copy its public site key and secret separately. Preview domains should use a
   separate widget and an explicit preview hostname list; do not broaden the
   production allowlist with wildcards.
2. Generate a dedicated waitlist IP-HMAC secret:

   ```bash
   openssl rand -hex 32
   ```

3. Configure these Vercel Production environment values:

   | Variable                         | Production value/contract                                      |
   | -------------------------------- | -------------------------------------------------------------- |
   | `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | Public key for the production widget                           |
   | `TURNSTILE_SECRET_KEY`           | Server secret for that same widget                             |
   | `TURNSTILE_ALLOWED_HOSTNAMES`    | `naturebook.earth`                                             |
   | `WAITLIST_IP_HASH_SECRET`        | Dedicated value generated above; at least 32 random characters |
   | `WAITLIST_TRUSTED_IP_HEADER`     | `x-vercel-forwarded-for`                                       |
   | `SUPABASE_URL`                   | Production project URL                                         |
   | `SUPABASE_SERVICE_ROLE_KEY`      | Production server-only service-role key                        |

   Vercel owns and overwrites `x-vercel-forwarded-for` at the application
   ingress. If the app moves behind another proxy, explicitly choose one
   allowlisted header and configure the trusted ingress to overwrite it; never
   accept a client-appended forwarding chain.

Do not put the Turnstile secret, waitlist HMAC secret, or Supabase service-role
key in a `NEXT_PUBLIC_` variable, source file, build log, or support ticket.
Only the Turnstile site key is public.

### Verification and deployment order

From the repository root, complete the static/unit gates and disposable database
fixture before production:

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations \
  services/supabase/functions/_shared/http_test.ts \
  services/supabase/functions/_tests/edgeHandler.test.ts \
  services/supabase/functions/_tests/jsonEndpointSecurityCoverage.test.ts \
  services/supabase/functions/_tests/jsonEndpointSecurityMigrationContract.test.ts

cd apps/web
npm test
npm run typecheck
npm run build
```

The production sequence is:

1. Run the normal Supabase workflow so the migration, privileged-routine catalog
   gate, and `waitlist_security.sql` pass.
2. Verify both hosted function signatures are executable by `service_role` only
   and the waitlist tables are not directly accessible by API roles.
3. Deploy the web application with all Vercel values above.
4. Submit one real browser signup so Turnstile can issue a valid, single-use
   token. Repeat the same address and confirm the response is deliberately
   indistinguishable.
5. Confirm a non-JSON request returns `415`, a body above 4 KiB returns `413`,
   and an invalid/expired challenge returns `400 invalid_challenge`. Repeated
   invalid attempts must reach the distributed pre-challenge `429` boundary,
   while repeated verified attempts must reach the tighter insertion `429`; both
   responses include `Retry-After: 600`.
6. Search server logs by `request_id`. Confirm raw emails, client IPs, Turnstile
   tokens, database messages, and provider responses are absent.

Post-deploy catalog checks:

```sql
SELECT
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) AS service_role_can_execute,
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) AS service_role_can_claim,
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) AS anon_can_execute,
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) AS anon_can_claim,
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) AS authenticated_can_execute,
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) AS authenticated_can_claim;

SELECT conname, convalidated
FROM pg_catalog.pg_constraint
WHERE conrelid = 'public.beta_waitlist_signups'::pg_catalog.REGCLASS
  AND conname LIKE 'beta_waitlist_signups_%_shape_check'
ORDER BY conname;

SELECT scope_type, pg_catalog.SUM(request_count) AS bounded_requests
FROM internal.beta_waitlist_rate_counters
GROUP BY scope_type
ORDER BY scope_type;
```

Expected privileges are `true, true, false, false, false, false` in the order
selected. The counter query is aggregate only; do not export or log the HMAC
scope keys.

The three historical-row constraints begin `NOT VALID` so deployment is not
blocked by old data, while all new writes are protected immediately. After a
privacy-reviewed cleanup of any historical invalid rows, validate them:

```sql
ALTER TABLE public.beta_waitlist_signups
    VALIDATE CONSTRAINT beta_waitlist_signups_email_shape_check;
ALTER TABLE public.beta_waitlist_signups
    VALIDATE CONSTRAINT beta_waitlist_signups_source_shape_check;
ALTER TABLE public.beta_waitlist_signups
    VALIDATE CONSTRAINT beta_waitlist_signups_user_agent_shape_check;
```

If Turnstile verification or the trusted-IP, HMAC, or database boundary fails,
the route intentionally returns `503` and stores no signup. Configuration
failures detected by the preflight consume no counter. After configuration
passes, a request that reaches the distributed pre-challenge gate consumes one
bounded HMAC counter; this contains provider amplification and stores no raw
address. Recover by correcting the server configuration or temporarily disabling
the web form. Do not restore the old direct table upsert, grant table access to
`service_role`, relax CAPTCHA verification, or accept an untrusted forwarding
header as a rollback.

The route validates the Turnstile secret, hostname allowlist, trusted client
address, and HMAC secret before calling the pre-challenge RPC. A configuration
failure therefore must not increase `challenge_ip_10m` or `challenge_ip_day`.
Expired-counter maintenance is capped at 500 rows per call and uses
`FOR UPDATE SKIP LOCKED`; lock-timeout alerts should be investigated rather than
worked around by raising the public request limits.

## Required and Optional GitHub Secrets

This section is the GitHub Actions control-plane contract, not a Vercel
application environment template. Never copy the complete GitHub `Production`
secret set into either Vercel project.

| GitHub secret                       | Runtime destination                                           |
| ----------------------------------- | ------------------------------------------------------------- |
| `DWCA_PSEUDONYM_HMAC_KEY_V1`        | Synchronized by the workflow to Supabase Edge only            |
| `REVENUECAT_SECRET_API_KEY`         | Synchronized by the workflow to Supabase Edge only            |
| `REVENUECAT_WEBHOOK_SECRET`         | Synchronized by the workflow to Supabase Edge only            |
| `REVENUECAT_WEBHOOK_SIGNING_SECRET` | Synchronized by the workflow to Supabase Edge only            |
| `SUPABASE_ACCESS_TOKEN`             | Used by the GitHub runner to operate the Supabase CLI         |
| `SUPABASE_DB_URL`                   | Used by the GitHub runner for database migration/audit access |
| `SUPABASE_DB_PASSWORD`              | Used only by the runner's alternative pooler connection path  |

None of these seven values belongs in Vercel. The public-web Vercel contract is
the explicit table in **Public Web Waitlist Release** above and
[`apps/web/.env.example`](../../apps/web/.env.example). Do not confuse its
`SUPABASE_URL` HTTPS API endpoint with the privileged `SUPABASE_DB_URL`
PostgreSQL connection string. The separate internal-admin Vercel project
receives only the three public variables listed under **Internal Admin
Release**.

Set these in the repository's GitHub Actions secrets:

- `SUPABASE_ACCESS_TOKEN` — Supabase CLI access token for the deployment actor.
- `AI_QUOTA_IP_HASH_SECRET` (optional override) — at least 32 high-entropy
  characters. When present in the GitHub `Production` environment, the deploy
  workflow validates and synchronizes it before deploying functions. When
  absent, Edge uses a built-in server-only Supabase key; a weak explicit value
  blocks deployment and runtime provider work. Rotation resets only the current
  network-rate bucket identity and must be a reviewed incident or privacy
  operation.
- `DWCA_PSEUDONYM_HMAC_KEY_V1` — required Base64 value decoding to at least 32
  random bytes. GitHub `Production` is authoritative and the deploy workflow
  synchronizes it to Supabase. It is a versioned global-export HMAC key, not a
  generic application salt.
- `REVENUECAT_WEBHOOK_SECRET` — required, at least 32 random characters, and
  used as the secret portion of RevenueCat's configured
  `Authorization: Bearer <value>` credential.
- `REVENUECAT_WEBHOOK_SIGNING_SECRET` — required RevenueCat-generated HMAC
  signing secret. RevenueCat shows it once and invalidates the previous value
  immediately on rotation.
- `REVENUECAT_SECRET_API_KEY` — required `sk_` secret server API key for
  authoritative CustomerInfo reads in the same RevenueCat project. This is not
  the public iOS `REVENUECAT_API_KEY`.
- One database connection path:
  - Preferred: `SUPABASE_DB_URL` — full percent-encoded Postgres connection
    string for migration pushes. Copy the Supabase shared pooler session-mode
    connection string from the project's **Connect** panel for GitHub Actions.
  - Alternative: `SUPABASE_DB_POOLER_HOST` plus `SUPABASE_DB_PASSWORD` — the
    workflow builds
    `postgresql://postgres.<project-ref>:<encoded-password>@<pooler-host>:5432/postgres?sslmode=require`.
    Store only the exact host from the same session-pooler connection string in
    `SUPABASE_DB_POOLER_HOST`. Do not derive this host from the project region
    alone; a region screenshot confirms geography but not the specific Supavisor
    pooler tenant host. If the host is wrong, Supavisor can still accept the TCP
    connection and then fail with
    `tenant/user postgres.<project-ref> not found`. Merian production's
    confirmed session-pooler host is `aws-1-us-east-1.pooler.supabase.com`.

Optional GitHub Actions variables:

- `SUPABASE_DB_POOLER_PORT` — defaults to `5432`, Supabase shared-pooler session
  mode.
- `SUPABASE_DB_NAME` — defaults to `postgres`.

Use the shared pooler for CI because GitHub-hosted runners are IPv4-only in
common configurations. Direct `db.<project-ref>.supabase.co:5432` hosts can
resolve to IPv6 only and fail before Postgres authentication.

The production Supabase project ref is intentionally stored in the workflow as
`qlarqavoqhkuwzmevrmf`. Project refs are routing identifiers, not credentials;
the deployment authority still comes from `SUPABASE_ACCESS_TOKEN` plus the
configured database connection. Post-deploy smoke checks and manual taxonomy
imports resolve the service-role key at runtime through
`supabase projects api-keys --project-ref qlarqavoqhkuwzmevrmf`, then mask it in
GitHub Actions logs.

If the Supabase dashboard or Management API is unavailable, do not guess the
pooler host in production secrets. Wait for the dashboard to recover, or get the
existing shared-pooler host from another operator who already has access. The
`supabase link` command also uses the Management API, so `504` or `500`
responses during a Supabase incident can block linking even when the migration
SQL itself is fine. Using `db push --db-url` only removes the project-status
lookup from the migration step. Edge Function deploys, service-role key lookup,
and smoke tests still depend on Supabase's hosted APIs and can fail during an
active platform incident.

The workflow also inherits normal Supabase project Edge secrets at runtime. Most
live only in Supabase. The three RevenueCat credentials, required DwC-A
versioned pseudonym key, and optional AI quota override are reviewed exceptions:
GitHub `Production` is their deploy source and the workflow synchronizes them to
Supabase. The complete Edge-secret inventory is documented in
`docs/backend-and-data/02-supabase-edge-and-database.md`.

## Manual Production Deploy

Use the manual GitHub Actions dispatch first:

1. Open the GitHub repository.
2. Go to **Actions**.
3. Select **Deploy Merian to Supabase**.
4. Click **Run workflow** on `main`.

This keeps deploy logs, validation, migration push, and function deployment in
one auditable place.

## Taxonomy Import Automation

The **Import Community Taxonomy** workflow runs automatically every Monday at
`09:20 UTC` (`04:20 America/Chicago` during daylight saving time). Scheduled
runs use:

- `target`: `birds`
- `limit`: `100`
- `page_count`: `20`
- `dry_run`: `false`
- `retry`: `false`
- `update_checklist`: `true`

The scheduled job uploads JSON/Markdown summary artifacts, writes a GitHub job
summary, and commits the running checklist when a real import changes it.

## RevenueCat Reconciliation Health Automation

The **RevenueCat Reconciliation Health Monitor** runs at minutes 7, 22, 37, and
52, after the quarter-hour database dispatches. It resolves the production
service-role key at runtime through the Supabase CLI and calls only the
aggregate `get_revenuecat_reconciliation_health()` RPC. No subscriber identity
is written to logs or artifacts.

Scheduled runs warn and fail at an oldest due age of 30 minutes, become critical
at 60 minutes, and warn immediately on any expired lease. A monitor request has
a 15-second deadline and 64 KiB response ceiling. A failed run therefore means
the queue is overdue, a worker lease expired, or the monitor could not read
health. Start with the structured reconciliation health event and queue error
codes described in the RevenueCat release gate; preserve claim fencing and let
the durable worker recover.

## Scan Media Health Automation

The **Scan Media Health Monitor** workflow runs every 30 minutes and can also be
started manually from GitHub Actions. It resolves the production service-role
key at runtime through the Supabase CLI, calls `/scan-media-health`, writes JSON
and Markdown summary artifacts, and appends the Markdown report to the job
summary. The Markdown report includes an **Incident Actions** table that maps
each issue code to an owner, next step, runbook, and sample-field hint; use that
table as the first triage view before opening raw database rows. It also
includes a visible **Sample Preview** table with the first sample row for each
issue code. Expand the per-issue sample blocks or download the
`scan-media-health-summary-<run_number>` artifact when you need the complete
sample set.

Scheduled runs use:

- `limit`: `25`
- `recent_scan_limit`: `250`
- `fail_on`: `critical`

Warnings are visible in the summary but do not fail the scheduled run. A failed
run means the endpoint returned `critical` or the monitor could not reach the
service-role endpoint. Start triage from the issue code:

- `stuck_ingestion_jobs`: inspect `scan_ingestion_jobs.stage`,
  `lock_expires_at`, `retry_after`, `manifest_checksum`, `upload_session_ids`,
  and `last_error`, then check the matching `scan_ingestion_intents` row for
  `resumable`, `inline_media_redacted`, and `payload_checksum`. Retryable rows
  with resumable intents are claimed by `replay-scan-ingestion`; rows with
  redacted inline media still require client retry. If the stuck job still has
  staged `scan_media_assets`, `reconcile-scan-media-assets` will keep those rows
  pending while the lease or retry window is active, mark the job complete after
  a successful media repair, or mark it `failed_terminal` after the abandonment
  TTL.
- `ingestion_jobs_missing_intent` / `ingestion_intents_not_resumable`: inspect
  `scan_ingestion_jobs` plus `scan_ingestion_intents`. Missing intents mean the
  accepted job predates the durable outbox or the intent write failed; non-
  resumable intents intentionally redacted inline media bytes and depend on the
  iOS queue to retry with durable staged media.
- `retryable_ingestion_jobs_past_due`: confirm the
  `replay_scan_ingestion_every_five_minutes` cron job is scheduled, then inspect
  `/functions/v1/replay-scan-ingestion` logs for dispatch failures. Rows that
  remain past due with `inline_media_redacted = true` are expected to wait for
  the iOS queue. Rows with `status = 'failed_terminal'` and
  `stage = 'server_replay_limit_reached'` exhausted the 10-claim server replay
  ceiling and should be reviewed as terminal incidents, not rescheduled by hand
  unless the replay payload or backend bug has been fixed first. If `last_error`
  starts with `insertScan: column reference "image_url" is ambiguous`, first
  confirm migration
  `20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql` has reached
  production; retrying before that migration is deployed will only re-create the
  same failed job. For a manual service-role retry after the underlying error is
  fixed, POST `{ "limit": 5, "awaitInvocations": true }` to
  `/functions/v1/replay-scan-ingestion`.
- `video_scan_missing_captured_media_video`: inspect the scan's
  `video_storage_urls`, `captured_media`, and ready playback
  `scan_media_assets`; repair should go through `reconcile-scan-media-assets` or
  the local `.mp4` restore path.
- `video_scan_missing_ready_playback_asset`: run or inspect
  `refresh_scan_media_assets(scan_id)` for the sampled scan after confirming
  `video_storage_urls` points at durable playback media. If the health sample
  also shows `captured_media_has_video = true`, the refresh should rebuild a
  ready playback row from the manifest; if it only has legacy arrays, the
  refresh falls back to `video_storage_urls` and chooses a poster thumbnail from
  `image_storage_urls`. If the refresh still leaves `ready_video_asset_count`
  below the durable video count, run `reconcile-scan-media-assets` with
  `dryRun = true` before allowing a repair.
- `audio_scan_missing_ready_audio_asset`: confirm migrations
  `20260711143348_repair_scan_media_assets_audio_constraints.sql` and
  `20260711171512_backfill_missing_ready_audio_assets.sql` reached production.
  The first permits normalized audio rows; the second makes standalone audio
  part of `refresh_scan_media_assets(...)` and backfills every scan with a
  durable `audio_storage_urls` entry. After deploy, rerun the health monitor. If
  a sample remains, call `refresh_scan_media_assets(sample_scan_id)` and compare
  the ready audio URLs to `audio_storage_urls` before touching R2; the durable
  recording must be preserved.
- `explore_video_missing_thumbnail`: inspect `explore_post_media.thumbnail_url`
  and the source scan's first safe image/poster thumbnail.
- Blank standalone-audio `explore_post_media.thumbnail_url`: deploy
  `backfill-explore-audio-spectrograms`, then invoke it with the service-role
  bearer token in bounded WAV-only batches while `generated_count` is greater
  than zero. Review `unsupported_count` separately; legacy non-WAV recordings
  intentionally keep playback plus the volume fallback rather than failing
  publication.
- `latest_reconciliation_run_not_clean`: inspect
  `scan_media_reconciliation_runs.errors` before rerunning the worker. Repeated
  `23505` errors naming `scan_media_assets_scan_id_order_index_key` indicate the
  legacy global scan/order constraint is still deployed; apply
  `20260720230648_repair_scan_media_asset_uniqueness.sql`, verify its partial
  indexes, and use a zero-error dry run before the live reconciliation.

Manual dispatch can use `fail_on = warning` for stricter validation before a
media-path release, or `fail_on = never` to collect a non-gating diagnostic
snapshot.

For one-off triage of a monitor sample, start with the scan-specific checks
below using the sampled `scan_id`:

```sql
SELECT
    s.id,
    s.user_id,
    s.image_storage_urls,
    s.video_storage_urls,
    s.captured_media,
    COUNT(*) FILTER (
        WHERE assets.status = 'ready'
          AND assets.kind = 'video'
          AND assets.role = 'playback'
    ) AS ready_video_asset_count
FROM public.scans s
LEFT JOIN public.scan_media_assets assets ON assets.scan_id = s.id
WHERE s.id = '<scan_id>'::UUID
GROUP BY s.id;

SELECT *
FROM public.scan_ingestion_jobs
WHERE scan_id = '<scan_id>'::UUID;

SELECT *
FROM public.scan_ingestion_intents
WHERE scan_id = '<scan_id>'::UUID;
```

If the scan row exists and the only drift is a missing ready playback asset,
refresh that scan and rerun the monitor with `fail_on = never`:

```sql
SELECT public.refresh_scan_media_assets('<scan_id>'::UUID);
```

If an ingestion job has no matching intent and the scan row does not exist,
there is no durable server replay payload to reconstruct; mark it as a
client-owned retry or a terminal ingestion failure after confirming there are no
staged `scan_media_assets` or upload-session objects worth repairing.

## Manual Taxonomy Import

Use **Actions > Import Community Taxonomy > Run workflow** when the deployed
Community Taxonomy endpoints are healthy and the next bounded GBIF batch should
be imported.

Recommended first production run after a deploy:

- `target`: `birds`
- `limit`: `100`
- `page_count`: `1`
- `dry_run`: `true`
- `retry`: `false`
- `update_checklist`: `true`

If that passes, run the same workflow again with `dry_run = false`. The workflow
uses `SUPABASE_ACCESS_TOKEN` to resolve the project service-role key at runtime
and constructs `https://qlarqavoqhkuwzmevrmf.supabase.co` from the project ref,
so operators do not need to paste service-role credentials locally.

For routine runs after the first clean production import, `dry_run = false` is
acceptable. The workflow uploads a JSON/Markdown summary artifact for every run
and, when `update_checklist = true`, commits
`docs/backend-and-data/07-community-taxonomy-import-checklist.md` after real
imports. Use `page_count = 10...20` only after several successful smaller runs.

## Local Emergency Fallback

Only use the local path when GitHub Actions is unavailable.

```bash
cd /Users/emreerdener/Developer/merian

deno check --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/auth.ts \
  services/supabase/functions/_shared/claimsAuth.ts \
  services/supabase/functions/_shared/edgeHandler.ts \
  services/supabase/functions/_shared/http.ts \
  services/supabase/functions/_shared/aws.ts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/mediaBudgets.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/_shared/encoding.ts \
  services/supabase/functions/_shared/concurrency.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/_shared/identify/latencyDb.ts \
  services/supabase/functions/_shared/identify/latencyDb_test.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility_test.ts \
  services/supabase/functions/_shared/scanIngestionIntents_test.ts \
  services/supabase/functions/_shared/scanIngestionJobs_test.ts \
  services/supabase/functions/_tests/auth.test.ts \
  services/supabase/functions/_tests/scanMediaIngestionContract.test.ts \
  services/supabase/functions/_tests/migrationMediaContract.test.ts \
  services/supabase/functions/_tests/privilegedRoutineMigrationContract.test.ts \
  services/supabase/scripts/audit_privileged_routine_acl.ts \
  services/supabase/scripts/audit_privileged_routine_acl_test.ts \
  services/supabase/scripts/monitor_scan_media_health.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/generate-upload-urls/index.ts \
  services/supabase/functions/generate-upload-urls/storage_test.ts \
  services/supabase/functions/update-public-avatar/index.ts \
  services/supabase/functions/update-public-display-name/index.ts \
  services/supabase/functions/identify-multimodal/index.ts \
  services/supabase/functions/identify-multimodal/index.test.ts \
  services/supabase/functions/update-scan-context/index.ts \
  services/supabase/functions/insight-chat/index.ts \
  services/supabase/functions/scan-media-health/index.ts \
  services/supabase/functions/auto-purge-nonbio/index.ts \
  services/supabase/functions/delete-scan/index.ts \
  services/supabase/functions/replay-scan-ingestion/index.ts

deno test --config services/supabase/functions/deno.json \
  --allow-read=docs/contracts \
  --allow-read=services/supabase/functions/identify-multimodal/index.ts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/_shared/identify/latencyDb_test.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility_test.ts \
  services/supabase/functions/_shared/scanIngestionIntents_test.ts \
  services/supabase/functions/_shared/scanIngestionJobs_test.ts \
  services/supabase/functions/_tests/auth.test.ts \
  services/supabase/functions/_tests/scanMediaIngestionContract.test.ts \
  services/supabase/scripts/audit_privileged_routine_acl_test.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/update-public-avatar/avatar_test.ts \
  services/supabase/functions/_tests/updatePublicDisplayName.test.ts \
  services/supabase/functions/identify-multimodal/index.test.ts \
  services/supabase/functions/insight-chat/guards_test.ts \
  services/supabase/functions/insight-chat/prompt_test.ts \
  services/supabase/functions/scan-media-health/health_test.ts \
  services/supabase/functions/replay-scan-ingestion/worker_test.ts \
  services/supabase/functions/generate-upload-urls/storage_test.ts

deno test --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/migrationMediaContract.test.ts \
  services/supabase/functions/_tests/privilegedRoutineMigrationContract.test.ts

make validate-supabase-migrations
make test-supabase-privileged-routines
```

For local emergency migration pushes that should avoid `supabase link`, export a
database URL first:

```bash
export SUPABASE_DB_URL='postgresql://...'
export MERIAN_DATABASE_URL="$SUPABASE_DB_URL"
deno run --frozen \
  --config services/supabase/functions/deno.json \
  --allow-env --allow-net \
  services/supabase/scripts/audit_privileged_routine_acl.ts \
  --report
make db-push
make audit-supabase-privileged-routines
```

Or export the pooler pieces and let the shared script construct the URL:

```bash
export SUPABASE_PROJECT_ID='qlarqavoqhkuwzmevrmf'
export SUPABASE_DB_POOLER_HOST='aws-1-us-east-1.pooler.supabase.com'
export SUPABASE_DB_PASSWORD='...'
export MERIAN_DATABASE_URL="$(bash scripts/supabase-db-url.sh --require)"
deno run --frozen \
  --config services/supabase/functions/deno.json \
  --allow-env --allow-net \
  services/supabase/scripts/audit_privileged_routine_acl.ts \
  --report
make db-push
make audit-supabase-privileged-routines
```

Only after the post-push audit passes:

```bash
make functions-deploy
```

If neither `SUPABASE_DB_URL` nor the pooler pieces are set, `make db-push` falls
back to the linked-project CLI behavior. `supabase link` reaches Supabase's
Management API to retrieve remote project status before it writes local link
metadata. A `504` at that step is a transient remote/status lookup failure, not
a migration failure. The GitHub workflow intentionally avoids that status lookup
by requiring an explicit database connection and using `db push --db-url`
instead. Direct Supabase database hosts can resolve to IPv6-only addresses; use
the pooler connection string in CI when a runner cannot reach IPv6. The local
configuration uses the current `[local_smtp]` section. It also keeps Apple Auth
enabled for integration testing, so local CLI commands need
`SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` in the environment. Schema-only CI scopes
an explicit non-secret placeholder to the individual CLI steps; it never
supplies or overwrites the hosted Apple credential. For local schema-only work,
a placeholder is sufficient. Use a real development credential only when
exercising the Apple OAuth flow.

## Internal Admin Release

The private admin system has a strict dependency order because the browser must
never receive direct table access or a service-role key:

1. Apply `20260719161112_add_internal_admin_foundation.sql` before exposing any
   admin route or deploying `/report-user`.
2. Confirm the private schema, explicit RPC grants, direct-table denial,
   moderation projection filters, usage triggers, price seeds, and historical
   backfill completed.
3. Deploy `/report-user` and every changed transitive consumer of
   `_shared/aiUsage.ts` immediately after the schema. Do not deploy a writer
   before `record_ai_usage_event` exists.
4. Deploy public-web/iOS projection consumers and the native Report user UI.
5. Deploy `apps/admin` as a separate project rooted at `apps/admin`; attach only
   `admin.naturebook.earth` and only the three public environment variables.
6. Add the exact production Auth callback, verify Google/TOTP, bootstrap the
   first owner only after their first Google sign-in, and complete the role and
   revocation smoke matrix.

Required local checks before the database push:

```bash
supabase --workdir services db reset
supabase --workdir services test db \
  services/supabase/tests/admin_foundation_security.sql \
  services/supabase/tests/admin_review_ai.sql \
  --local
supabase --workdir services db lint --local --schema public,internal
supabase --workdir services db advisors --local --type security
supabase --workdir services db advisors --local --type performance

deno test \
  --allow-read=services/supabase/migrations \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_tests/adminFoundationMigration.test.ts \
  services/supabase/functions/_shared/aiUsage_test.ts \
  services/supabase/functions/report-user/db.test.ts

cd apps/admin
npm ci
npm run typecheck
npm test
npm run build
```

After the migration, query grants as a non-owner runtime role or run the pgTAP
security suite against the candidate database. `anon` must not execute admin
RPCs; `authenticated` must not select `internal`, `user_reports`, or
`ai_usage_events`; and `record_ai_usage_event` must remain service-role-only.

The admin app is a separate Next.js deployment, not part of the public web
project. Its environment allowlist is:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
NEXT_PUBLIC_ADMIN_ORIGIN=https://admin.naturebook.earth
```

Fail the release if the deployment includes `SUPABASE_SERVICE_ROLE_KEY`, direct
database credentials, a Gemini key, or analytics credentials. Roll back the
frontend/DNS independently if needed; preserve the internal schema, audit rows,
review history, notes, moderation fields, and AI ledger. Database correction is
always a forward migration.

The complete owner-bootstrap, smoke-test, pricing, recovery, incident, and
rollback procedures are in
[`11-internal-admin-operations.md`](./11-internal-admin-operations.md).

## Post-Deploy Smoke Checks

After deployment:

- Confirm `supabase db push` applied the newest migration.
- For `20260725045544_repair_complete_edge_database_contracts.sql`, verify a
  resolved Community request without `explore_published_at` is absent from the
  feed and species-sightings RPC, then publish it with the owner flow and verify
  it appears. Verify a withdrawn request falls back to its original observation
  and a moderated post remains absent. Confirm `service_role` can execute the
  first Field trip achievement projection while API roles cannot, and that the
  service role has `SELECT` on its three source tables without changing their
  existing client RLS policies. On staging, refresh reference images, unshare
  one promoted source, refresh again, and verify its provenance is disqualified
  rather than merely demoted.
- Run the privileged-routine audit in enforcement mode and retain its JSON.
  `PUBLIC` and `anon` must execute no public definer; authenticated and service
  execution must exactly match `internal.privileged_routine_grants`; every
  definer must have an empty search path and the expected caller check.
- For a RevenueCat release, confirm the webhook has both Authorization and HMAC
  signing enabled, send a linked-customer test event, compare the resulting
  tier/expiry with authoritative CustomerInfo, and redeliver the same event to
  prove it returns `duplicate` without advancing `entitlement_version`. Confirm
  the event and customer-state tables remain inaccessible to API roles and the
  duplicate-lookup and state-mutation RPC ACLs are exactly
  anon/authenticated/service-role = `false`/`false`/`true`. Treat elevated `401`
  as credential/signature drift and elevated `502`/`503` as RevenueCat API,
  profile, or database availability; never bypass reconciliation to clear the
  retry queue.
- For an exact external-reference-media suppression, apply its cleanup/write
  prevention migration before deploying dependent functions. Deploy every
  transitive consumer selected for `_shared/externalImagePolicy.ts`,
  `_shared/external.ts`, and `_shared/publicSpeciesProjection.ts` changes,
  including identify/enrichment, Species Dictionary, Explore post detail, and
  `refresh-species-content` surfaces. Query normalized and legacy reference data
  to confirm the denied path is absent, attempt a service-role normalized insert
  to confirm the trigger skips it, then confirm the public first-image helper
  promotes the next permitted URL. For media `605615444`, manually open the
  pictured Brown Tabby scan and verify the European wildcat card remains
  navigable with a non-disturbing replacement or leaf placeholder in Insight,
  Explore, and Species Dictionary. Released clients that fetch GBIF directly
  still require the iOS update.
- For identification-latency releases, confirm the three service-role RPCs and
  RLS-enabled `scan_deferred_context_updates` table exist before calling
  `/update-scan-context`. Submit one free and one Pro image and verify the exact
  expected model in privacy-safe latency logs, one `generateContent` call,
  complete `Server-Timing`, a first result before awards/Field trips, and no
  duplicate foreground/background upload contention. Confirm a delayed context
  update survives both the pre-insert staged path and the completed-scan path.
- For Field trips releases, confirm `field-trips` serves `catalog`,
  `template_detail`, `capture_context`, `start`, `community_publications`,
  `recent_publications`, `challenges_catalog`, `challenge_detail`,
  `join_challenge`, `challenge_publications`, `scan_challenge_hashtags`, and
  `profile_summaries`, plus `apply_scan_progress` and `scan_contributions`,
  after the V1, V2, V3, V4, contextual-guide, and capture-context migrations
  plus the standard-preservation, Forest-retirement, completion-evidence,
  publication-status, credited-progress, first-achievement, lifecycle,
  persistent-contribution, and atomic-hardening follow-ups. Verify
  `capture_context` returns only accessible incomplete standard field trips and
  current-level unfinished targets, orders field trips by recent engagement,
  ignores Seasonal Challenge-specific completions without hiding the shared
  standard field trip, and returns no scan IDs, media, locations, field notes,
  species completion data, or other evidence. Confirm `PUBLIC`, `anon`, and
  `authenticated` cannot execute `public.get_field_trip_capture_context(uuid)`
  while `service_role` can. Verify catalog and template detail return each
  completed item's exact `user_field_trip_item_completions.scan_id`, return no
  media URL, and keep incomplete items evidence-free. Confirm `PUBLIC`, `anon`,
  and `authenticated` cannot execute `public.get_field_trip_catalog(...)` or
  `public.get_field_trip_template_detail(...)`, while `service_role` can.
  Confirm `completed_scan_id` is absent from capture context, public profile
  summaries, publication/challenge snapshots, Explore feed, and map payloads.
  Verify template detail returns `publication_id`/`published_at` only for the
  requesting owner's active non-deleted snapshot. Catalog and public/capture
  projections must remain unchanged, and direct client roles must remain unable
  to execute template detail. Start two standard outings and join one live
  Event, then submit one matching scan and confirm at most one credit in each
  experience. Verify a valid visible `preferred_goal` wins inside its standard
  outing, while missing/stale/foreign/ nonmatching hints fall back
  deterministically. Confirm a delayed upload uses the scan timestamp even after
  the activity period or Event ends. Correct the identification and verify
  unfinished credit moves or disappears, while a completed experience remains
  unchanged. Reapply the same scan concurrently and confirm the scan-first
  uniqueness constraints remain idempotent. `scan_contributions` must return
  every owned standard/Event credit with typed routing and credited-level
  counts, but no media, storage URL, coordinates, place labels, or notes.
  Confirm `PUBLIC`, `anon`, and `authenticated` cannot read
  `field_trip_scan_goal_preferences` or execute
  `public.get_field_trip_scan_contributions(uuid, uuid)`; `service_role` can.
  Enumerate every public-schema `SECURITY DEFINER` function whose name contains
  `field_trip` or `challenge`: `PUBLIC`, `anon`, and `authenticated` must have
  no execute privilege, while effective `service_role` execution must match the
  central allowlist exactly. Trigger-only/internal helpers remain denied. Insert
  a scan through the ingestion-intent path and confirm standard/Event updates
  plus preference, first-achievement state, and receipt commit together. Inject
  an Event RPC failure and confirm all of them roll back; retry the unchanged
  scan and confirm the stored result is returned. Publish a completed outing and
  verify its snapshot item rows reference the returned publication ID. While
  Events are staged, verify a physical non-allowlisted account and ghost user
  see Outings but not the Events segment, requests, badges, routes, or hashtag
  suggestions; verify the allowlisted tester and simulator still see the full
  Events flow. Before public Events release, set the client release flag
  intentionally, promote the gated bundled changelog entry, update the rollout
  documentation and test lock, and rerun the Field trips iOS/Deno suites plus an
  unsigned device build. No backend deploy is implied unless a backend contract
  changed independently. Publishing a Field trip or challenge entry must not
  write `explore_posts`, map points, normal Explore post notification rows,
  APNs, widgets, public web share pages, prize rows, or leaderboard rows. Field
  trip comment/reply/followed-publication activity may appear in
  `field_trip_activity_notifications` and the in-app Explore activity feed.
- For Explore author-maintenance releases, apply
  `20260720042641_optimize_explore_author_maintenance.sql` before deploying the
  affected write and read functions. Confirm `PUBLIC`, `anon`, and
  `authenticated` cannot execute `refresh_public_author_identity(uuid)` or
  `repair_explore_post_ownership_for_user(uuid)`, while `service_role` can. Run
  `_tests/exploreIdentityDb.test.ts` with an explicit `SUPABASE_DB_TEST_URL`;
  verify a second converged refresh preserves the user row version. Smoke-test
  one feed/profile read and confirm it performs no maintenance RPC, then share
  or comment once and confirm the public author projection is current. During
  ghost-merge QA, verify scans and Explore posts move to the target account
  before the identity refresh and ghost purge.
- For video-upload contract releases, confirm `scan_media_assets.scan_id` and
  `scan_media_assets.url` are nullable in production
  (`information_schema.columns.is_nullable = YES`) before expecting six-file
  video signing to work.
- Confirm `auto-purge-nonbio` and `delete-scan` were deployed after any
  `_shared/aws.ts` change.
- For public Explore audio, confirm both audio migrations are applied,
  `GEMINI_API_KEY` exists as an Edge secret, and `identify-multimodal`,
  `share-scan-to-explore`, `update-explore-field-notes`, `delete-scan`,
  `backfill-explore-audio-spectrograms`, `auto-purge-nonbio`, and
  `scan-media-health` were deployed together.
- Confirm `/generate-upload-urls` was deployed after any
  `_shared/mediaBudgets.ts` or media-staging contract change.
- Confirm `update-public-avatar` was deployed after
  `20260528120000_add_custom_public_avatars.sql`.
- Inspect Cloudflare R2 lifecycle rules against `docs/r2-lifecycle.json`,
  confirm the seven-day incomplete-multipart abort rule is enabled, and confirm
  there is no enabled expiration rule for `avatars/`.
- Run one staging purge or safe delete and inspect Edge logs for bounded R2
  fanout, delete failures, duration spikes, and memory pressure.
- Upload a custom avatar, then run/inspect scan purge flows and confirm the
  `https://media.merian.app/avatars/{userId}/...` URL remains available.
- Confirm cron-triggered purge endpoints still receive service-role
  authorization from Supabase Vault/pg_net.
- Confirm `community-taxonomy-status` accepts a service-role request with
  `view = coverage` and returns the Birds coverage target quickly.
- Confirm `scan-media-health` accepts a service-role request and returns
  `success = true` with a status of `ok`, `warning`, or `critical`.
- Share approved and policy-violating staging audio. Confirm only approved audio
  creates/reactivates a post, web and iOS playback requires user interaction,
  widgets omit audio-only posts, and moderation logs contain no transcript or
  URL.
- Share an approved WAV and confirm its audio `explore_post_media.thumbnail_url`
  and matching `scan_media_assets.thumbnail_url` point to the same
  `spectrogram-v1-{sha256}.png` under the recording's durable R2 directory.
  Confirm the public home grid, post header, Open Graph metadata, and Twitter
  metadata use the spectrogram while native audio remains user-initiated.
- Run `backfill-explore-audio-spectrograms` on an older blank WAV snapshot and
  confirm `generated_count` advances, a second run reuses the deterministic
  object, and a legacy M4A remains playable with the speaker fallback.
- Re-share the unchanged approved clip and confirm
  `explore_audio_moderation_cache_hit` appears without a second Gemini
  classification. Replace the bytes and confirm a new decision is created. Query
  the attestation table as service role and verify it contains only checksum,
  policy/model, decision, MIME type, byte size, and timestamp.
- On a disposable legacy audio scan with a surviving local file, share once and
  confirm staging promotion populates `audio_storage_urls`, replaces the local
  `captured_media` audio reference, creates a ready normalized audio asset, and
  moderates before publication. Repeat with the local file unavailable and
  confirm no empty or phantom public post is created.
- Delete one disposable audio scan and purge one expired non-biological audio
  scan; confirm their source recordings and derived spectrogram objects
  disappear before their database rows do.
- Submit or replay a short video scan and verify Edge logs do not show
  `Payload Too Large` for the normal six-file manifest or `scan_media_assets`
  nullability errors during staged row creation.
- Share one video scan with extracted audio and one without microphone/audio
  evidence, then verify composer/share payloads preserve `has_audio = true` and
  `false` respectively.
- Confirm `sync-community-taxonomy-index` accepts a tiny `dry_run = true` Birds
  request without advancing `taxonomy_coverage_targets.next_import_offset`.
- Smoke-test `/insight-chat` with `action: "load"` and
  `action:
  "suggest_prompts"` against an owned completed biological scan.
- For an admin release, complete the authentication/role, security-header,
  grouped-review, hidden-content projection, feedback/user audit, and AI-ledger
  smoke matrices in `11-internal-admin-operations.md`. Confirm the deployment
  contains no service-role/direct-database/model/analytics secret.
