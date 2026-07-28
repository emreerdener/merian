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
resumable, paginated full backfill. The script requires `SUPABASE_URL` and a
server key resolved from `SUPABASE_SERVER_API_KEY`, deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, platform `SUPABASE_SECRET_KEYS`, the singular
`SUPABASE_SECRET_KEY` local/manual fallback, or the migration-only
`SUPABASE_SERVICE_ROLE_KEY` fallback. It rate-limits Nominatim requests and
updates only scans that have exact coordinates and a missing semantic location.
Existing database triggers sanitize the scan label and reproject every linked
Explore post while preserving its saved post-level location-sharing choice.

## Production Path

> **Active release evidence gate (2026-07-27):** The DwC-A version-2/public-web
> Explore design repairs are implemented. Do not use this path to promote that
> release unit until the exact-SHA fresh-catalog, complete-CI, production-smoke,
> and hosted maximum-shape criteria in
> [`14-dwca-and-public-web-release-hold-2026-07-27.md`](./14-dwca-and-public-web-release-hold-2026-07-27.md)
> are complete. Unrelated releases must isolate that held unit rather than
> treating the checks below as an exception.

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
   `contents: write` to the taxonomy checklist's isolated follow-up job. The
   import job itself remains `contents: read` and passes only a one-day artifact
   to that writer.
3. Installs the exact reviewed Deno `2.9.2` runtime and Supabase CLI `2.109.1`.
4. Fails fast if required deployment, RevenueCat, DwC-A pseudonym, or dedicated
   R2 Object Read credentials are missing; if either webhook credential is
   shorter than 32 characters; if the DwC-A key is invalid Base64 or decodes
   below 32 bytes; or if an explicitly configured AI quota HMAC override is
   shorter than 32 characters.
5. Validates whole-tree formatting and TypeScript lint across both Edge
   Functions and `services/supabase/scripts`, then runs the discovery-based
   complete tooling gate. That gate type-checks every standard script, runs
   every `*_test.ts` (including ghost-user audit and cleanup), exercises the
   isolated executable Identify response contract, checks the exact generated
   Swift nested/coding-key/decoder block across the complete iOS source graph,
   runs deployed runtime-contract tests, and syntax-checks/tests shell tooling.
   Deployment/provider secrets are scoped only to the individual steps that
   consume them; they are not job-wide environment values and are never
   persisted through `GITHUB_ENV`.
6. Confirms exact set parity between function entrypoints and
   `[functions.<name>]` entries, then verifies every function has a current
   generated local `deno.json`, only approved aliased runtime imports, and a
   graph fully represented by the shared frozen `dependencies.lock`; finally it
   type-checks all entrypoints with the exact local config Supabase will
   discover.
7. Runs focused workflow-policy, shared-helper, AI quota, RevenueCat webhook,
   DwC-A claim/stream/idempotency, and static migration-contract tests in
   addition to the complete tooling gate. The migration execution contract
   enumerates every SQL migration and rejects direct or dynamic
   pipeline-incompatible concurrent index DDL. The public-schema contract
   rejects transaction controls in new files, requires effective RLS, and locks
   final grants/default ACLs plus bounded user-FK index behavior. The
   species-count contract separately preserves its immutable historical
   `BEGIN → LOCK TABLE → final trigger → COMMIT` cutover ordering.
   Source-inspection tests receive explicit read grants because Deno does not
   grant `readTextFile` access merely because a source is in the import graph.
8. Starts a disposable local Postgres instance, applies all pending migrations,
   and discovers every `services/supabase/tests/*.sql` pgTAP fixture through
   `test_database_catalogs.sh`. An empty fixture directory or any failed catalog
   test blocks deployment; there is no curated SQL allowlist to forget when a
   new security contract is added. It then invokes the checked-in recursive
   `deno task test` with an explicit database URL, so route-local tests cannot
   be omitted by a curated CI list and database-backed tests cannot silently
   skip.
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
17. Synchronizes required bucket-scoped R2 Object Read credentials and the
    optional R2 event-ingress secret to Supabase Edge.
18. Resolves a callable production server key plus every real public project key
    through the Management API and masks the selected server value.
19. Synchronizes that exact selected key into the non-reserved
    `MERIAN_SUPABASE_SERVER_API_KEY` Edge fallback. This closes a management
    plane/runtime provisioning gap without changing request transport or trying
    to overwrite a reserved built-in.
20. Reads the stored secret's SHA-256 digest through the pinned CLI and compares
    it with the exact selected key locally. A missing, duplicate, malformed, or
    mismatched digest stops the release without printing the key or digest.
21. Deploys the planned functions in bounded batches. A failed batch is retried
    function-by-function, so a transient graph failure cannot restart the whole
    fleet deployment.
22. Requires every public key to receive `401` from Community Taxonomy status
    before the propagation-aware, format-aware positive suite smoke-tests
    internal functions and PostgREST RPCs, including scan-media health, one-item
    Explore direct-origin reconciliation, and a dry-run bounded GBIF import.
    Positive requests make at most six attempts for transient deployment
    statuses. Final Function failures report endpoint, status, and only whether
    the fixed `X-Merian-Handler: 1` marker was present. Final Data API failures
    are classified separately as PostgREST/RPC diagnostics and do not expect a
    Function marker. Response bodies and request-ID values remain withheld; no
    variable header value is printed.

Local and CI database rebuilds use the exact reviewed Supabase CLI `2.109.1`.
The CLI owns migration transaction and history boundaries. Its normal apply path
wraps pipeline-compatible statements with the history insert, while
pipeline-incompatible statements and immutable historical boundary artifacts can
require standalone handling. New migrations must not add top-level transaction
controls because an embedded commit can split schema state from migration
history. Top-level timeout guards use session `SET` plus matching `RESET`, not
`SET LOCAL`, so they remain effective during fresh replay. Historical applied
files that contain explicit controls remain immutable compatibility artifacts,
not future examples.

Checked-in migrations may not contain `CREATE INDEX CONCURRENTLY`,
`DROP INDEX CONCURRENTLY`, or `REINDEX ... CONCURRENTLY`, including executable
dynamic SQL. Fresh databases replay every file even though production skips
versions already in history. For a populated relation where a blocking index is
unsafe, run the reviewed concurrent command as a separately supervised owner
operation outside a transaction and outside `db push`. Verify both
`pg_index.indisvalid` and `indisready`, then retry the unchanged size-gated
migration. Partitioned relations require valid child indexes before a
metadata-only parent operation. The canonical rules are in
[`13-server-credentials-and-database-release-safety.md`](./13-server-credentials-and-database-release-safety.md).

Actual GBIF taxonomy imports are intentionally separated into
`.github/workflows/import-community-taxonomy.yml`. The deploy workflow only
smoke-tests a dry run; it does not write taxonomy rows or advance import
cursors.

The deployment subset is computed from the TypeScript runtime import graph
rather than a hand-maintained list. Explicit `import type` / `export type` edges
are erased from deployed bundles and therefore excluded from selection; the
whole-tree Deno check still validates them. A route-local runtime change selects
that route. A shared-module change selects every function that transitively
runtime-imports it. A function-local `deno.json` change selects that function.
Changes to `config.toml`, the root dependency manifest, or the shared lock
select the full fleet because they can affect any bundle. New, deleted, or
otherwise unresolvable shared runtime files also fall back to the full fleet.
Docs and test-only changes select no functions. This preserves shared-helper
consistency without paying for an unconditional full-fleet deployment on every
backend commit.

The graph/configuration test compares the sorted function names discovered from
`functions/*/index.ts` with the sorted `[functions.<name>]` names parsed from
`config.toml`. It deliberately has no numeric fleet-size assertion: adding or
retiring a function changes the fleet naturally, while a missing or stale
configuration entry fails with the differing names. Do not repair this class of
failure by changing a count.

Run the complete Supabase tooling preflight from any working directory with:

```bash
make test-supabase-tooling
```

The runner discovers TypeScript and shell tests by naming convention. Do not
replace it with a selected list in CI; use the targeted commands below only to
diagnose a planner or dependency-graph failure.

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

Migration `20260727010340_fix_service_role_authorization_guard.sql` is the
server-key compatibility layer for that in-function check. It preserves legacy
JWT detection, adds PostgREST's protected standard `role` signal for opaque
secret keys, and retains direct migration/repair sessions. It does not change
the execution allowlist. Apply it before privileged-route smoke tests; do not
recover availability by broadening a public RPC grant.

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

WITH probe AS (
    SELECT
        'sb_' || 'secret_probe_' || REPEAT('a', 20) AS server_api_key
)
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

After applying the compatibility migration, run this read-only owner check in
the target environment:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    POSITION(
        'auth.role() IS DISTINCT FROM ''service_role'''
        IN function_row.prosrc
    ) > 0 AS checks_legacy_jwt_role,
    POSITION(
        'CURRENT_SETTING(''role'', TRUE)'
        IN function_row.prosrc
    ) > 0 AS checks_postgrest_role,
    POSITION(
        'SESSION_USER NOT IN (''postgres'', ''service_role'')'
        IN function_row.prosrc
    ) > 0 AS permits_repair_sessions,
    NOT HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.refresh_public_author_identity(uuid)',
        'EXECUTE'
    ) AS authenticated_cannot_refresh_author,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.refresh_public_author_identity(uuid)',
        'EXECUTE'
    ) AS service_role_can_refresh_author
FROM pg_proc AS function_row
WHERE function_row.oid =
    'internal.require_service_role()'::REGPROCEDURE;

ROLLBACK;
```

Require one row with all five booleans `true`. Then share one eligible scan from
the Scan Library and one through the full Insight composer. Both paths must
complete without `service_role authorization required` in Edge/database logs.
The immediate guard repair is database-only and does not require an iOS rebuild.
The complete server-key migration also deploys every function batch that imports
the shared resolver/client and the server-only web app.

After `20260727013416_future_proof_server_key_boundaries.sql`, run the broader
catalog check:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path TO pg_catalog;

SELECT
    TO_REGPROCEDURE(
        'internal.server_api_request_headers(text)'
    ) IS NOT NULL AS sql_header_policy_exists,
    internal.server_api_request_headers(probe.server_api_key) =
        JSONB_BUILD_OBJECT(
            'Content-Type',
            'application/json',
            'apikey',
            probe.server_api_key
        )
        AS opaque_key_uses_apikey_only,
    NOT EXISTS (
        SELECT 1
        FROM pg_proc AS function_row
        JOIN pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname IN ('public', 'internal')
          AND function_row.prosrc ~* 'net[.]http_post'
          AND function_row.prosrc ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    ) AS routines_have_no_bearer_only_server_key,
    NOT EXISTS (
        SELECT 1
        FROM cron.job
        WHERE active
          AND command ~* 'net[.]http_post'
          AND command ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    ) AS active_cron_has_no_bearer_only_server_key,
    NOT EXISTS (
        SELECT 1
        FROM pg_proc AS function_row
        JOIN pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND function_row.prosrc ~*
              'auth[.]role[(][)][[:space:]]*=[[:space:]]*''service_role'''
    ) AS definers_have_no_jwt_only_service_dispatch
FROM probe;

ROLLBACK;
```

Require all five booleans `true`. In addition to both share entry points, smoke
identity refresh after an Explore comment, Field Trip mutation, Community
request, and ghost-profile merge. Exercise one internal route and
`get_owned_explore_media_incidents(uuid)` with the current opaque key, and prove
a real anon/publishable key receives `401` from the internal route. See the
[July 2026 server-key incident report](../incidents/2026-07-server-key-authorization-mismatch.md)
for the full affected-surface and legacy-key shutdown checklist.

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

Treat a `jsonb_to_record(...)` field declared as `TEXT` as wire input, not as a
catalog enum. Validate the allowed strings first, then cast explicitly to the
fully qualified enum type at the write boundary. Otherwise migration replay can
succeed while `plpgsql_check` later reports SQLSTATE `42804` for the embedded
statement. Avoid PL/pgSQL variable names such as `authorization` that collide
with SQL grammar; use a purpose-qualified name such as `authorization_result`.

Durable scan deletion tombstones intentionally reserve a scan UUID forever.
After a fixture exercises deletion or ownerless tombstoning, it must use a new
deterministic UUID for later insert coverage. Do not disable the generation
guard or delete its tombstone merely to make a test reusable. Likewise, when a
migration replaces a trigger to correct lock order, catalog tests must validate
the replacement trigger and function; remove the detached predecessor routine
once all dependencies have moved.

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
triggers. No Edge Function deployment or new secret is required. This already
applied file is an immutable historical explicit-boundary exception; it is not a
template for a new migration.

The migration deliberately takes `SHARE ROW EXCLUSIVE` on `public.scans`.
Existing writes finish first; new scan inserts, updates, deletes, and cascading
owner/species changes wait while one grouped backfill runs, projected totals are
repaired, and the trigger set is swapped. The lock is held until the migration
transaction commits. The migration file must retain its explicit `BEGIN` before
`LOCK TABLE` and final `COMMIT`; PostgreSQL rejects a table lock outside a
transaction block, and removing either boundary also destroys the atomic cutover
guarantee for replay paths that processed this historical file statement by
statement. New migrations leave transaction and migration-history ownership to
the pinned CLI and must not add these controls. Before production deployment,
inspect the planner estimate and physical size:

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
the backfill from the trigger swap, copy this exception into a new migration, or
run `supabase migration repair`. Disposable database validation runs before the
production `db push`, so this failure does not create a hosted migration-history
entry; fix the unapplied migration file and rerun the workflow.

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
`20260725041308_ownerless_account_deletion_tombstones.sql`,
`20260725052337_enforce_account_storage_erasure.sql`,
`20260726041109_fence_storage_erasure_claims.sql`, and
`20260727001630_monitor_account_deletion_health.sql`, plus the shared server-key
transport migration `20260727013416_future_proof_server_key_boundaries.sql` and
user-FK index migration
`20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql`,
`safe-delete`, `reconcile-account-deletions`, `generate-upload-urls`, and
`replay-scan-ingestion`, form one release unit. No new secret is required: the
reaper uses the existing Supabase service-role and R2 values, and the
independent GitHub monitor resolves a server key with the existing
`SUPABASE_ACCESS_TOKEN`. The reaper still requires non-empty `SUPABASE_URL` and
an active server key in the compatibility-named `SUPABASE_SERVICE_ROLE_KEY`
Vault slot (or the documented app-setting fallback); missing values now produce
a critical monitor result. Its current transport sends a modern `sb_secret_...`
Vault key only in `apikey`, or a legacy service-role JWT in both `apikey` and
Bearer Authorization. The value must match an active project server key. Do not
replace only the Vault value; rotate it and the project key together.

The `20260725035737` file is an explicit executable no-op. It is a compatibility
bridge for production run 1461, where its superseded public-only sentinel insert
failed the existing profile-to-Auth foreign key before the migration version was
recorded. The no-op ensures the failed timestamp is recorded without mutating
data. The following forward migration converges both production and any
preview/local catalog that happened to accept the earlier sentinel. Together the
migration sequence:

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
- makes every storage claim require the matching cleaned-up `storage_pending`
  private job while vetoing live profiles and owned scans;
- installs service-only account and storage claim/advance/failure RPCs;
- adds indexed, identity-free aggregate health for active/due age, retries,
  leases, storage backlog, cron state, and credential readiness; and
- schedules `reconcile_account_deletions_every_five_minutes`.

The ownerless migration takes bounded `SHARE ROW EXCLUSIVE` locks in Auth →
scans → public-profile order. A lock timeout is a safe deployment failure; retry
the unchanged migration after the conflicting transaction finishes.

The user-FK migration reuses every valid, ready, non-partial index whose first
key is the FK column. It creates missing indexes inline only for relations no
larger than 32 MiB. It never recursively builds a missing index on a partitioned
parent. Before production deployment, run this read-only inventory:

```sql
WITH missing_user_fk_index AS (
    SELECT DISTINCT
        source_table.oid AS table_oid,
        source_table.relkind AS relation_kind,
        source_namespace.nspname AS schema_name,
        source_table.relname AS table_name,
        source_column.attname AS column_name
    FROM pg_catalog.pg_constraint AS constraint_row
    JOIN pg_catalog.pg_class AS source_table
      ON source_table.oid = constraint_row.conrelid
    JOIN pg_catalog.pg_namespace AS source_namespace
      ON source_namespace.oid = source_table.relnamespace
    JOIN pg_catalog.pg_attribute AS source_column
      ON source_column.attrelid = constraint_row.conrelid
     AND source_column.attnum = constraint_row.conkey[1]
    WHERE constraint_row.contype = 'f'
      AND constraint_row.confrelid IN (
          'public.users'::REGCLASS,
          'auth.users'::REGCLASS
      )
      AND source_namespace.nspname IN ('public', 'internal')
      AND source_table.relkind IN ('r', 'p')
      AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
      AND NOT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_index AS index_row
          WHERE index_row.indrelid = constraint_row.conrelid
            AND index_row.indisvalid
            AND index_row.indisready
            AND index_row.indpred IS NULL
            AND index_row.indexprs IS NULL
            AND index_row.indkey[0] = constraint_row.conkey[1]
      )
)
SELECT
    schema_name,
    table_name,
    column_name,
    relation_kind,
    CASE
        WHEN relation_kind = 'p' THEN 'partitioned parent'
        ELSE pg_catalog.PG_SIZE_PRETTY(
            pg_catalog.PG_RELATION_SIZE(table_oid)
        )
    END AS relation_size,
    CASE
        WHEN relation_kind = 'p' THEN NULL
        ELSE pg_catalog.FORMAT(
            'CREATE INDEX CONCURRENTLY %I ON %I.%I (%I);',
            'idx_'
                || pg_catalog.SUBSTRING(table_name FOR 24)
                || '_'
                || pg_catalog.SUBSTRING(column_name FOR 16)
                || '_'
                || pg_catalog.SUBSTRING(
                    pg_catalog.MD5(
                        schema_name || '.' || table_name || '.' || column_name
                    )
                    FOR 8
                )
                || '_user_fk',
            schema_name,
            table_name,
            column_name
        )
    END AS concurrent_index_command
FROM missing_user_fk_index
ORDER BY schema_name, table_name, column_name;
```

Run each returned concurrent command separately through an owner connection,
outside a transaction and outside `supabase db push`. Inspect any same-named
invalid index left by an interrupted build before dropping and rebuilding it.
For a partitioned parent (relation kind `p`), build an equivalent valid leading
index concurrently on every leaf partition first, then create the parent
partitioned index non-concurrently as a metadata-only operation. Do not run a
single recursive blocking build against the parent.

Require both `indisvalid` and `indisready` before deployment. The migration then
converges without rebuilding the index; its size guard prevents a forgotten
preflight from turning the release into a prolonged write outage.

Run before deployment:

```bash
cd services/supabase/functions
deno task test
cd ../../..

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/scripts,services/supabase/tests/account_deletion_security.sql,services/supabase/config.toml,.github/workflows \
  services/supabase/functions/_tests/safeDelete.test.ts \
  services/supabase/functions/_tests/accountDeletionCoverage.test.ts \
  services/supabase/functions/_tests/accountDeletionMigrationContract.test.ts \
  services/supabase/functions/safe-delete/storageWorker_test.ts \
  services/supabase/scripts/monitor_account_deletion_health_test.ts

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

SELECT *
FROM public.get_account_deletion_health();

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

WITH claim_definition AS (
    SELECT pg_catalog.LOWER(
        pg_catalog.PG_GET_FUNCTIONDEF(
            'public.claim_pending_storage_deletions(integer)'::REGPROCEDURE
        )
    ) AS body
)
SELECT
    pg_catalog.POSITION(
        'inner join internal.account_deletion_jobs' IN body
    ) > 0 AS joins_private_job,
    pg_catalog.POSITION(
        'deletion_job.status = ''storage_pending''' IN body
    ) > 0 AS requires_storage_pending,
    pg_catalog.POSITION(
        'deletion_job.cleanup_completed_at is not null' IN body
    ) > 0 AS requires_cleanup,
    pg_catalog.POSITION(
        'from public.users as live_user' IN body
    ) > 0 AS vetoes_live_profile,
    pg_catalog.POSITION(
        'from public.scans as owned_scan' IN body
    ) > 0 AS vetoes_owned_scans
FROM claim_definition;

SELECT COUNT(*) AS fenced_due_storage_rows
FROM public.pending_storage_deletions AS deletion
LEFT JOIN internal.account_deletion_jobs AS deletion_job
  ON deletion_job.user_id = deletion.target_user_id
WHERE deletion.status IN ('pending', 'processing')
  AND deletion.next_attempt_at <= NOW()
  AND (
    deletion_job.status IS DISTINCT FROM 'storage_pending'
    OR deletion_job.cleanup_completed_at IS NULL
    OR deletion_job.storage_completed_at IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM public.users AS live_user
      WHERE live_user.id = deletion.target_user_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.scans AS owned_scan
      WHERE owned_scan.user_id = deletion.target_user_id
    )
  );
```

Expected: at least one validated restrictive profile/Auth foreign key, a
nullable scan owner plus validated ownerless check, zero invalid ownerless
scans, zero legacy sentinel scans/profiles, zero synthetic all-zero Auth users,
all five claim-fence booleans true, an active cron, and
`reaper_cron_active = true` plus `reaper_credentials_configured = true` in the
health row. The other health fields reflect the current aggregate queue and must
not contain identifiers. The credential boolean checks nonblank effective values
only; it does not validate the URL or key.

Manually dispatch `Account Deletion Health Monitor` once after the migration.
The run must complete successfully under the Production environment and retain
both summary artifacts. Its defaults fail on warning: 10/30 minutes for oldest
claimable work, 27/36 hours for oldest active work, and 25/100 jobs for
warning/critical backlog. The end-to-end threshold intentionally includes the
mandatory 25-hour delayed verification window.

`fenced_due_storage_rows` is an audit count, not an expected-zero correctness
gate. A nonzero result can identify historical outbox rows that the new routine
correctly leaves inert. Review those rows under restricted operator access; do
not sweep their prefixes or make them actionable merely to clear the count.

Smoke-test with a staging-only account that owns at least one scan. Confirm:

1. `/safe-delete` returns `200 completed` or `202 pending`;
2. the retained scan has `user_id IS NULL` and `is_tombstoned = true`;
3. all compatibility media URLs and structured media references are empty, and
   its exact location/elevation, semantic location, device context, notes, and
   custom tags are null/empty;
4. anonymous table access does not return the tombstoned scan;
5. the original public profile is absent and one storage job exists with all
   five canonical prefixes;
6. before deletion, a deliberately stale/orphaned outbox row for a separate live
   fixture account cannot be returned by `claim_pending_storage_deletions`;
7. recreating the original public profile while the job is active is rejected;
8. a new upload-signing request is rejected while deletion is active;
9. Auth remains present through `storage_pending`, and disappears only after an
   empty delayed verification pass permits `auth_pending`; and
10. the terminal job is `completed` with `user_id IS NULL`.

The independent workflow is the SLA/stuck-job alert and is intentionally offset
from the reaper. Critical conditions are a disabled/missing cron, absent reaper
credentials, orphaned active storage work, oldest-due or end-to-end SLA
breaches, and critical backlog. Any retry error, expired lease, warning age, or
warning backlog is a warning; the default policy fails that run. Continue
structured-log alerts on `account_deletion_attempt_deferred`,
`account_deletion_reconciliation_deferred`, and
`account_storage_erasure_deferred` for immediate dependency failures.

On alert:

1. open the workflow's identity-free Markdown/JSON summary; do not print user
   IDs into logs, tickets, or chat;
2. if cron/configuration is false, restore the exact named cron and the Vault
   URL/service credential, then manually rerun the health workflow;
3. otherwise inspect bounded `safe-delete`, `reconcile-account-deletions`, R2,
   and Auth logs for the failing dependency;
4. for an orphan critical, use restricted operator access to classify the exact
   outbox row, matching private job, request/audit provenance, live profile, and
   owned scans without copying identifiers outside that session;
5. if deletion intent is legitimate, restore it only through the reviewed
   durable request boundary; if the marker is stale or unauthorized, preserve
   evidence and prepare a reviewed forward metadata migration after provenance
   is understood;
6. repair the dependency and let claim-fenced, database-backed retries resume;
   and
7. escalate if oldest active age reaches 36 hours or backlog reaches 100.

Never recover a `pending` or `storage_pending` job by deleting Auth manually or
by editing a cursor, lease, or next-attempt timestamp. Never blanket-delete
outbox rows, sweep their prefixes, make them due, or run ad-hoc SQL merely to
clear an alert. A legacy Auth-first incident can be placed into the durable
pipeline only after an operator verifies the recorded UUID and invokes
`request_account_deletion` through a reviewed service-role or owner session.

Do not roll back by dropping the private table, unique outbox index, or cron;
that would discard deletion intent. Fix forward while keeping the reaper
available.

#### Account-scoped image-loss containment and repair

The July 2026 incident response adds two migrations and one Edge Function:

- `20260726041109_fence_storage_erasure_claims.sql` is the containment boundary
  and must reach Postgres before any further reconciliation invocation is
  trusted;
- `20260726041338_repair_owned_scan_image_references.sql` installs the atomic
  metadata repair RPC; and
- `repair-scan-image` exposes owner-authenticated inspection and repair.

The normal workflow order—migrations before Edge bundles—is required. The SQL
claim fence protects against the existing worker immediately after migration; it
is not dependent on deploying a new worker bundle. If the five-prefix migration
is present but the fence migration is absent, treat account-storage
reconciliation as unsafe and apply the forward fence immediately. If deployment
is blocked, pause only the named account-deletion reconciliation cron under the
normal reviewed change-control procedure, record its prior state, and restore it
only after all claim-fence booleans below are true. Do not drop the job or
discard deletion intent.

Before deployment, retain successful output from:

```bash
cd services/supabase/functions
deno task test
cd ../../..

make validate-supabase-migrations

supabase --workdir services db start
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/account_deletion_security.sql \
  services/supabase/tests/scan_image_repair_security.sql
```

After deployment:

1. confirm both migration versions are recorded;
2. require all five claim-definition booleans above to be true;
3. record and review `fenced_due_storage_rows` without printing UUIDs or keys;
4. verify a stale outbox row for a live staging fixture remains unclaimable;
5. call `/repair-scan-image` without `restored_object_key` for one healthy, one
   missing, and one unreferenced owned fixture URL;
6. repair one missing staging fixture and verify the new durable R2 object,
   ordered scan array, captured-media path, normalized asset, and Explore
   snapshot;
7. repeat the repair request and prove it is safe/idempotent; and
8. review request-correlated logs for promotion or rollback failures without
   retaining raw object keys in public incident notes.

Repository mitigation, production deployment, production runtime verification,
and recovered-object coverage are separate status fields. Do not call the
incident resolved merely because the migration and function exist in `main`. The
canonical evidence, leading cause, recovery limits, and exit criteria are in the
[July 2026 incident report](../incidents/2026-07-account-scoped-r2-image-loss.md).

#### Explore media-health and reversible-quarantine release gate

Ship the Explore response to unexpected object loss as one compatibility unit:

1. `20260726144647_add_explore_media_quarantine_lifecycle.sql` commits the two
   enum values separately;
2. `20260726144754_implement_explore_media_quarantine_state_machine.sql` adds
   item/post health, private leases and continuity, projection gates,
   notifications, owner/service RPCs, audit rows, repair reset, and the
   five-minute cron;
3. `20260726174555_align_explore_author_publication_contract.sql` aligns author
   count/preview/grid visibility and adds owner and service aggregate summaries;
4. deploy `reconcile-explore-media-health`, `get-explore-media-incidents`, and
   `ingest-r2-media-events`;
5. redeploy `get-explore-author-profile`, `get-explore-author-posts`, and
   `send-push-notification`;
6. verify Vault has `SUPABASE_URL` and an active current or legacy server key in
   the compatibility-named `SUPABASE_SERVICE_ROLE_KEY` slot, then configure
   bucket-scoped Object Read credentials in `R2_READ_ACCESS_KEY_ID` /
   `R2_READ_SECRET_ACCESS_KEY` at the GitHub and Supabase boundaries;
7. optionally configure the same high-entropy `R2_EVENT_WEBHOOK_SECRET` in
   GitHub/Supabase and the trusted Cloudflare Queue consumer; and
8. release the iOS owner banners, notification routes, repair refresh, and scan
   deletion warning only after the backend owner endpoints are available.

Do not combine the enum migration into the state-machine transaction: PostgreSQL
cannot safely use a newly added enum value in the same transaction. The
state-machine migration initializes existing rows as healthy/due and does not
claim historical loss without R2 evidence.

Pre-deploy:

```bash
make validate-supabase-migrations

deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/reconcile-explore-media-health/worker_test.ts

supabase --workdir services db start
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/explore_media_quarantine_security.sql \
  services/supabase/tests/scan_image_repair_security.sql
```

Use a disposable database for the integration tests. The tracked local
configuration uses the current `[local_smtp]` section expected by the pinned
Supabase CLI.

Post-deploy structural checks:

```sql
SELECT version
FROM supabase_migrations.schema_migrations
WHERE version IN (
  '20260726144647',
  '20260726144754',
  '20260726174555'
)
ORDER BY version;

SELECT
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'service_role',
    'public.claim_explore_media_health_checks(integer,integer)',
    'EXECUTE'
  ) AS service_can_claim,
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'authenticated',
    'public.claim_explore_media_health_checks(integer,integer)',
    'EXECUTE'
  ) AS client_can_claim,
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'authenticated',
    'public.get_owned_explore_media_incidents(uuid)',
    'EXECUTE'
  ) AS owner_can_list_incidents,
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'authenticated',
    'public.get_owned_explore_publication_summary(uuid)',
    'EXECUTE'
  ) AS owner_can_read_publication_summary,
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'authenticated',
    'public.get_explore_publication_health_summary()',
    'EXECUTE'
  ) AS client_can_read_global_summary,
  pg_catalog.HAS_FUNCTION_PRIVILEGE(
    'service_role',
    'public.get_explore_publication_health_summary()',
    'EXECUTE'
  ) AS service_can_read_global_summary;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'reconcile_explore_media_health_every_five_minutes';
```

Require all three migration versions, `service_can_claim = true`,
`client_can_claim = false`, `owner_can_list_incidents = true`,
`owner_can_read_publication_summary = true`,
`client_can_read_global_summary = false`,
`service_can_read_global_summary = true`, and one active `*/5 * * * *` cron row.

Staging smoke matrix:

1. publish a two-image fixture and verify Feed, Map, author profile, detail,
   notifications, and public share agree;
2. delete one fixture object through the reviewed staging storage path;
3. verify the first direct check yields `suspected_missing` and leaves the item
   public;
4. after at least five minutes, verify the second direct `404` yields `missing`,
   the item is omitted, and the post remains public as `degraded`;
5. delete the second fixture object and repeat confirmation; verify
   `quarantined`, every public surface omits the post, and the owner endpoint,
   in-app notification, push, Profile explanation, and Scan Library banner
   expose recovery;
6. verify the post row, `unshared_at`, likes, and comments are unchanged;
7. restore one object and run reconciliation; verify the post automatically
   returns as degraded;
8. restore the second object; verify healthy state, one in-app `media_restored`,
   no restore push, and no owner banner;
9. mark the fixture author-unpublished and prove a later healthy check does not
   republish it; and
10. verify author-profile `published_post_count`, `preview_posts`, and all
    `get-explore-author-posts` pages contain the same canonical visible set;
11. verify the author-post response supplies `next_cursor` until the final page
    and `null` at the end; and
12. run `refresh_explore_post_media` while the fixture is quarantined and prove
    the private continuity ledger preserves both missing statuses.

Review recent run health without printing media URLs:

```sql
SELECT
  started_at,
  finished_at,
  status,
  claimed_count,
  healthy_count,
  missing_observation_count,
  retryable_error_count,
  error_count
FROM public.explore_media_health_reconciliation_runs
ORDER BY started_at DESC
LIMIT 20;
```

Alert when no successful run exists in 15 minutes, oldest due active media is
over 15 minutes, leases expire repeatedly, result recording fails, or confirmed
loss rises suddenly. A Cloudflare event may make a row due but is never proof;
scheduled direct-origin reconciliation is the correctness path.

The deploy workflow also invokes `get_explore_publication_health_summary()` with
the service-role key and prints only aggregate totals. Treat
`affected_author_count` as the production scope signal: `1` confirms an
account-scoped cohort at that moment; any larger value requires investigation of
additional owners. This smoke must never print owner IDs or media keys.

Rollback is fix-forward. Do not clear `missing`, set posts healthy in bulk,
delete notifications, or rewrite `unshared_at`. If the worker bundle is faulty,
pause only `reconcile_explore_media_health_every_five_minutes`, preserve item
and audit state, deploy the correction, then resume the same job. Existing
quarantined posts remain preserved while checks are paused.

Canonical product, schema, API, security, recovery, and monitoring details are
in
[Explore Media Health and Quarantine](./12-explore-media-health-and-quarantine.md).

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
`20260725052339_bound_dwca_export_work.sql`, and the ordered source-bound pair
`20260725175312_bound_dwca_export_source_bytes.sql` /
`20260725180321_validate_dwca_export_source_bounds.sql`, and
`20260726025103_snapshot_dwca_export_sources.sql`, followed by
`20260726230837_scale_dwca_export_continuations.sql` and
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`,
then `20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql`, then
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql`, must land with
`request-export-dwca`, the resumable `export-dwca` bundle, `download-dwca`, and
`reconcile-dwca-archive-cleanup`. This describes migration/bundle compatibility,
not production sign-off; the active evidence gate must still pass before
promotion. Before the first deployment, generate a dedicated version-1 pseudonym
key:

The same final migration must precede the updated `delete-scan`, all four
scan-producing routes, `replay-scan-ingestion`, and
`reconcile-scan-media-assets`, and must deploy `reconcile-scan-deletions` in the
same release unit. Confirm `internal.scan_deletion_tombstones` is RLS-enabled
and has no API-role table privileges; `request_scan_deletion(uuid,uuid)` and
`complete_scan_deletion(uuid,uuid)`,
`request_nonbiological_scan_retention_deletions(integer)`,
`claim_scan_deletion_jobs(...)`, `release_scan_deletion_job(...)`, and
`get_scan_deletion_health()` must be executable only by `service_role`. In
staging, interrupt deletion after its request transaction, stop the client
retry, verify a delayed scan update and owner-row recovery both fail, then let
the independent server reaper finish it. R2 404 must converge to success, the
scan row must disappear, and the private tombstone must remain completed with
`user_id`, `claim_token`, and `lease_expires_at` null. Finally run account
deletion on a fixture with a pending scan deletion tombstone and verify the same
unlink/completion state while the scan UUID fence remains.

Before pushing the migration, run a read-only legacy-data audit. Any nonzero
count will make constraint validation stop the deployment and must be corrected
through a reviewed data repair, not by dropping or leaving the constraint
unvalidated:

```sql
SELECT
    COUNT(*) FILTER (
        WHERE NOT internal.text_array_elements_are_bounded(
            video_storage_urls,
            5,
            4096
        )
    ) AS invalid_video_arrays,
    COUNT(*) FILTER (
        WHERE NOT internal.text_array_elements_are_bounded(
            audio_storage_urls,
            5,
            4096
        )
    ) AS invalid_audio_arrays,
    COUNT(*) FILTER (
        WHERE NOT internal.text_array_elements_are_bounded(
            custom_tags,
            50,
            256
        )
    ) AS invalid_tag_arrays,
    COUNT(*) FILTER (
        WHERE user_identification_override IS NOT NULL
          AND OCTET_LENGTH(user_identification_override) > 1024
    ) AS invalid_override_text
FROM public.scans;
```

After migration replay, verify the API-role boundary explicitly:

```sql
SELECT
    HAS_TABLE_PRIVILEGE('anon', 'public.scans', 'INSERT')
        AS anon_can_insert,
    HAS_TABLE_PRIVILEGE('anon', 'public.scans', 'UPDATE')
        AS anon_can_update,
    HAS_TABLE_PRIVILEGE('anon', 'public.scans', 'DELETE')
        AS anon_can_delete,
    HAS_TABLE_PRIVILEGE('authenticated', 'public.scans', 'INSERT')
        AS authenticated_can_insert,
    HAS_TABLE_PRIVILEGE('authenticated', 'public.scans', 'DELETE')
        AS authenticated_can_delete;

SELECT grantee, column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'scans'
  AND privilege_type = 'UPDATE'
  AND grantee IN ('anon', 'authenticated')
ORDER BY grantee, column_name;

SELECT
    checks.signature,
    HAS_FUNCTION_PRIVILEGE('anon', checks.signature, 'EXECUTE')
        AS anon_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        checks.signature,
        'EXECUTE'
    ) AS authenticated_can_execute,
    HAS_FUNCTION_PRIVILEGE(
        'service_role',
        checks.signature,
        'EXECUTE'
    ) AS service_role_can_execute
FROM (
    VALUES
        ('public.update_owned_scan_custom_tags(uuid,text[])'),
        ('public.update_owned_scan_identification_review(uuid,text,boolean,uuid,public.user_review_state)'),
        ('public.request_nonbiological_scan_retention_deletions(integer)')
) AS checks(signature);
```

All five table booleans must be false. `anon` must have no UPDATE column rows;
`authenticated` must have exactly the five documented tag/review columns and no
owner/media/privacy column. Each metadata RPC row must be `false`, `true`,
`false`; the retention RPC row must be `false`, `false`, `true`. Remove the
five-column bridge only after the minimum supported app version uses both
metadata RPCs. In staging, copy another owner's otherwise-valid public media URL
into a controlled legacy fixture, delete the fixture scan, and prove that only
the exact canonical-owner URL was sent to R2. The foreign object must remain.
Also prove that a no-ledger recovery request returns `deferred`, while an
existing complete-but-missing or exact `replay_exhausted` fixture can recover
once.

```bash
openssl rand -base64 32
```

Store the output as `DWCA_PSEUDONYM_HMAC_KEY_V1` in the GitHub `Production`
environment. Do not reuse a JWT secret, service-role key, R2 credential, Resend
key, or an example value. CI requires valid Base64 decoding to at least 32 bytes
and synchronizes the exact value to Supabase before function deployment.

The download endpoint requires the existing bucket-scoped
`R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY` credentials. Optional
`DWCA_DOWNLOAD_IP_HASH_SECRET` can provide a dedicated Base64/random server-only
HMAC secret; without it, the shared client-address helper domain-separates the
active platform server key. This optional value belongs in Supabase Edge
secrets, not Vercel or an iOS configuration.

The public request route queues personal exports only. Do not expose global
scope to iOS or ordinary authenticated callers; repository-wide exports require
a reviewed internal workflow. Every job pins immutable canonical budgets: 5,000
CSV rows and an 8 MiB archive by default, with hard database ceilings of 20,000
rows and 16 MiB.

The current worker does not finish a complete export in `waitUntil`. A
minute-level cron synchronously drains five-job oldest-due waves. Each claim
still performs only one occurrence page, multimedia page, assembly, or delivery
phase; the dispatcher starts no new phase after its 40-second soft cutoff and
attempts at most 40 phases. Successfully advanced jobs rotate behind older due
work, while failed/contended IDs are suppressed for the rest of that invocation.
The database caps data pages at 100 scans and 256 KiB of serialized source under
the active claim; validated row checks bound media, interactions, and selected
taxonomy before the read. Job insertion examines at most the canonical row
budget plus one lookahead as UUIDs, then a parameterized lateral cursor
projects, measures, and inserts one DTO at a time. Total source JSON is limited
to four times the archive budget with a 64 MiB hard cap; projection stops at the
first violation and removes partial rows. Confirmed identity is authoritative.
Exact GPS keys are persisted only for an opted-in, snapshot-unprotected personal
export. A later scan or ordinary edit cannot change immutable DTO content.

The compact page hash remains, and a separate full-member predicate verifies
count, version, durable invalidation, current eligibility, and every stored hash
before assembly, staging, email, and completion. Relevant scan and taxonomy
changes durably invalidate affected jobs. A mismatch is terminal and removes
download authority immediately while durable cleanup removes the uploaded/staged
object. Opaque application capabilities stay in private work state while
processing; the public application URL and completed status appear in one
final-fence transaction. Failed jobs purge DTO rows immediately; completed DTOs
remain only until verified grant cleanup. Every download click reruns the
full-member predicate before a read-only R2 redirect valid for at most 30
seconds. A fixed-capacity incremental encoder caps CSV output at 512 KiB. CSV
pages are stored as claim-token-fenced R2 chunks and committed to a durable
cursor/manifest with cumulative budgets. These phase, deadline, and byte
boundaries are the production memory/time contract.

Every mixed source/grant/cleanup transition must lock in this order: canonical
`public.export_jobs` row `FOR UPDATE`, per-job advisory generation lock, then
child rows. Privacy triggers visit affected job UUIDs in order. A lock timeout
is a failed release gate; do not bypass the helper or weaken timeouts. The
fresh-catalog suite must exercise delivery, privacy invalidation, job deletion,
and stale cleanup concurrently to prove no deadlock or cross-generation
revocation.

Do not take an export-parent row lock from a scan/species `TRUNCATE` trigger.
The statement already owns source-table `ACCESS EXCLUSIVE`, while an export
worker can own the parent and wait for source-table `ACCESS SHARE`; requesting
the parent there would deadlock. The reviewed trigger only sets monotonic
`source_state.invalidated_at`/reason values. Click-time authorization then fails
closed, and the independent cleanup claimant discovers those states through
`export_job_source_state_invalidated_cleanup_idx`, visits parents in UUID order,
revokes grants, and enqueues archives. Revoked-grant discovery is supported by
`export_download_grants_revoked_due_idx`.

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
  services/supabase/functions/download-dwca \
  services/supabase/functions/reconcile-dwca-archive-cleanup \
  services/supabase/functions/reconcile-scan-deletions \
  services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts \
  services/supabase/functions/_tests/dwcaDownloadAndScanFinalizationMigrationContract.test.ts \
  services/supabase/functions/_tests/exportDwcaSecurityCoverage.test.ts \
  services/supabase/functions/_tests/publicWebExploreCoverage.test.ts \
  services/supabase/functions/_tests/publicWebExploreMigrationContract.test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/scripts,.github/workflows \
  services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts \
  services/supabase/functions/_tests/dwcaDownloadAndScanFinalizationMigrationContract.test.ts \
  services/supabase/functions/_tests/exportDwcaSecurityCoverage.test.ts \
  services/supabase/functions/_tests/publicWebExploreCoverage.test.ts \
  services/supabase/functions/_tests/publicWebExploreMigrationContract.test.ts \
  services/supabase/functions/export-dwca/archive_test.ts \
  services/supabase/functions/export-dwca/crc32_test.ts \
  services/supabase/functions/export-dwca/db_test.ts \
  services/supabase/functions/export-dwca/drain_test.ts \
  services/supabase/functions/export-dwca/index_test.ts \
  services/supabase/functions/export-dwca/mail_test.ts \
  services/supabase/functions/export-dwca/pseudonym_test.ts \
  services/supabase/functions/export-dwca/storage_test.ts \
  services/supabase/functions/export-dwca/worker_test.ts \
  services/supabase/functions/export-dwca/zip_test.ts \
  services/supabase/functions/download-dwca/handler_test.ts \
  services/supabase/functions/download-dwca/db_test.ts \
  services/supabase/functions/reconcile-dwca-archive-cleanup/worker_test.ts \
  services/supabase/functions/reconcile-dwca-archive-cleanup/db_test.ts \
  services/supabase/functions/delete-scan/db_test.ts \
  services/supabase/functions/reconcile-scan-deletions/worker_test.ts \
  services/supabase/functions/reconcile-scan-deletions/db_test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/exportDwcaMigrationContract.test.ts

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/privileged_routine_security.sql \
  services/supabase/tests/export_dwca_security.sql \
  services/supabase/tests/export_dwca_snapshot_security.sql \
  services/supabase/tests/dwca_export_queue_security.sql \
  services/supabase/tests/dwca_download_and_scan_finalization_security.sql \
  services/supabase/tests/public_web_explore_security.sql
```

The database test must prove all three source constraints are validated, API
roles cannot read the immutable DTO store/projection, only `service_role` can
execute the source-page RPC, a byte ceiling can stop a page before its row
ceiling, and the returned completion flag remains false when more keyset work
exists. Both phases must retain creation-time DTOs, confirmed identity must win
over the original AI identity, ordinary source edits must leave the stored DTO
unchanged, privacy revocation in the current candidate page must return no
payload, failed status must purge DTOs, and queue health must distinguish due,
live-claim, and expired-claim work without widening its ACL. The new catalog
test must additionally prove hash-indexed grants, distributed rate limits,
click-time full-source revocation, leased archive cleanup and health, atomic
claim-versus-recovery ordering, claimed-key disposition checks, and
completion-last canonical media verification. It must also prove a stale cleanup
generation cannot revoke a replacement grant or purge active source state, and
that every mixed DwC-A transition uses the parent-first generation lock. Those
existing assertions are insufficient for release.

The exact-SHA database/worker suites must pass the implemented regression
scenarios: revoke an early row after final paging, revoke after preparation and
after staging, and prove full-member validation blocks assembly, email, and
completion while removing/inactivating the object. Personal/global
protected-species escalation and deletion/tombstoning must cover applicable
windows. A stale claim must be unable to pass any final validation or side
effect.

Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
fences and restarts all nonterminal export preparation because hash-only source
membership cannot be upgraded into immutable DTOs. Expect prior attempt-scoped
CSV objects to become lifecycle-cleaned orphans. Repair migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` replaces
the all-projection aggregate with UUID lookahead plus row-at-a-time lateral
cursor enforcement. Do not use a successful small fixture as scale proof:
capture hosted statement duration, temporary bytes, WAL, lock age, and memory
pressure. A lock or statement timeout is a deployment failure; inspect active
export RPCs and roll forward rather than manually copying live rows into the
private source table.

Migration `20260726235158_amortize_dwca_archive_crc.sql` intentionally fences
and restarts nonterminal jobs in occurrence, multimedia, or assembly because
their legacy temporary manifests have no durable CRC. It reuses the existing
immutable membership snapshot and does not restart jobs already delivering a
staged archive. Expect old attempt-scoped CSV objects to become
lifecycle-cleaned orphans; do not manually splice them into the new manifest.
The migration locks affected canonical job rows in UUID order before chunk-table
DDL. If its ten-second lock timeout expires, inspect active export RPCs and
retry the deployment rather than weakening the lock order. A worker already
inside an export database routine can finish before the fence; the migration
re-evaluates its committed phase. A worker in an affected phase still doing R2
I/O blocks at its next fenced database transition and loses its deleted claim
after commit.

Supabase's
[canonical Edge Function limits](https://supabase.com/docs/guides/functions/limits),
verified 2026-07-26, currently list 2 seconds of active CPU and 256 MB of memory
per hosted request. The
[CPU troubleshooting page](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits)
still lists 200 milliseconds, while the newer
[546 guide](https://supabase.com/docs/guides/troubleshooting/edge-function-546-error-response)
lists 2 seconds and 250 MB. Do not resolve this documentation mismatch by
assuming the larger budget is safely available. Preserve the bounded phase
shapes and recheck the canonical page and hosted behavior for every ceiling
change.

After the repair migration passes preflight, queue one personal test export and
deliberately redeliver the same job UUID while a phase owns the lease. Both
wake-ups return `200`; no phase is owned by both workers, a contended attempt
reports `not_claimed` without source/provider work, and each targeted response
reports exactly one or zero attempted steps without discovering unrelated jobs.
Confirm a separate empty-body minute-cron wake-up advances several fast pages in
one invocation while reporting no more than 40 attempted steps.

Before production sign-off, run a reviewed internal export at the maximum
intended row/archive shape in staging or an equivalent hosted project. Inspect
the function Metrics and Logs during preparation and assembly. There must be no
HTTP 546 response, `WORKER_RESOURCE_LIMIT`, `CPU Time exceeded`, or unexpected
isolate retirement, and queue oldest-due age must recover after the job. Record
the tested commit, job UUID, canonical budgets, observed CPU/memory range, and
result in the deployment evidence. A local CRC microbenchmark validates the
algorithmic regression only and cannot satisfy this hosted release gate.

The hosted sign-off must also exercise final eligibility invalidation after
preparation and after staging. No email or usable download may survive that
invalidation. Record object cleanup/inaccessibility as evidence alongside Edge
resource metrics.

The storage test suite also proves that an S3-compatible HTTP-200 `<Error>`
completion body is rejected and that R2/Resend response bodies stop at their
byte ceilings. After completion, verify with an owner connection:

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
    source_state.source_byte_count,
    source_state.max_source_bytes,
    source_state.source_too_large,
    source_state.purged_at,
    (
        SELECT COUNT(*)
        FROM internal.export_job_source_rows AS source_rows
        WHERE source_rows.job_id = source_state.job_id
    ) AS retained_source_rows
FROM internal.export_job_source_state AS source_state
WHERE source_state.job_id = '<test-job-uuid>'::UUID;

SELECT
    chunks.phase,
    chunks.sequence,
    chunks.byte_count,
    chunks.crc32,
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
    health.generated_at,
    health.backlog_count,
    health.due_count,
    health.active_claim_count,
    health.expired_claim_count,
    health.oldest_due_at,
    health.oldest_due_age_seconds
FROM public.get_dwca_export_queue_health() AS health;

SELECT
    grants.job_id,
    grants.expires_at,
    grants.revoked_at,
    grants.revocation_reason,
    grants.cleaned_at,
    grants.token_sha256 ~ '^[0-9a-f]{64}$' AS hashed_capability
FROM internal.export_download_grants AS grants
WHERE grants.job_id = '<test-job-uuid>'::UUID;

SELECT *
FROM public.get_dwca_archive_cleanup_health();

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
        ('public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,bigint,boolean)'),
        ('public.get_export_job_chunks(uuid,uuid)'),
        ('public.stage_prepared_export_archive_with_download_grant(uuid,uuid,text,text,text,timestamp with time zone)'),
        ('public.complete_prepared_export_job_with_download_grant(uuid,uuid)'),
        ('public.enqueue_dwca_archive_cleanup(uuid,text,text)'),
        ('public.authorize_dwca_archive_download(text,text)'),
        ('public.claim_dwca_archive_cleanup_jobs(uuid,integer,integer)'),
        ('public.complete_dwca_archive_cleanup_job(uuid,uuid)'),
        ('public.release_dwca_archive_cleanup_job(uuid,uuid,text)'),
        ('public.get_dwca_archive_cleanup_health()'),
        ('public.release_export_job_step(uuid,uuid,text,boolean)'),
        ('public.renew_export_job_claim(uuid,uuid)'),
        ('public.get_dwca_export_queue_health()')
) AS checks(routine_signature)
ORDER BY checks.routine_signature;

ROLLBACK;
```

The completed row must be a personal export within both canonical budgets, use
key version `1`, have an attempt-scoped `exports/{user}/{job}/{claim}.zip` key,
and have no failure code. The work phase must be `completed`; every chunk key
must be claim-fenced and every CRC must be in `0...4294967295`. ACL results must
be `false`, `false`, `true` for each routine. Verify the received message
contains one 24-hour `/functions/v1/download-dwca?token=...` application
capability and no direct R2 host/signature. Click it before and after a
controlled source-privacy change: the first request must produce only a no-store
redirect with `X-Amz-Expires <= 30`; the second must fail closed and enqueue the
exact archive for deletion. Verify duplicate processing did not send a second
email. The private protocol/work/manifest/grant/cleanup tables are owner-visible
operational state only; API roles, including `service_role`, must lack direct
`SELECT`.

Confirm the **DwC-A Export and Archive Health Monitor** workflow is enabled for
the Production environment. Dispatch it once with the default 5/15-minute age,
25/100-job backlog, and `fail_on=warning` settings. It independently calls both
the continuation and archive-cleanup health RPCs, so a missing worker cron or
Vault configuration cannot make the system appear healthy. A drained staging
queue should report `ok`, zero due jobs, no expired claim, zero pending archive
deletes, and no expired cleanup lease. During an alert, inspect the structured
`dwca_export_queue_health`, `dwca_export_step_complete`, and
`dwca_archive_cleanup_health` events, repair cron/Vault/R2/database/Resend
availability, and let claim-fenced retries resume. Never clear a claim, rewrite
a cursor, or edit the cleanup outbox to silence the monitor.

The production deployment smoke invokes `reconcile-dwca-archive-cleanup` once
with the exact server credential, validates its bounded counters, and rejects a
critical cleanup-health result. For a manual deployment, perform the same
invocation and inspect `get_dwca_archive_cleanup_health()`. Before promotion,
legacy `file_url` values must be scrubbed, all due legacy/revoked archive rows
must drain, `expired_lease_count` must be zero, and oldest-due age must be below
15 minutes. Confirm a transient R2 failure releases the row for retry and does
not restore download authorization. In staging, complete an older-attempt
cleanup after a replacement archive/grant has been staged for the same job. The
old outbox row may complete, but the current grant and unpurged source state
must remain unchanged.

The same deployment smoke invokes `reconcile-scan-deletions` with the exact
server credential and rejects a critical health result. Confirm
`reconcile_scan_deletions_every_five_minutes` exists and the independent Scan
Media Health Monitor is enabled for Production. A clean queue reports no expired
lease and oldest-pending age below 15 minutes. Simulate one transient R2 failure
in staging: the exact lease must release with a future `next_attempt_at`, a
stale token must not clear a replacement lease, and a later run must finish
without a client retry. Worker and health logs must contain aggregate counters
only, never scan IDs, owner IDs, or media URLs.

Do not treat the 40-step ceiling as a guaranteed per-minute rate or calculate a
fixed delivery time from it. The dispatcher checks its soft cutoff between
durable phases, while page, assembly, delivery, and provider durations vary. Use
oldest-due age and backlog trends to decide whether capacity is healthy. If
warnings persist after dependency recovery, profile phase duration and database
plans before changing concurrency. Scale only through bounded workers that use
the existing oldest-due discovery and claim-token protocol; do not raise the
step ceiling or add overlapping cron calls without validating Edge CPU, memory,
wall-clock, and R2/Resend limits.

For key rotation, first add `DWCA_PSEUDONYM_HMAC_KEY_V2` to GitHub, extend the
workflow to validate/synchronize it, and deploy code capable of reading both
versions. Only then migrate the `export_jobs.pseudonym_key_version` default to
`2`. Keep V1 configured until all V1 jobs are terminal and past operational
retention. Never overwrite V1 with new bytes: doing so silently changes stable
pseudonyms for jobs already pinned to version 1.

If storage or Resend is transiently unavailable, do not bypass the claim RPC,
edit a job to completed, reuse a stale claim token, or restore caller-supplied
scope/user fields. Let the lease/watchdog expose the normal failed/retry path.
Cloudflare's lifecycle policy remains a safety net for orphan attempt/work
objects and incomplete multipart sessions; the durable cleanup outbox owns known
final archives. Before release, compare the live rules with
`docs/r2-lifecycle.json`: the bucket must retain the global seven-day
incomplete-multipart abort rule as well as the one-day `exports/` expiration
rule.

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

Confirm the active `reconcile_revenuecat_subscribers_every_fifteen_minutes` cron
and its 120-second `pg_net` timeout, then invoke the service-only route once. It
must process repeated six-row waves rather than stop after one wave. Its
aggregate response must report no unpersisted failures, its queue claims must be
released, and an equal/older CustomerInfo snapshot must report stale without
changing the tier. Temporarily suppressing a staging webhook and allowing the
sweep to observe a newer authoritative snapshot is the missed-delivery recovery
smoke test. Pro rows should next be due in roughly six hours and free rows in
roughly 24 hours.

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
SUPABASE_URL=... SUPABASE_SERVER_API_KEY=... \
  deno run --allow-net --allow-env \
  services/supabase/scripts/repair_processed_material_scan_pollution.ts
```

Review every planned row before applying:

```sh
SUPABASE_URL=... SUPABASE_SERVER_API_KEY=... \
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

Confirm Vault has `SUPABASE_URL` and an active current or legacy server key in
the compatibility-named `SUPABASE_SERVICE_ROLE_KEY` slot; the scheduled worker
reads those exact names. Confirm the function entries are:

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
release invariants. The original latency pass changed eligible live-camera still
orchestration only; the later owner-row durability release below applies the
server success boundary to still, gallery, audio, describe, mixed-media, and
video observations.

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
meets every segmented gate:

- cache-hit non-Gemini p95 is at most 1 second (target p50 at most 300 ms);
- primary cache-miss external resolution is measured separately, remains within
  Edge/client timeouts, and does not cause a persistence-failure increase;
- response-to-first-render p95 is at most 300 ms;
- identification quality is unchanged;
- failure rate increases by less than 0.5 percentage points;
- missing remote scans and stuck ingestion jobs do not increase.

When measured Gemini p95 is at most 5 seconds, the corresponding cache-hit
end-to-end p95 goal is at most 6 seconds. If the final end-to-end p95 remains
high, segment by dictionary cache state and use `Server-Timing` to distinguish
Gemini from required post-Gemini persistence/external resolution. Record the
remaining floor; do not alter model economics or move owner-row durability back
behind the response.

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
- WeatherKit, geocoding, awards, and Field trips do not move the result
  boundary; analytics, group tags, and candidate enrichment remain optional
  background work;
- primary Wikipedia/GBIF cache-miss resolution may extend `post_gemini` and the
  server response, but cannot extend response-to-first-render or outlive the
  required owner-row success boundary;
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

## Scan Owner-Row Durability and Recovery Rollout

This release closes the false-success condition where iOS could persist an AI
result while `public.scans` was still absent, leaving Explore sharing and Field
Chat without their required owner row. Repository implementation is not
production remediation. Keep the
[July 2026 incident](../incidents/2026-07-scan-owner-row-durability-gap.md) open
until the backend and iOS exit criteria below are complete.

### Release unit and order

Treat these components as one compatibility release:

1. Apply the repository's current migration set. In particular, verify
   `20260727010340_fix_service_role_authorization_guard.sql` and
   `20260727013416_future_proof_server_key_boundaries.sql` before testing
   Explore publication; recovery must not disguise a stale privileged-key
   boundary.
2. From one exact SHA, run the normal production backend workflow and promote
   `identify-multimodal`, `identify`, `identify-describe`, `audio-spec`,
   `check-scan-status`, and `share-scan-to-explore`. Their
   `_shared/identify/db.ts`, `_shared/scanIngestionJobs.ts`,
   `_shared/scanIngestionCompatibility.ts`, and `_shared/scanRecovery.ts`
   dependencies bundle transitively. If an emergency manual function deploy is
   unavoidable, deploy in that order so new false successes stop before
   repair-capable clients arrive.
3. Build and release iOS from the matching reviewed source. The iOS release
   carries `recovery_scan`, staged image/video/audio restoration, Field Chat
   preflight repair, and customer-facing toast translation. A backend workflow
   success is not evidence that this app build shipped.

Old clients remain compatible with the new backend. Release backend first; never
require the new app to compensate for an old false-success function.

Before promotion, retain results for:

```bash
make test-supabase-tooling
make validate-supabase-migrations
make validate-ios-project
git diff --check
```

Run database integration/pgTAP gates against a disposable local or staging
catalog when Docker/database access is available. A sandbox that cannot reach
Docker is missing evidence, not a passing integration result.

### Staging smoke matrix

Use disposable staging identities and media:

1. Submit a new known biological cache-hit still. After identify returns `200`,
   immediately call `/check-scan-status`; it must return `found` without polling
   delay. Open Field Chat, then share the same scan to Explore and verify the
   public post snapshot.
2. Repeat the immediate owner-row check for standalone audio and playback video.
   Video is successful only with its required promoted `.mp4` and ready playback
   representation. Inspect the ledger:
   `complete /
   media_finalization_complete` may appear only after every
   claimed storage key is promoted or explicitly deleted and every promoted
   image/video/audio URL has a ready canonical row.
3. With controlled staging fault injection, make the scan insert or owner
   read-back fail. Identify must return customer-safe
   `503 scan_persistence_failed` with `Retry-After: 5`, and iOS must not save a
   successful local observation.
4. Exercise a controlled moderation rejection. Identify must return generic
   `400 observation_rejected`, leave no scan row, and preserve the exact
   terminal policy fence against recovery.
5. Create an eligible legacy missing-row fixture. A single `/check-scan-status`
   request with bounded non-media `recovery_scan` must create and reload only
   the authenticated owner row. Bulk status remains read-only.
6. Force claim and recovery concurrently for one UUID. Exactly one generation
   may win: recovery-first makes claim return `already_complete` without a
   provider call; claim-first makes recovery return `deferred`. Verify
   processing, finalizing, retrying, and `failed_retryable` jobs defer repair.
   Verify policy, media-abandonment, legacy-unknown, and arbitrary terminal
   reason codes block repair; only exact `replay_exhausted` remains recoverable.
   Repeat through each compatibility route. Its atomic setup must complete
   before the mocked provider is called; setup error must return
   `scan_ingestion_unavailable`, refund unused quota, and perform no provider
   request.
7. Attempt recovery using another owner's row UUID and a mismatched
   caller-supplied `user_id`. Neither may overwrite or reveal the other row.
8. For an eligible missing Explore row, combine `recovery_scan` with
   owner-staged image, video, and audio keys. Verify promotion and normal
   publication checks run before the post is visible; direct URLs and non-owner
   staging keys must fail.
9. Verify Ask the Community repairs through `/check-scan-status` before image
   restoration, and that a transient Field Chat still-syncing result leaves the
   toolbar action available for retry.
10. Fault one required promotion or canonical audio refresh after scan insert.
    Identify must return retryable `503`, retain a noncomplete ledger, and let
    replay/reconciliation finish only through
    `complete_scan_ingestion_finalization`. No alternate worker may directly
    update the ledger to `complete`.
11. Return a controlled 5xx from R2 staging deletion in current multimodal and
    compatibility audio paths. Neither path may mark the ledger complete. A 404
    is idempotent success; 5xx, timeout, and every other non-success retain
    durable retry/reconciliation state.
12. Race rolling-deployment `claim_scan_ingestion_job`, `begin_scan_ingestion`,
    and recovery against the same scan UUID. Both routines must use the same
    advisory lock; every current route must use atomic `begin_scan_ingestion`,
    and neither routine may replace a completed recovery generation.

### Monitoring and incident triggers

Monitor structured Edge event `multimodal/scan_persistence_failed`, PostHog
event `scan_persistence_failed`, `multimodal/observation_rejected`, owner status
`not_found` rates, share `Scan not found` rates, and `scan_ingestion_jobs`
retry/terminal age. Segment persistence latency and failures by modality, tier,
and dictionary cache state in aggregate dashboards. Restricted structured error
logs contain owner and scan identifiers for incident correlation; keep them
access-controlled and never copy identifiers, coordinates, media keys, request
bodies, or raw error details into retained release artifacts.

Any current identify `200` followed immediately by owner status `not_found` is a
severity incident, even if recovery later succeeds. Repeated recovery on fresh
scans is also a deployment/version-skew signal, not acceptable steady state.

### Rollback and exit criteria

The backend recovery contract is backward compatible, so an iOS rollback is safe
but restores the old customer experience. Do not roll `identify-multimodal` back
to a version that can return success before owner-row read-back; deploy a
forward fix instead. A status/share rollback removes repair capability and
should be used only to contain a defect while keeping durable identify success
in place. Never grant direct `scans` writes or privileged RPCs to
`authenticated`, and never ship a server key in iOS.

Close the incident only after:

- production deployment records tie all three Edge Function versions to the
  reviewed exact SHA;
- the matching iOS build is available to the intended cohort;
- new-scan immediate status, Field Chat, Explore, and legacy recovery smoke
  checks pass;
- monitoring shows no identify-success/missing-owner-row pairs through the
  agreed observation window; and
- the incident report records deployment identifiers, timestamps, retained
  evidence, and final measured latency/failure deltas.

## Public Web Explore Read Boundary

Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql` and
the Next.js Explore reader are one release unit. Push the migration first, then
apply `20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql`,
then deploy `apps/web/`. The database exposes only
`get_public_web_explore_posts(...)` and
`get_public_web_explore_post_detail(...)`, plus the combined
`get_public_web_explore_post_page(...)`, to the web server credential. Direct
`anon` and `authenticated` execution is intentionally denied.

Detail independently requires `explore_projected_post_cards(NULL)` visibility.
The Next.js detail page uses the combined routine so card and detail share one
statement/MVCC snapshot; do not regress to sequential check-then-fetch calls.

Before production:

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,.github/workflows \
  services/supabase/functions/_tests/publicWebExploreCoverage.test.ts \
  services/supabase/functions/_tests/publicWebExploreMigrationContract.test.ts

npm --prefix apps/web test

supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/public_web_explore_security.sql
```

If this fixture reports `permission denied for table explore_posts` at its
moderation transition, do **not** grant `service_role` direct table access.
Fixture setup/mutation must run as the catalog-test owner; only the visibility
assertions run under `service_role` through the explicitly granted public-web
RPCs. A direct-write denial is the expected ACL contract.

The Vercel Production environment must contain `SUPABASE_URL` and exactly one
supported server-key source. Prefer `SUPABASE_SERVER_API_KEY` with the current
`sb_secret_...` key; retain `SUPABASE_SERVICE_ROLE_KEY` only as the documented
legacy migration fallback. Neither value may use a `NEXT_PUBLIC_` prefix.
`SUPABASE_PUBLIC_VIEWER_ID` is obsolete and must be removed: viewer identity is
fixed to `NULL` inside PostgreSQL.

The pre-production database suite directly calls detail for moderated, unshared,
tombstoned, shadowbanned, media-less, quarantined, and unpublished
community-resolved posts and receive no row. It must also cover a visibility
change against the combined routine. Testing only the normal visible web path
does not satisfy this gate.

After deployment, the backend workflow exercises the posts RPC with every real
anon/publishable project key and accepts only `401`, `403`, or `404`. It then
uses the resolved server key as the positive control and checks that the result
is a bounded JSON array with zero engagement counts and false viewer/ownership
flags. Treat a public-key `2xx`, an empty server-key result when production has
known visible posts, a raw source-table grant, or viewer-specific state as a
release blocker. Do not repair this path by granting native Explore RPCs or
their source relations to browser roles.

As a second positive/negative control, invoke the repaired card-plus-detail
boundary with the server key for one known visible post and one known
card-hidden post. The visible row must be internally consistent; the hidden post
must return no card or detail payload.

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
   | `SUPABASE_SERVER_API_KEY`        | Preferred current server-only `sb_secret_...` key              |
   | `SUPABASE_SERVICE_ROLE_KEY`      | Legacy service-role JWT migration fallback only                |

   Vercel owns and overwrites `x-vercel-forwarded-for` at the application
   ingress. If the app moves behind another proxy, explicitly choose one
   allowlisted header and configure the trusted ingress to overwrite it; never
   accept a client-appended forwarding chain.

Do not put the Turnstile secret, waitlist HMAC secret, or either privileged
Supabase server-key format in a `NEXT_PUBLIC_` variable, source file, build log,
or support ticket. Only the Turnstile site key is public. Configure the current
key when available; do not configure a publishable key or anon/user JWT in
either privileged variable. The server resolver rejects those values.

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
| `R2_READ_ACCESS_KEY_ID`             | Synchronized by the workflow to Supabase Edge only            |
| `R2_READ_SECRET_ACCESS_KEY`         | Synchronized by the workflow to Supabase Edge only            |
| `R2_EVENT_WEBHOOK_SECRET`           | Optional; synchronized to Supabase Edge for R2 event hints    |
| `SUPABASE_ACCESS_TOKEN`             | Used by the GitHub runner to operate the Supabase CLI         |
| `SUPABASE_DB_URL`                   | Used by the GitHub runner for database migration/audit access |
| `SUPABASE_DB_PASSWORD`              | Used only by the runner's alternative pooler connection path  |

None of these values belongs in Vercel. The public-web Vercel contract is the
explicit table in **Public Web Waitlist Release** above and
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
- `R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY` — required,
  bucket-scoped Cloudflare R2 Object Read credentials. The deploy workflow
  synchronizes them to Supabase Edge; audit that the token cannot write or
  delete objects.
- `R2_EVENT_WEBHOOK_SECRET` (optional) — at least 32 high-entropy characters.
  When present, the deploy workflow validates and synchronizes it to Supabase;
  configure the identical value in only the trusted Cloudflare Queue consumer.
  Omit it to disable event acceleration safely. The five-minute scheduled
  direct-origin reconciliation remains authoritative.
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
configured database connection. Post-deploy smoke checks, manual taxonomy
imports, and scan-media monitoring resolve a server API key at runtime through
`services/supabase/scripts/resolve_project_api_keys.ts`, then mask it in GitHub
Actions logs. The resolver calls the Management API key-list endpoint with
`reveal=true`; the CLI key-list command has no equivalent reveal option and must
not be used to obtain a callable `sb_secret_...` value. Resolution prefers the
revealed current key named `default`, then another revealed current secret, and
falls back only to the exact legacy key named `service_role`. Masked values,
malformed keys, and partial name matches fail closed.

The shared resolver tolerates a short Management API incident without weakening
that classification. It makes at most five attempts for transport failures, HTTP
408/425/429, and HTTP 5xx. Delay uses capped exponential equal jitter and a
bounded numeric `Retry-After`; every individual request retains its 15-second
deadline. HTTP 401/403, other caller errors, malformed or oversized responses,
and invalid or ambiguous key lists fail immediately. Retry diagnostics contain
only `transport_error` or the HTTP status class, delay, and attempt count—never
the access token, key, response body, or raw transport message.

The deploy workflow then copies the masked selected value to the non-reserved
Edge secret `MERIAN_SUPABASE_SERVER_API_KEY` before Function deployment.
Operators do not provision a separate GitHub secret for this fallback: the
Management API result is its source of truth. Do not rename it to a `SUPABASE_*`
variable; Supabase reserves those names and rejects CLI writes to them.
Immediately after the write,
`services/supabase/scripts/verify_edge_secret_digest.ts` compares the exact
selected key's SHA-256 digest with the named digest returned by
`supabase secrets list --output json`. The gate fails before Function rollout if
the entry is missing, duplicated, malformed, or mismatched and never prints the
key or either digest. A project-key rotation is incomplete until the new key has
been added, this deploy workflow has passed with the overlap in place, all Vault
and server callers have moved, and only then the old key is revoked.

If the Supabase dashboard or Management API is unavailable, do not guess the
pooler host in production secrets. Wait for the dashboard to recover, or get the
existing shared-pooler host from another operator who already has access. The
`supabase link` command also uses the Management API, so `504` or `500`
responses during a Supabase incident can block linking even when the migration
SQL itself is fine. Using `db push --db-url` only removes the project-status
lookup from the migration step. Edge Function deploys, service-role key lookup,
and smoke tests still depend on Supabase's hosted APIs and can fail during an
active platform incident. If key resolution exhausts its five attempts on a
retryable status such as HTTP 502, leave migrations and secrets unchanged,
confirm Supabase Management API health, and rerun the same workflow SHA. Do not
replace the revealed lookup with a masked CLI result, bypass the digest gate, or
paste a project key into workflow YAML.

The workflow also inherits normal Supabase project Edge secrets at runtime. Most
live only in Supabase. The three RevenueCat credentials, required DwC-A
versioned pseudonym key, and optional AI quota override are reviewed exceptions:
GitHub `Production` is their deploy source and the workflow synchronizes them to
Supabase. The complete Edge-secret inventory is documented in
`docs/backend-and-data/02-supabase-edge-and-database.md`.

Internal routes using `_shared/serviceRoleAuth.ts` authorize locally against
`SUPABASE_SERVER_API_KEY`, the deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, named values in the hosted
`SUPABASE_SECRET_KEYS` JSON dictionary, the singular `SUPABASE_SECRET_KEY`
local/manual fallback, and the migration-only `SUPABASE_SERVICE_ROLE_KEY`
fallback; they must never probe a table to infer authority. Legacy service-role
JWT callers send the same value in Bearer Authorization and `apikey`. Named
`sb_secret_...` keys are non-JWT and are sent only in `apikey`. The deployment
smoke step retrieves every available real anon/publishable project key and
requires `community-taxonomy-status` to return `401` for each before the real
current secret key (or exact legacy service-role fallback) is used as the
positive control. Current secret keys are sent only in `apikey`; legacy JWT keys
are sent in both headers. Do not weaken that denial check when rotating API
keys.

Every source is classified independently for inbound authorization. A malformed
source contributes no candidate and cannot veto an exact request key from
another valid source. If no key matches, any malformed source still produces
`invalid_secret_key_configuration`; it is never normalized or silently accepted.
Outbound selection preserves strict priority: a malformed configured scalar
encountered at its priority point fails, while a valid higher-priority source is
not vetoed by a malformed lower migration fallback. The publishable Edge
resolver and public web server-key resolver apply equivalent source isolation
for their supported migration sources.

Positive smoke requests retry `401`, `404`, `429`, `500`, `502`, `503`, and
`504` with bounded backoff for at most six attempts so routing propagation is
not mistaken for a final release failure. A final error still fails closed. For
a `/functions/v1/*` failure, a fixed `X-Merian-Handler: 1` marker means the
request reached the handler: inspect `community_taxonomy_status_auth_denied` and
its stable reason in restricted Edge logs. If the marker was absent, inspect the
Supabase gateway, Function deployment status, and router. A `/rest/v1/*` failure
is classified as a Data API request instead; inspect the API gateway, PostgREST
RPC grants, and database logs without expecting a Function marker. Never print
the response body or `X-Request-ID` value merely to diagnose authorization.

Before credentialed smoke begins, the workflow derives the complete Function
inventory from the same dependency graph used for deployment. It sends `OPTIONS`
to every production route and requires `X-Merian-Handler: 1`; all unresolved
routes share up to 18 bounded attempts with no sleep longer than ten seconds.
This proves route recognition and Merian execution without invoking business
work. A validated legacy anon JWT is added only as the preflight execution
credential required by the routes that retain gateway `verify_jwt = true`;
publishable keys are never valid Bearer tokens. If the configuration contains
such a route but the legacy JWT is unavailable, the workflow fails closed before
route probing. Before deactivating the legacy anon key, migrate every remaining
gateway-verified route to the reviewed in-handler auth boundary or provision a
replacement short-lived user smoke identity; do not weaken this probe to accept
an unmarked gateway response. The workflow then separately probes
`identify-multimodal`, `check-scan-status`, `share-scan-to-explore`,
`get-explore-composer-media`, and `insight-chat` without Authorization. Each
critical route must return `401` with the marker, additionally proving
user-scoped access fails closed. A gateway `404` with no handler marker never
counts as a missing scan and never permits the production workflow to report
success. Do not run the matching iOS smoke while either gate is still retrying.

After migration `20260726212549_harden_service_role_request_authentication.sql`,
verify effective production table privileges through the reviewed read-only
database connection:

```sql
SELECT
    role_name,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'SELECT'
    ) AS can_select,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'INSERT'
    ) AS can_insert,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'UPDATE'
    ) AS can_update,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'DELETE'
    ) AS can_delete,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'TRUNCATE'
    ) AS can_truncate,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'REFERENCES'
    ) AS can_reference,
    has_table_privilege(
        role_name,
        'public.taxonomy_import_runs',
        'TRIGGER'
    ) AS can_trigger
FROM (
    VALUES ('anon'), ('authenticated'), ('service_role')
) AS roles(role_name);
```

`anon` and `authenticated` must be false in all seven columns. `service_role`
must be true only for select/insert/update and false for delete. Do not infer
this matrix from an empty REST response.

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

The import job has only `contents: read`, uploads JSON/Markdown summary
artifacts plus a one-day checklist artifact, and writes the GitHub job summary.
When a real import changes the checklist, a separate five-minute writer job
downloads that artifact and performs the commit with the workflow's sole scoped
`contents: write` grant. The import process cannot read a checkout credential.

## Account Deletion Health Automation

The **Account Deletion Health Monitor** runs every five minutes at minutes 2, 7,
…, 57, offset from the database reaper. It resolves the production server API
key through the Management API and calls only the aggregate
`get_account_deletion_health()` RPC. It does not invoke deletion work and does
not read the Vault values required by the reaper, so cron or Vault
misconfiguration remains independently observable. UUIDs, claim tokens,
prefixes, cursors, and raw errors are absent from logs and artifacts.

Scheduled runs warn and fail on claimable work aged 10 minutes, active work aged
27 hours, backlog of 25 jobs, any retry error, or any expired lease. They become
critical at 30 minutes due age, 36 hours active age, 100 jobs, a disabled cron,
missing reaper URL/service credentials, or any orphaned active storage work. The
active-age threshold allows for the mandatory 25-hour delayed verification. The
monitor request has a 15-second deadline and 64 KiB response ceiling.
Configuration health follows the reaper's Vault-first, NULL-only fallback
exactly. A blank Vault entry is therefore critical even when a legacy app
setting is populated; update or remove the blank Vault entry instead of relying
on fallback. The independent monitor may use an opaque server key through
`apikey`; the database reaper supports the same current/legacy formats through
the private database header builder. A successful manual monitor dispatch
verifies the health RPC and monitoring credential, but operators must also
inspect recent reaper cron runs to confirm the separate Vault-backed path
succeeds.

A failed run means the state machine is overdue, unhealthy, misconfigured, or
the monitor could not read aggregate health. Use the incident procedure in the
durable account-deletion release gate. Preserve claim fencing and login access
until verified completion; do not edit private jobs or manually delete Auth.

## RevenueCat Reconciliation Health Automation

The **RevenueCat Reconciliation Health Monitor** runs at minutes 7, 22, 37, and
52, after the quarter-hour database dispatches. It resolves the production
server API key at runtime through the revealed Management API resolver and calls
only the aggregate `get_revenuecat_reconciliation_health()` RPC. No subscriber
identity is written to logs or artifacts.

Scheduled runs warn and fail at an oldest due age of 30 minutes, become critical
at 60 minutes, and warn immediately on any expired lease. A monitor request has
a 15-second deadline and 64 KiB response ceiling. A failed run therefore means
the queue is overdue, a worker lease expired, or the monitor could not read
health. Start with the structured reconciliation health event and queue error
codes described in the RevenueCat release gate; preserve claim fencing and let
the durable worker recover.

## DwC-A Export and Archive Health Automation

The **DwC-A Export and Archive Health Monitor** runs every five minutes, offset
from the once-per-minute database dispatcher. It resolves the production server
API key through the revealed Management API resolver and calls only the
aggregate `get_dwca_export_queue_health()` and
`get_dwca_archive_cleanup_health()` RPCs. User IDs, object keys, capability
tokens, claim tokens, and work cursors are absent from logs and artifacts. Its
GitHub schedule is independent of database cron and Vault, so it still alerts
when the archive-cleanup worker never starts.

Scheduled runs warn and fail when the oldest due job reaches five minutes, the
outstanding backlog reaches 25 jobs, or any claim has expired. They become
critical at 15 minutes or 100 outstanding jobs. The monitor request has a
15-second deadline and 64 KiB response ceiling. An alert therefore means
continuation throughput is behind, a worker claim expired, or health could not
be read. Start with the route's structured queue-health and step events, then
verify database, R2, and Resend health. Preserve the durable state machine and
let its retries drain; do not edit private queue tables. A zero due count means
no work is currently claimable, not necessarily an empty backlog: inspect active
claims and retry deadlines before declaring the queue fully idle. Archive
cleanup warns at 25 pending rows or 15 minutes oldest-due age and becomes
critical at 100 pending rows, one hour oldest-due age, or any expired lease.
Repair cron/Vault/R2 configuration and let the fenced outbox resume; never edit
cleanup leases or rows directly.

## Scan Media Health Automation

The **Scan Media Health Monitor** workflow runs every 30 minutes and can also be
started manually from GitHub Actions. It resolves a revealed production server
key through `resolve_project_api_keys.ts` and the Management API, then calls
`/scan-media-health` with format-aware standard headers. The request has a
15-second deadline and a 2 MiB streaming response ceiling. Because this endpoint
is read-only, transient network, routing, authorization-propagation, rate-limit,
and server statuses receive at most six attempts with a bounded
2/4/6/8/10-second backoff. A final invocation failure reports only HTTP status,
bounded SDK failure class, and whether the fixed `X-Merian-Handler: 1` marker
was present; the body, request ID, variable headers, and credential remain
withheld. It writes JSON and Markdown summary artifacts and appends the Markdown
report to the job summary after a successful endpoint response. The Markdown
report includes an **Incident Actions** table that maps each issue code to an
owner, next step, runbook, and sample-field hint; use that table as the first
triage view before opening raw database rows. It also includes a visible
**Sample Preview** table with the first sample row for each issue code. Expand
the per-issue sample blocks or download the
`scan-media-health-summary-<run_number>-attempt-<run_attempt>` artifact when you
need the complete sample set. Attempt-specific names preserve evidence from
workflow reruns.

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
  pending while the lease or retry window is active, invoke the shared
  claimed-key/canonical-media finalization transaction after a successful
  repair, or mark it `failed_terminal` after the abandonment TTL. No worker may
  directly set `complete`.
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
uses `SUPABASE_ACCESS_TOKEN` to resolve a current project secret key (or the
exact legacy service-role fallback) at runtime and constructs
`https://qlarqavoqhkuwzmevrmf.supabase.co` from the project ref, so operators do
not need to paste server credentials locally.

For routine runs after the first clean production import, `dry_run = false` is
acceptable. The workflow uploads a JSON/Markdown summary artifact for every run
and, when `update_checklist = true`, commits
`docs/backend-and-data/07-community-taxonomy-import-checklist.md` after real
imports. Use `page_count = 10...20` only after several successful smaller runs.

## Local Emergency Fallback

Only use the local path when GitHub Actions is unavailable.

```bash
cd /Users/emreerdener/Developer/merian

deno fmt --check services/supabase/functions services/supabase/scripts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions services/supabase/scripts
make test-supabase-tooling
(cd services/supabase/functions && deno task test)
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
npm run audit:dependencies
npm test
npm run typecheck
npm run build
```

The `.github/workflows/admin-quality.yml` job must pass this same ordered
application sequence before the separately hosted admin deployment. It reports
for every pull request so it can be required reliably, and on affected pushes to
`main`. Its live audit fails on high/critical findings or registry failure,
while the admin dependency-security test also enforces reviewed Next.js,
PostCSS, and Sharp floors directly from the committed lockfile. A green backend
deployment workflow does not substitute for this admin gate. The repository
ruleset must require `Naturebook Admin Quality / test`, and the separate admin
Vercel project must add that GitHub Action as a required Deployment Check.
Workflow YAML alone does not block a merge, direct deployment, Force Promote, or
manual deployment. Verify Vercel is releasing the exact checked commit.

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
- For the DwC-A version-2/public-web Explore release unit, retain the evidence
  hold unless every exit criterion in
  `14-dwca-and-public-web-release-hold-2026-07-27.md` has exact-SHA evidence.
  Green unit/static suites alone are not release sign-off. Require the stable
  hosted `iOS Build and Test / Production readiness` result, including the full
  unit-test target and independent unsigned Release archive, plus the frozen
  public-web install/audit/test/type-check/build gate for the same release SHA.
- For an Explore media-health release, complete the structural checks and
  staging smoke matrix in **Explore media-health and reversible-quarantine
  release gate**. Require public-surface agreement, preserved author/engagement
  state, spaced direct-origin confirmation, and automatic repair recovery before
  calling the release complete.
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
- For the scan owner-row durability release, confirm production deployment
  records tie the deployed versions of `identify-multimodal`,
  `check-scan-status`, and `share-scan-to-explore` to the same reviewed SHA.
  Submit a brand-new scan, require immediate owner status `found` after identify
  `200`, then open Field Chat and publish it to Explore. Run the eligible
  legacy-repair, active/retryable deferral, exact policy-rejection block,
  cross-owner isolation, and staged-media restoration cases in
  [Scan Owner-Row Durability and Recovery Rollout](#scan-owner-row-durability-and-recovery-rollout).
  Do not call backend smoke complete until the matching iOS build independently
  passes its customer-facing retry/toast checks.
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
  affected write and read functions, and require
  `20260727010340_fix_service_role_authorization_guard.sql` in any environment
  using the hardened service-role boundary. Confirm `PUBLIC`, `anon`, and
  `authenticated` cannot execute `refresh_public_author_identity(uuid)` or
  `repair_explore_post_ownership_for_user(uuid)`, while `service_role` can. Run
  `_tests/exploreIdentityDb.test.ts` with an explicit `SUPABASE_DB_TEST_URL`;
  verify a second converged refresh preserves the user row version. Smoke-test
  one feed/profile read and confirm it performs no maintenance RPC, then share
  from both the Scan Library and the Insight composer and confirm the public
  author projection is current. Neither share may log
  `service_role authorization required`. During ghost-merge QA, verify scans and
  Explore posts move to the target account before the identity refresh and ghost
  purge.
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
  there is no enabled expiration rule for `public_uploads/free/`,
  `public_uploads/pro/`, or `avatars/`.
- After any account-deletion migration, require all five claim-definition
  booleans above to be true before trusting the scheduled reaper. Record the
  fenced-due-row audit count separately, and prove a stale storage marker for a
  live staging fixture remains unclaimable.
- Run one staging purge or safe delete and inspect Edge logs for bounded R2
  fanout, delete failures, duration spikes, and memory pressure.
- Upload a custom avatar, then run/inspect scan purge flows and confirm the
  `https://media.merian.app/avatars/{userId}/...` URL remains available.
- Confirm cron-triggered purge endpoints still receive service-role
  authorization from Supabase Vault/pg_net.
- Confirm the production smoke summary reports that every retrieved real
  anon/publishable project key received `401` from `community-taxonomy-status`.
  A `200` with an empty data set is an authorization failure, not a harmless RLS
  result.
- Confirm the deploy's hash-only gate matched the stored SHA-256 digest for
  `MERIAN_SUPABASE_SERVER_API_KEY` to the exact selected production key before
  Function rollout. Never print the key or either digest. A final positive `401`
  with the fixed `X-Merian-Handler: 1` marker is a handler-owned denial; use the
  restricted structured auth event rather than bypassing the guard.
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
- Delete one disposable audio scan and invoke `auto-purge-nonbio` with one
  expired non-biological audio scan. Confirm the route first leaves the row
  present with a pending private deletion fence, then `reconcile-scan-deletions`
  removes its source recording and derived spectrogram before completing row
  deletion. A recent non-biological control and an expired biological control
  must remain unfenced.
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
