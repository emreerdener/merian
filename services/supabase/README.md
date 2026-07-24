# Merian Supabase Backend

The Supabase backend for Merian. This directory contains the PostgreSQL database migrations, Deno Edge Functions, and related configuration.

## Structure

```text
services/supabase/
  config.toml      # Supabase CLI and Edge Function configuration
  functions/       # Deno Edge Functions (e.g., identify-multimodal)
  migrations/      # PostgreSQL database migrations
  scripts/         # Helper scripts for backend tasks
  tests/           # pgTAP database authorization/behavior contracts
  test_auth.ts     # Auth testing utilities
```

## Edge Functions

Edge Functions are written in TypeScript and run on Deno. They handle logic like AI inference (`identify-multimodal`), gamification telemetry, public user profile updates, and Explore feed projections.

- **Configuration**: Every new Edge Function MUST have a
  `[functions.<name>]` entry in `config.toml`. Keep `verify_jwt = true` for
  routes called only with a Supabase user JWT (anonymous sessions also carry
  user JWTs). Use `false` only for deliberately public routes, service-key
  workers, webhooks, or a documented custom in-handler verification policy.
  A `false` route must enforce that replacement boundary in code. CI compares
  the complete configured-name set with the complete discoverable graph-name
  set; it does not maintain a hard-coded function count.
- **Dependencies**: `functions/deno.json` is the reviewed source manifest for
  exact dependency pins, and every deployable function has a generated local
  `deno.json` that points at the shared frozen `functions/dependencies.lock`.
  Runtime imports use those aliases instead of direct `esm.sh`, `deno.land`,
  npm, or JSR specifiers. The whole fleet uses one exact
  `@supabase/supabase-js@2.110.6` graph; `_shared/claimsAuth.ts` remains the
  opt-in authentication policy boundary for cached-JWKS claims verification,
  not a second SDK dependency. Generated configs explicitly retain Deno's
  one-day minimum dependency age; reviewed versions already present in the
  frozen lock install reproducibly, while future unlocked resolutions must age
  before adoption.

### Identification Latency Contract

`identify-multimodal` remains the single production inference request for a
scan. Free uses `gemini-2.5-flash`; Pro uses `gemini-2.5-pro`. Latency changes
must not alter prompts, response schema, thinking budgets, media resolution,
output-token limits, or the one-`generateContent`-call invariant.

The latency-sensitive path uses cached ES256 JWKS verification through
`auth.getClaims`, injected only by the two latency-sensitive routes so unrelated
functions retain their existing `getUser` behavior; `begin_scan_ingestion` for
atomic pre-Gemini setup; and
`hydrate_identification_dictionary` for post-Gemini cache hydration. External
cache misses and optional ingestion work run as Edge background tasks except
for required video durability. `/update-scan-context` applies or stages late
owner weather/location fields without rerunning inference. See the function-
local READMEs and `docs/system-architecture/04-ai-engineering.md` for the full
contract.

### Public Species Contract

`species-dictionary` is an intentionally public, read-only Edge Function with
`verify_jwt = false`. Detail requests do not read viewer identity and return
only the versioned species-level projection built by
`functions/_shared/publicSpeciesProjection.ts`. Do not add scan, user, Explore
post, location, field-note, comment, local-media, AI-reasoning, or preferred-name
fields to that response.

The iOS Species Dictionary and the server-rendered
`https://naturebook.earth/species/{speciesId}/{slug}` route share this contract.
The web server invokes the function with `species_id`; the readable slug is
derived from response names and is never sent to Supabase or used for lookup.
UUID-only and stale-slug browser routes redirect to the current canonical path
after a successful response. The web server does not query broad tables. Before
rendering or choosing social metadata imagery, the web mapper runs
`publicWebReferenceImageAttributionIssues(...)` and omits incomplete rights
rows. Similar-species thumbnails stay hidden until their payload carries
equivalent license and attribution fields.

Contract coverage lives in
`functions/_shared/publicSpeciesProjection_test.ts` and
`apps/web/lib/species.test.ts`. The former locks privacy, schema, content
quality, and attribution auditing; the latter locks UUID validation, public
mapping, slug generation and compatibility redirects, 404/transient error
semantics, metadata helpers, native URLs, and the exact AASA path list.

### Internal Admin Boundary

Migration `20260719161112_add_internal_admin_foundation.sql` owns the private
membership/session/audit/review/feedback/pricing schema, service-owned user
report intake, reversible Explore moderation, and append-only AI usage ledger.
The browser admin has no service-role key and reaches this state only through
the explicitly granted authenticated RPCs.

`functions/report-user/` is the authenticated visible-profile intake endpoint;
`functions/_shared/aiUsage.ts` normalizes Gemini usage for durable or bounded
best-effort ledger writes. Database authorization and behavior coverage lives
in `tests/admin_foundation_security.sql` and `tests/admin_review_ai.sql`.

See [`docs/backend-and-data/10-internal-admin.md`](../../docs/backend-and-data/10-internal-admin.md)
and the
[`docs/backend-and-data/11-internal-admin-operations.md`](../../docs/backend-and-data/11-internal-admin-operations.md)
runbook before changing grants, roles, sessions, review transitions, visibility,
pricing, or auditing.

### Privileged Routine Execution Boundary

Migration
`20260723144640_harden_privileged_routine_execution.sql` makes public-schema
`SECURITY DEFINER` functions deny-by-default even though `public` remains a
Data API schema. It revokes PostgreSQL's default function execution from
`PUBLIC` and the Supabase API roles for the repository migration owner, removes
historical execution from every public definer function, fixes every definer
to `search_path = ''`, and then reapplies only the reviewed entries in
`internal.privileged_routine_grants`.

The resulting contract is:

- `PUBLIC` and `anon` execute no public-schema definer function.
- `authenticated` receives only caller-bound admin and ghost-upgrade RPCs.
  Each authorized body must derive the caller from `auth.uid()`/`auth.jwt()` or
  call `internal.require_admin(...)`.
- `service_role` receives only an Edge worker or documented operator RPC. Every
  such body calls `internal.require_service_role()`; SQL-language functions are
  wrapped as PL/pgSQL so this check cannot be omitted.
- Trigger and implementation helpers receive no API-role grant.
- An application definer routine must be owned by `postgres`, use an empty fixed
  search path, and fully qualify application objects, types, and extension
  operators.

Never grant a definer function ad hoc. Add its exact identity signature and
purpose to the migration-owned allowlist, document its caller boundary, and run
both the static and catalog tests. If a public definer appears under another
owner (including a Supabase-managed owner), the audit fails; resolve ownership
or the creator's default privileges explicitly rather than weakening the test.

Catalog validation is semantic, not just migration-syntax validation.
`supabase db push --local` can succeed while SQL inside a PL/pgSQL routine still
contains an unresolved catalog function or overload. The pgTAP catalog gate runs
`plpgsql_check` and reports the exact routine signature, source line, SQLSTATE,
statement, query, detail, and hint. Treat that first PostgreSQL exception as the
root cause; pg_prove's later `Dubious`, `Bad plan`, and
`planned 1 but ran 0` messages are consequences of the aborted test.

Schema qualification does not compensate for a misspelled catalog routine or an
incorrect argument type. Verify the exact `pg_proc` identity and explicitly cast
overloaded arguments. The quota reservation lock, for example, deliberately uses
`pg_catalog.HASHTEXTEXTENDED(..., 0::BIGINT)`, and the migration contract locks
that signature.

PostgreSQL conditional expressions are not ordinary catalog routines and must
not be schema-qualified. In particular, do not write
`pg_catalog.COALESCE(...)`. When an
`INSERT ... ON CONFLICT DO NOTHING RETURNING TRUE INTO event_inserted` statement
returns no row, PL/pgSQL leaves `event_inserted` null; branch on
`event_inserted IS NOT TRUE` so both null and false take the durable-duplicate
path. The catalog gate validates this routine body after migration replay.

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines

# Read-only hosted-database verification. The URL is never printed.
MERIAN_DATABASE_URL='postgresql://...' \
  make audit-supabase-privileged-routines
```

Production CI runs the same catalog audit in report mode before `db push` and
in enforcement mode immediately afterward. See the deployment runbook for the
incident and forward-repair procedure.

### Authoritative AI Entitlement and Quota Boundary

Migration `20260723160229_enforce_server_ai_quotas.sql` makes paid-model access
a database decision. Public Edge routes use `_shared/aiQuota.ts` to call
`reserve_ai_quota(user, operation, request_id, ip_hash)` before provider work.
That single transaction locks and resolves the durable entitlement and selected
policy, chooses an allowlisted model, applies a daily safety ceiling plus shared
per-user/IP rate limits, and records an idempotent reservation. The row locks
give concurrent tier/policy changes and reservations a single database order;
future-dated profiles never extend the seven-day trial. The Edge route commits
immediately before provider dispatch. Only a proven pre-provider no-op, such as
a moderation cache hit or rejected empty multimodal request, may refund.
Every attempt carries a ten-minute database lease and a fresh fencing token;
expired pre-provider reservations are refunded automatically, and a late
settlement from an older attempt cannot mutate a retry. A provider failure
transitions `committed` to `failed`: counters remain charged, but the same
request key can make a newly metered retry.

The internal policy matrix distinguishes `free`, `pro_trial`, and `pro_paid`.
Current UTC-day safety ceilings are:

| Operation bucket | Free | Pro trial | Paid Pro |
|---|---:|---:|---:|
| Primary image/description/audio scans | 1 | 50 | 500 |
| Cache-miss overview/lookalike/group-tag enrichment | 4 | 100 | 500 |
| Explore/Community audio moderation | 3 | 25 | 100 |
| Insight/Explore model chat work | denied | 60 | 120 |

These are abuse and cost ceilings, not client entitlements. Change them only in
a reviewed forward migration, increment the policy version, and keep every
operation in `AIQuotaOperation`,
`aiQuotaMigrationContract.test.ts`, `aiQuotaCoverage.test.ts`, and
`tests/ai_quota_security.sql` aligned.

Executable security fixtures insert test profiles directly instead of running
the Auth signup trigger. Any such owner-only `public.users` fixture must
provide a deterministic, unique `public_username` accepted by
`public.is_valid_public_username(...)`, a non-empty `public_author_name`, and a
CHECK-valid `public_identity_source`; all three columns are `NOT NULL`. Usernames
are currently 3–24 lowercase characters, must start with a letter and end with
an alphanumeric character, cannot contain `__`, and cannot be reserved. Fix a
stale fixture rather than weakening the production identity constraints.

`users.entitlement_version` advances whenever the tier or timed expiry changes.
`_shared/entitlement.ts` performs durable reads for non-provider checks; it
never caches authorization in an Edge isolate. A query error or missing user
row fails closed with `503 ai_entitlement_unavailable`. Authenticated clients
cannot insert/delete `public.users` rows or update tier, expiry, or entitlement
version; only the two reviewed preference columns remain directly writable.

IP buckets store a daily-rotating, domain-separated HMAC, never a raw address.
`AI_QUOTA_IP_HASH_SECRET` is an optional dedicated override. When it is absent,
Edge code uses the built-in server-only Supabase secret/service-role key; an
explicit override shorter than 32 characters still fails closed. The deploy
workflow validates and synchronizes the override only when configured.

### RevenueCat delivery boundary

`revenuecat-webhook` requires a constant-time Authorization credential and
RevenueCat's timestamped raw-body HMAC. After verification it fetches
authoritative CustomerInfo with `REVENUECAT_SECRET_API_KEY`; webhook event types
alone never grant or revoke access. All three credentials are required GitHub
`Production` secrets synchronized to Supabase by the deploy workflow.

Migration `20260723201500_secure_revenuecat_webhook_delivery.sql` records
RevenueCat event IDs under a unique constraint and keeps a per-user ordering
watermark. `apply_revenuecat_customer_state(...)` orders by provider event time,
then CustomerInfo snapshot time, in the same transaction that updates tier and
expiry. The event ledger has child subject rows so `TRANSFER` can reconcile and
commit both its source and destination under one event ID; all affected user
rows are locked in deterministic UUID order. Duplicate or delayed events cannot
overwrite newer access. Reuse of an event ID with a different payload digest is
rejected. The
service-only `get_revenuecat_webhook_event_result(...)` lookup prevents durable
duplicates from causing another provider API call. Both RPCs use an empty search
path and caller check; the internal ledger tables have RLS enabled and no direct
API-role grants. Billing does not create missing users and rejects an identity
set that ambiguously maps to multiple live profiles.

Keep `revenueCatWebhookCoverage.test.ts`,
`revenueCatWebhookMigrationContract.test.ts`, the route's focused unit tests,
and `tests/revenuecat_webhook_security.sql` in the deploy gate. See
[`functions/revenuecat-webhook/README.md`](./functions/revenuecat-webhook/README.md)
for the protocol, rollout, and rotation contract.

### Explore Author Maintenance

Explore read functions are projection-only. They must not refresh public author
identity or repair post ownership while serving feeds, profiles, comments,
notifications, maps, mentions, hashtags, species pages, or post detail. Public
author maintenance belongs on the write paths that can make the projection
observable: Explore sharing, Explore and Field trip comment creation, Community
requests, auth metadata triggers, and ghost-profile merge.

Migration `20260720042641_optimize_explore_author_maintenance.sql` keeps
`refresh_public_author_identity(uuid)` idempotent, hardens both maintenance
functions with `SECURITY DEFINER SET search_path = ''`, and grants execution
only to `service_role`. The refresh returns without writing when the safe public
projection already matches, preventing repeated row-version churn. Never grant
either maintenance RPC to `PUBLIC`, `anon`, or `authenticated`, and never move
them back into a read endpoint to repair data opportunistically.
This follows Supabase's
[database-function security guidance](https://supabase.com/docs/guides/database/functions)
for fixed search paths and explicit execute privileges.

### Ghost Account Upgrade Boundary

Direct Apple/Google identity linking remains the primary anonymous upgrade path.
Only the exact Auth error `identity_already_exists` may enter
`functions/merge-ghost-profile/`. The anonymous source issues a hashed,
provider-subject-bound 30-day handoff; the permanent destination consumes it in
one serialized database transaction. The caller cannot nominate either user
UUID.

The foreground endpoint deletes the obsolete anonymous Auth row after commit.
`functions/reconcile-ghost-profile-merges/` is the five-minute,
service-role-only recovery worker for interrupted cleanup. It has
`verify_jwt = false` solely for `pg_net` compatibility and performs a
timing-safe service-role bearer comparison in Deno. See the two function
READMEs and the deployment runbook before changing this protocol.

### Public Species-Stats Resource Boundary

Migration `20260724170709_harden_species_observation_stats.sql` bounds the
intentionally public `/species-observation-stats` route. The request must bind a
dictionary UUID to its canonical name. Atomic database counters enforce
request user/IP limits and colder user/IP/global provider-work limits. Exact
taxon misses and provider failures receive status-aware negative cache TTLs.
Provider failures with no useful buckets become `unavailable`, never empty
`partial` results.

Cold population uses a 90-second database row lease. The final cache write
compares the lease UUID in the same transaction, so another Edge isolate cannot
stampede the same species and a delayed generation cannot overwrite newer
work. The four public-schema wrappers preflight IP use, authorize canonical
species, claim work, and finalize cache state. Each is `SECURITY DEFINER`, uses
an empty search path, calls `internal.require_service_role()`, and is executable
only by `service_role`; their tables have no direct API-role grants. Provider
fetches also have explicit per-call/operation deadlines and streaming response
caps. See the function README and deployment runbook before changing these
limits.

An unavailable refresh cannot erase positive data still inside the 37-day
retention ceiling. Fenced finalization preserves the payload and original
`fetched_at`, marks it `stale`, records the current row-level cache error, and
sets a five-minute retry backoff. The iOS memo cache similarly admits only
schema-v2 or newer responses whose canonical UUID/name matches its request.
Successful public responses do not vary by Authorization, preserving shared
cache reuse instead of creating per-token origin traffic.

### Testing Edge Functions

Before opening a PR targeting `services/supabase/functions`, run formatting,
linting, dependency-policy validation, and type checking:

```bash
cd services/supabase/functions
deno fmt --check
deno lint --config deno.json
cd ../../..
deno run --allow-read=services/supabase \
  services/supabase/scripts/sync_function_deno_configs.ts --check
deno run --allow-read=services/supabase \
  services/supabase/scripts/validate_function_dependencies.ts
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase \
  services/supabase/scripts/function_dependency_tools_test.ts
deno check --frozen \
  --config services/supabase/functions/<function>/deno.json \
  services/supabase/functions/<function>/index.ts
```

After changing a pin in `functions/deno.json`, regenerate the function-local
configs with `sync_function_deno_configs.ts`, refresh
`functions/dependencies.lock`, and commit all three surfaces together. CI rejects
stale generated configs, unlocked packages, direct runtime specifiers, and any
missing or stale `config.toml` function entry. When the fleet changes, fix the
reported name mismatch; never update a numeric expected-function count.

Run Deno tests:
```bash
deno test --config deno.json --allow-env --allow-net \
  --allow-read=../migrations _tests/
```

### Testing Database Migrations

Media durability migrations have an additional static contract test that runs
without a local Postgres instance. It checks the normalized scan-media lifecycle
schema, the scan-ingestion job ledger, the drift-repair SQL that must run before
media reconciliation indexes are created, and the source-aware uniqueness
repair for generated versus promoted capture-upload rows.

The same migration contract suite covers the identification-latency migration:
service-role-only RPC grants, the atomic ingestion setup function, combined
dictionary hydration, and the RLS-protected deferred-context table/trigger.
It also guards the APNs device-token repair so PostgreSQL format validation and
32...512 character length validation remain separate. The executable pgTAP
coverage in `tests/push_device_registration.sql` accepts a normal 64-character
hex token and rejects short, oversized, and non-hex tokens.

The suite also locks the Explore current-scan reference exclusion helper and
the unchanged `get_explore_post_detail` response projection. Run the static
contract plus the executable DB case after changing species-reference ordering,
blocked-media handling, legacy fallback, or scan media fields:

Public species stats have both static and executable security contracts:

- `_tests/speciesObservationStatsCoverage.test.ts` prevents removal of
  dictionary binding, deadlines, body limits, or fenced RPC calls.
- `_tests/speciesObservationStatsMigrationContract.test.ts` locks rates, ACLs,
  lease duration, negative TTLs, and finalization fencing.
- `tests/species_observation_stats_security.sql` executes canonical denial,
  persistent rate accounting, cross-isolate claim suppression, expired-token
  fencing, cache-race closure, and API-role ACL checks.

`_tests/migrationExecutionContract.test.ts` scans every SQL migration after
removing comments and rejects `CREATE`, `DROP`, or `REINDEX ... CONCURRENTLY`.
Fresh local and CI databases replay migrations through a Supabase statement
pipeline, where concurrent index DDL is not consistently supported. Keep the
checked-in migration pipeline-compatible. If a large production table needs a
zero-downtime index, create it in a separately supervised direct database
session first, verify `pg_index.indisvalid`, and retain a non-concurrent
`CREATE INDEX IF NOT EXISTS` migration for fresh environments.

```bash
deno test --allow-read \
  services/supabase/functions/_tests/migrationMediaContract.test.ts
SUPABASE_DB_TEST_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  deno test --allow-env --allow-net \
  --filter "excludes only the current scan media" \
  services/supabase/functions/_tests/explorePostDetailDb.test.ts
```

Run the focused checks from the repository root after the local Supabase stack
is available:

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/push_device_registration.sql
supabase --workdir services test db --local \
  services/supabase/tests/scan_media_asset_uniqueness.sql
supabase --workdir services test db --local \
  services/supabase/tests/species_observation_stats_security.sql
```

Keep the pgTAP fixture local; do not substitute `--linked`. Before deploying a
database repair, run `supabase --workdir services db push --linked --dry-run`
and confirm only the reviewed migrations appear. After deployment, run
`supabase --workdir services migration list --linked`, then inspect
`pg_constraint` read-only. For the APNs repair, both
`user_push_devices_device_token_format_check` and
`user_push_devices_device_token_length_check` must exist with
`convalidated = true`. The migration is database-only; the existing
`register-push-device` Edge Function does not need redeployment.

For the scan-media uniqueness repair, the legacy
`scan_media_assets_scan_id_order_index_key` constraint must be absent. The
`idx_scan_media_assets_generated_unique` partial unique index must cover
`(scan_id, source, role, order_index)` only for `scan_refresh` and `backfill`,
and `idx_scan_media_assets_upload_session_unique` must cover
`(upload_session_id, order_index)` only when the upload session is present. This
allows a promoted `capture_upload` audit row to coexist with its generated ready
row while still rejecting duplicate positions within either writer contract.

Field trips migrations also have static contract coverage. The current chain is
V1 template/progress/publication storage, V2 guided detail/start/pins, V3
Community/activity, and V4 curated Seasonal Challenges with explicit joins,
challenge progress, badges, challenge entries, and optional Explore hashtag
suggestions. The contextual objective-guide migration supplies structured Tips,
`20260717195751_active_outing_capture_context.sql` adds the private service-role
capture read model.
`20260717213641_preserve_standard_outings_in_capture_context.sql` keeps the
underlying standard field trip visible after a Seasonal Challenge join while still
ignoring challenge-specific progress.
`20260717224544_retire_forest_edges_outing.sql` deactivates the Forest Edges
placeholder without deleting historical user data.
`20260718043218_expose_field_trip_completion_scan_ids.sql` adds the completing
scan ID to the private catalog/detail projections while restricting both RPCs
to `service_role`.
`20260718051748_expose_field_trip_publication_status.sql` adds the owner's
active non-deleted publication ID/timestamp to private template detail only.
`20260718150932_add_credited_field_trip_progress.sql` extends both standard and
Seasonal Challenge scan-progress responses with the level number/title and
completed/target counts credited by the scan. It preserves the existing RPC
signatures, permissions, and response fields; the added fields let a level-
completion toast show the completed level rather than the newly active level.
`20260718162409_scope_credited_progress_to_current_attempt.sql` scopes those
credited counts to checklist items matched by the current application attempt,
so re-identifying an older scan cannot duplicate a destination or reuse a
previous level's ring.
`20260722025411_persistent_field_trip_scan_contributions.sql` adds the private
selected-goal preference, deterministic one-credit ranking, correction support,
and scan contribution projection.
`20260722064704_harden_atomic_field_trip_progress.sql` moves standard progress,
Event progress, preference persistence, first-outing achievement evaluation,
and the scan-revision receipt into one transaction. Scan insertion/correction
triggers call that boundary from the ingestion pipeline. The migration also
repairs completed-outing publication item materialization, removes the pin RPC's
temporary-table dependency, and revokes all Field
trip/Event `SECURITY DEFINER` functions from `PUBLIC`, `anon`, and
`authenticated`; only `service_role` may execute them.
`20260722195453_exclude_ants_from_bee_wasp_goal.sql` first excludes `Formicidae`
from Park Pollinators' Hymenoptera goal and repairs ant-backed progress.
`20260722211636_tighten_field_trip_goal_matching.sql` adds conjunctive
taxonomy-plus-signal matching, finalizes **Bee or wasp** as Hymenoptera plus
`bee|wasp`, narrows active Spider/Butterfly/plant/animal goals, aligns
unverifiable Park prompt copy with saved-scan evidence, and repairs progress
credited by the former broader rules.
The contract suite verifies caller identity, role grants, ordering/filtering
clauses, private completion links/status, credited progress in both RPCs, and
the absence of evidence from public/capture projections.
`fieldTripCaptureContextDb.test.ts` additionally executes the
filtering/order/privacy contract, while `fieldTripProgressDb.test.ts` exercises
standard/challenge credited counts, level advancement, re-identification,
idempotent reapplication, and representative positive/negative cases for every
narrowed active goal. `fieldTripAtomicProgressDb.test.ts` proves rollback
when the Event half fails, `fieldTripSecurityDb.test.ts` enumerates runtime
execute privileges, and `fieldTripPublicationDb.test.ts` executes publication
materialization. These require the local Postgres stack; a connection skip is
not database validation.

Explore identity integration coverage in `_tests/exploreIdentityDb.test.ts`
executes the public projection and ownership-repair functions against Postgres.
It verifies custom-avatar precedence, no row rewrite after identity convergence,
ownership repair, and service-role-only execution. Database helpers use the
standard local URL when `SUPABASE_DB_TEST_URL` is absent and may report a skip
when that default stack is unavailable. When `SUPABASE_DB_TEST_URL` is set
explicitly, a connection failure fails the test; this is the required mode for
CI and release validation.

```bash
SUPABASE_DB_TEST_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  deno test --allow-env --allow-net \
  services/supabase/functions/_tests/exploreIdentityDb.test.ts
```

From the repo root:

```bash
make validate-supabase-migrations
```

## Local Development

Use Supabase CLI `2.109.0` or newer; CI pins `2.109.1`. The repository keeps
every migration compatible with fresh-schema statement-pipeline replay rather
than depending on CLI-specific handling for concurrent index DDL. The minimum
also recognizes the `[local_smtp]` configuration used by this project. Confirm
the local version before database verification:

```bash
supabase --version
```

From the repo root, point the Supabase CLI at the backend service directory:

```bash
# Start local Supabase stack
supabase --workdir services start

# Serve edge functions locally
supabase --workdir services functions serve <function_name>
```

### Ghost User Audit

Use the read-only audit before considering any anonymous-user cleanup. It reads
Auth Admin users plus public activity tables, classifies likely empty ghost
profiles, and writes reviewable JSON/CSV/Markdown snapshots. The audit also
calls the service-role-only protected-source RPC; prepared handoffs and merged
receipts awaiting Auth cleanup count as activity and can never become deletion
candidates. It does not delete or mutate data.

```bash
SUPABASE_URL="https://<project>.supabase.co" \
SUPABASE_SECRET_KEY="<sb_secret_...>" \
make audit-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --snapshot-csv /tmp/ghost-users.csv --summary-md /tmp/ghost-users.md"
```

`SUPABASE_SERVICE_ROLE_KEY` is still accepted for older projects, but new
Supabase projects should use a secret key from Settings > API Keys.

Review cleanup candidates with the guarded cleanup dry-run. This reads the audit
JSON and does not delete unless `--execute` and the confirmation flag are both
present.

```bash
make cleanup-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --limit 10 --output-json /tmp/ghost-cleanup-dry-run.json"
```

After manually reviewing a dry-run batch, execute only a tiny batch:

```bash
SUPABASE_URL="https://<project>.supabase.co" \
SUPABASE_SECRET_KEY="<sb_secret_...>" \
make cleanup-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --limit 10 --execute --confirm-delete-likely-empty-ghosts --output-json /tmp/ghost-cleanup-result.json"
```

Execute mode performs a second, live database reservation for each candidate
before calling Auth Admin delete. The reservation and handoff issuance share an
advisory lock: if an account upgrade is prepared first, cleanup fails closed; if
cleanup reserves first, prepare returns a retryable error without switching the
guest session. Do not run a historical version of the cleanup script after the
secure merge migration.

## Deployment

### Database Migrations
```bash
supabase --workdir services db push
```

Do not bypass the privileged-routine gate for a manual push. Run
`make test-supabase-privileged-routines` against the fully migrated local
catalog, capture a hosted `--report` audit before the push, and require a clean
`make audit-supabase-privileged-routines` result after it.

### Edge Functions
```bash
supabase --workdir services functions deploy
```

That command is the emergency/manual full-fleet path. Production CI computes
the affected functions from the transitive import graph, deploys bounded
batches, and isolates retries to members of a failed batch. A manual workflow
dispatch intentionally selects the full fleet. Database migrations still run
before function deployment, so same-release schema changes must follow
expand/migrate/contract compatibility: the migration must remain safe for the
currently live function version, and destructive cleanup ships only after the
new readers/writers are proven live.

For identification-latency releases, apply migrations before deploying function
code that calls the new RPCs, then stage the client and Edge rollout using the
gates in `docs/backend-and-data/06-supabase-deployment-runbook.md`. Do not force
an Edge region without the documented A/B evidence.

For the Field trip Scan indicator, apply the contextual-guide, active-field trip
capture-context, and standard-field trip preservation migrations before deploying
`field-trips`, then smoke-test the authenticated `capture_context` action before
releasing the iOS client. The RPC
is intentionally unavailable to direct `anon` and `authenticated` database
calls; only the verified Edge action may invoke it with `service_role`. The
long-term client/source boundary and extension rules are recorded in
`docs/rfcs/active-capture-goal-context.md`.

For completed-goal thumbnails, also apply
`20260718043218_expose_field_trip_completion_scan_ids.sql` before releasing the
iOS client. Smoke-test that catalog/detail return the exact completion
`scan_id`, direct client roles cannot execute those RPCs, and public profile,
publication, challenge, Explore, and capture-context payloads remain
evidence-free.

For the Private/Published detail badge, apply
`20260718051748_expose_field_trip_publication_status.sql` before releasing the
iOS surface. Verify only private template detail receives the requesting
owner's active publication ID/timestamp and that direct client roles remain
unable to execute the RPC.

For credited scan-progress notifications, apply
`20260718150932_add_credited_field_trip_progress.sql` and then
`20260718162409_scope_credited_progress_to_current_attempt.sql` before releasing
the iOS toast surface. Verify partial progress, level advancement, final
completion, multiple standard/challenge destinations, re-identification after
level advancement, and idempotent reapplication. Those two migrations add only
response fields; legacy clients ignore them and newer clients fall back to
current counts until the migrations are live. The later persistent-
contribution release adds optional `preferred_goal` to the request.

For persistent Insight contribution cards and selected-goal preference, apply
`20260719045306_first_field_trip_achievement.sql`,
`20260719160750_field_trip_lifecycle_controls.sql`,
`20260720014446_update_backyard_safari_copy.sql`,
`20260722025411_persistent_field_trip_scan_contributions.sql`,
`20260722064704_harden_atomic_field_trip_progress.sql`,
`20260722195453_exclude_ants_from_bee_wasp_goal.sql`, and
`20260722211636_tighten_field_trip_goal_matching.sql` in order. Then deploy the
scan-ingestion functions and `field-trips` before the iOS client. Smoke-test
optional `preferred_goal`, one credit per outing/Event, deterministic fallback,
correction removal/move, bee/wasp acceptance with ant and sawfly rejection,
the representative negative-match matrix, transactional rollback, receipt
replay, publication, and `scan_contributions`. Direct client roles must not read
either private progress table or execute any Field trip/Event
`SECURITY DEFINER` RPC;
contribution payloads must contain no media, coordinates, place labels, notes,
or public evidence. Older clients omit the preference and remain compatible.
