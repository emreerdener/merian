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

- **Configuration**: Every new Edge Function MUST have a `[functions.<name>]` entry in `config.toml`. Pay attention to `verify_jwt` (set to `false` for app-facing anonymous-compatible functions to bypass gateway-level JWT validation, allowing the function to handle validation internally).
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
deno check --frozen \
  --config services/supabase/functions/<function>/deno.json \
  services/supabase/functions/<function>/index.ts
```

After changing a pin in `functions/deno.json`, regenerate the function-local
configs with `sync_function_deno_configs.ts`, refresh
`functions/dependencies.lock`, and commit all three surfaces together. CI rejects
stale generated configs, unlocked packages, direct runtime specifiers, or a
function missing its `config.toml` entry.

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
supabase --workdir services db push --local
supabase --workdir services test db --local \
  services/supabase/tests/push_device_registration.sql
supabase --workdir services test db --local \
  services/supabase/tests/scan_media_asset_uniqueness.sql
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
The contract suite verifies caller identity, role grants, ordering/filtering
clauses, private completion links/status, credited progress in both RPCs, and
the absence of evidence from public/capture projections.
`fieldTripCaptureContextDb.test.ts` additionally executes the
filtering/order/privacy contract, while `fieldTripProgressDb.test.ts` exercises
standard/challenge credited counts, level advancement, re-identification, and
idempotent reapplication. Both require the local Postgres stack; a connection
skip is not database validation.

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
profiles, and writes reviewable JSON/CSV/Markdown snapshots. It does not delete
or mutate data.

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

## Deployment

### Database Migrations
```bash
supabase --workdir services db push
```

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
`20260720014446_update_backyard_safari_copy.sql`, and
`20260722025411_persistent_field_trip_scan_contributions.sql` in order. Then
deploy `field-trips` before the iOS client. Smoke-test optional
`preferred_goal`, one credit per outing/Event, deterministic fallback,
correction removal/move, and `scan_contributions`. Direct client roles must not
read `field_trip_scan_goal_preferences` or execute
`get_field_trip_scan_contributions`; contribution payloads must contain no
media, coordinates, place labels, notes, or public evidence. Older clients omit
the preference and remain compatible.
