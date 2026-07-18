# Merian Supabase Backend

The Supabase backend for Merian. This directory contains the PostgreSQL database migrations, Deno Edge Functions, and related configuration.

## Structure

```text
services/supabase/
  config.toml      # Supabase CLI and Edge Function configuration
  functions/       # Deno Edge Functions (e.g., identify-multimodal)
  migrations/      # PostgreSQL database migrations
  scripts/         # Helper scripts for backend tasks
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
schema, the scan-ingestion job ledger, and the drift-repair SQL that must run
before media reconciliation indexes are created.

The same migration contract suite covers the identification-latency migration:
service-role-only RPC grants, the atomic ingestion setup function, combined
dictionary hydration, and the RLS-protected deferred-context table/trigger.

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
level advancement, and idempotent reapplication. The existing
`apply_scan_progress` request does not change; legacy clients ignore the
additional response fields and the new iOS client falls back to current counts
until the migrations are live.
