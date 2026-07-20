# Supabase Deployment Runbook

Naturebook's long-term Supabase release path is GitHub Actions, while backend
function, RPC, migration, and storage identifiers retain their Merian technical
identity. Local `supabase login` is useful for emergency maintenance, but
production deploys should be repeatable from CI with explicit secrets and
validation.

## Legacy Location-Label Repair

If a scan has exact coordinates but no `semantic_location`, changing an Explore
post’s `location_sharing` cannot produce a label. Preview a targeted repair with:

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
safety, or another independent check.
Large commits render at most 100 changed-file bullets and then append a
truncation marker. `test-ci-run-summary.sh` locks that behavior without an
early-closing pipeline, because `set -o pipefail` would otherwise turn an
expected SIGPIPE into exit 141 before validation or deployment begins.

The workflow performs the following steps:

1. Writes the workflow context summary and exercises its large-change regression
   test.
2. Installs the exact reviewed Deno `2.9.2` runtime.
3. Installs the Supabase CLI.
4. Fails fast if required deployment secrets are missing.
5. Validates Edge Function formatting, lint, and shared runtime type checks.
6. Confirms every function has a current generated local `deno.json`, a matching
   `config.toml` entry, only approved aliased runtime imports, and a graph fully
   represented by the shared frozen `dependencies.lock`; then type-checks all
   function entrypoints with the exact local config Supabase will discover.
7. Runs focused shared-helper, deployment-planner, and static migration-contract
   tests. Source-inspection tests receive explicit read grants because Deno does
   not grant `readTextFile` access merely because a source is in the import graph.
8. Builds an affected-function deployment plan from the pushed Git diff. Manual
   dispatch and an unresolvable Git diff safely select the full fleet.
9. Prepares a Postgres connection string for database migrations without
   calling `supabase link`. The workflow prefers a full `SUPABASE_DB_URL`, but
   can also construct a session-pooler URL from `SUPABASE_DB_POOLER_HOST` plus
   `SUPABASE_DB_PASSWORD`.
10. Pushes database migrations with `supabase db push --db-url`.
11. Deploys the planned functions in bounded batches. A failed batch is retried
    function-by-function, so a transient graph failure cannot restart the whole
    fleet deployment.
12. Smoke-tests the Community Taxonomy status endpoint, the scan-media health
   endpoint, and a dry-run bounded GBIF import with the production service-role
   credential.

Actual GBIF taxonomy imports are intentionally separated into
`.github/workflows/import-community-taxonomy.yml`. The deploy workflow only
smoke-tests a dry run; it does not write taxonomy rows or advance import
cursors.

The deployment subset is computed from the TypeScript import graph rather than
a hand-maintained list. A route-local runtime change selects that route. A
shared-module change selects every function that transitively imports it. A
function-local `deno.json` change selects that function. Changes to
`config.toml`, the root dependency manifest, or the shared lock select the full
fleet because they can affect any bundle. New, deleted, or otherwise
unresolvable shared runtime files also fall back to the full fleet. Docs and
test-only changes select no functions. This preserves shared-helper consistency
without paying for an unconditional 77-function deployment on every backend
commit.

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
then remove old columns, constraints, RPC signatures, or compatibility code in
a later release. The workflow deliberately does not pretend migrations and
Edge bundles switch atomically.

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
the function check must be true. Smoke-test user-facing response and
export email copy, but continue to expect durable Merian values in internal
logs, headers, analytics, source fields, and route names. See the
[public brand compatibility contract](../system-architecture/08-public-brand-compatibility.md)
and [rebrand rollout runbook](../development-guides/15-naturebook-rebrand-rollout.md).

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
composer/share/edit function bundles must deploy together so
`scan_media_assets` and `explore_post_media` only set `has_audio` when
`captured_media` proves an audio companion exists.

Audio moderation-attestation releases are migration-first. Apply
`20260711055524_add_explore_audio_moderation_attestations.sql` before deploying
the updated `_shared/audioModeration.ts`, `share-scan-to-explore`, and
`update-explore-field-notes` bundles. Functions safely fall back to live Gemini
when the table is temporarily unavailable, but deploying the migration first
avoids unnecessary provider calls and cache-error logs. Never deploy a function
that treats a cache error as approval.

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
`20260708021110_field_trips_v1.sql` before
`20260708033451_field_trips_v2.sql` before
`20260708042713_field_trips_v3_community.sql` before
`20260708051414_field_trips_v4_challenges.sql` before
`20260717150222_contextual_outing_objective_guides.sql` before
`20260717195751_active_outing_capture_context.sql` before
`20260717213641_preserve_standard_outings_in_capture_context.sql` before
`20260717224544_retire_forest_edges_outing.sql` before
`20260718043218_expose_field_trip_completion_scan_ids.sql` before
`20260718051748_expose_field_trip_publication_status.sql` before
`20260718150932_add_credited_field_trip_progress.sql` before
`20260718162409_scope_credited_progress_to_current_attempt.sql`, then deploy the
`field-trips` Edge Function and the updated Explore/profile activity bundles
together. V1
creates the Field trip tables, progress/publication/comment storage, profile
visibility helpers, and publication snapshots. V2 adds guided template detail,
explicit starts, Recent compatibility pagination, and profile pins. V3 adds
the Community publication RPC, Field trip in-app activity storage, and Explore
activity union/read/count RPC updates. V4 adds curated seasonal challenge
storage, explicit joins, challenge-specific item completions, completion badges,
challenge entry snapshots, challenge entry comments/likes, and scan-scoped
hashtag suggestion helpers. The contextual-guide migration supplies the
structured Tips content used by focused target navigation. The capture-context
migration adds the private service-role RPC and its active-field trip/challenge
lookup indexes consumed by the Scan indicator. The preservation migration keeps
the shared standard field trip eligible after a Seasonal Challenge join while
leaving challenge-specific progress out of the capture payload. The Forest
retirement migration deactivates the placeholder while retaining
existing progress and evidence. The completion-evidence migration redefines
the private catalog/detail projections to expose the exact completing scan ID
without a media URL and restricts both RPCs to `service_role`. The publication-
status migration keeps template detail private and adds only the owner's active,
non-deleted publication ID/timestamp for the Private/Published badge. The
credited-progress migrations replace the standard/challenge progress RPC bodies
without changing their signatures or permissions and adds optional credited
level/count fields for scan-completion feedback. Those values preserve the
just-completed level when the existing current-level fields have already
advanced to the next level and stay scoped to checklist items matched by the
current attempt when an older scan is re-identified. A
function-only deploy cannot serve `capture_context` or V4 actions until all
migrations are applied; a database-only deploy leaves the app without the
Field trips action router. Do not release the indicator-enabled iOS client until
both the capture-context migration and updated function are live. Do not release
the completed-goal thumbnail route until the completion-evidence migration is
live; its optional decode keeps older database responses compatible during a
staged rollout. Release the status badge only after the publication-status
migration; its optional fields render Private against the older payload.
Deploy both credited-progress migrations, in order, before the progress-toast
iOS client.
The client can decode the legacy shape and fall back to current counts during a
staged rollout, and no Edge Function request-shape change is required, but level
completion will otherwise show the next level's `0/N` instead of a full ring.
If the current V4 `field-trips` function is already deployed, this incremental
release needs the two new migrations and iOS client only; the function does not
need to be redeployed solely for the response additions.

Current client rollout (2026-07-19): standard Field trips/Outings are public,
while Seasonal Challenge Events remain staged through
`FieldTripEventsAvailability.isReleased`. The tester account and simulator
builds bypass that iOS flag. This is not a Supabase feature flag or an
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
`deno.json` inside every function directory, and each generated config points
at the tracked frozen `services/supabase/functions/dependencies.lock`. Supabase
discovers the function-local config while bundling. Do not pass the retired
`--import-map` flag. Runtime code imports configured aliases; direct esm.sh,
deno.land, npm, and JSR specifiers are rejected from production graphs. The
fleet uses one exact `@supabase/supabase-js@2.110.6` dependency for both
`getUser` and `getClaims`. `_shared/claimsAuth.ts` remains opt-in to avoid
silently changing authentication policy for unrelated routes, not to isolate a
second SDK. `functions/dependencies.lock` is the only lockfile; do not add a
root or function-local `deno.lock` that can silently diverge from it.
The root and generated configs explicitly set `minimumDependencyAge` to `P1D`.
Deno 2.9 applies a one-day default even when the field is absent, but spelling
the policy out prevents toolchain drift. A fresh CI cache may download a version
already integrity-pinned in the frozen lock; newly resolved npm/JSR versions
must still satisfy the one-day delay. Do not disable the protection with
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

## Identification Latency Rollout

The image-analysis latency change is a staged operational rollout, not a reason
to change Gemini configuration. Free remains `gemini-2.5-flash`; Pro remains
`gemini-2.5-pro`. Prompts, schema, thinking budgets, image resolution,
`maxOutputTokens`, and the single primary identification model call per scan are
release invariants.
Audio and video receive the additive timing instrumentation but no client
behavioral change in this pass.

Release in three observable waves:

1. Deploy compatible timing instrumentation and establish pre-change p50/p95
   baselines for Gemini, non-Gemini Edge work, response-to-first-render, failures,
   missing remote scans, and stuck ingestion jobs.
2. Roll out the iOS critical-path changes: eligible live-camera still-image
   150 ms context grace, pinned-session prewarm, inline/background upload
   handoff, and first-result-before-secondary-work commit.
3. Roll out the Edge/database optimization. Within this wave, apply
   `20260715153946_reduce_identification_latency_round_trips.sql` before deploying
   `identify-multimodal`, `_shared` dependents, and `update-scan-context`. The
   identify handler has a temporary old-helper fallback for propagation safety;
   repeated fallback logs after rollout are an incident, not a steady state.

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
  `gemini`, `dictionary`, `post_gemini`, and `edge_total` and contains no private
  identifiers;
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
changelog and latency/AI/API/logging/offline-queue docs with the measured p50/p95
and the chosen Edge-region policy.

## Required GitHub Secrets

Set these in the repository's GitHub Actions secrets:

- `SUPABASE_ACCESS_TOKEN` — Supabase CLI access token for the deployment actor.
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
    `tenant/user postgres.<project-ref> not found`.
    Merian production's confirmed session-pooler host is
    `aws-1-us-east-1.pooler.supabase.com`.

Optional GitHub Actions variables:

- `SUPABASE_DB_POOLER_PORT` — defaults to `5432`, Supabase shared-pooler
  session mode.
- `SUPABASE_DB_NAME` — defaults to `postgres`.

Use the shared pooler for CI because GitHub-hosted runners are IPv4-only in
common configurations. Direct `db.<project-ref>.supabase.co:5432` hosts can
resolve to IPv6 only and fail before Postgres authentication.

The production Supabase project ref is intentionally stored in the workflow as
`qlarqavoqhkuwzmevrmf`. Project refs are routing identifiers, not credentials;
the deployment authority still comes from `SUPABASE_ACCESS_TOKEN` plus
the configured database connection. Post-deploy smoke checks and manual
taxonomy imports resolve the service-role key at runtime through
`supabase projects api-keys --project-ref qlarqavoqhkuwzmevrmf`, then mask it in
GitHub Actions logs.

If the Supabase dashboard or Management API is unavailable, do not guess the
pooler host in production secrets. Wait for the dashboard to recover, or get the
existing shared-pooler host from another operator who already has access. The
`supabase link` command also uses the Management API, so `504` or `500`
responses during a Supabase incident can block linking even when the migration
SQL itself is fine.
Using `db push --db-url` only removes the project-status lookup from the
migration step. Edge Function deploys, service-role key lookup, and smoke tests
still depend on Supabase's hosted APIs and can fail during an active platform
incident.

The workflow also inherits normal Supabase project Edge secrets at runtime.
Those live in Supabase, not GitHub Actions, and are documented in
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

## Scan Media Health Automation

The **Scan Media Health Monitor** workflow runs every 30 minutes and can also be
started manually from GitHub Actions. It resolves the production service-role
key at runtime through the Supabase CLI, calls `/scan-media-health`, writes JSON
and Markdown summary artifacts, and appends the Markdown report to the job
summary. The Markdown report includes an **Incident Actions** table that maps
each issue code to an owner, next step, runbook, and sample-field hint; use that
table as the first triage view before opening raw database rows.
It also includes a visible **Sample Preview** table with the first sample row
for each issue code. Expand the per-issue sample blocks or download the
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
  starts with
  `insertScan: column reference "image_url" is ambiguous`, first confirm
  migration
  `20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql` has reached
  production; retrying before that migration is deployed will only re-create the
  same failed job. For a manual service-role retry after the underlying error is
  fixed, POST
  `{ "limit": 5, "awaitInvocations": true }` to
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
  below the durable video count, run
  `reconcile-scan-media-assets` with `dryRun = true` before allowing a repair.
- `audio_scan_missing_ready_audio_asset`: confirm migrations
  `20260711143348_repair_scan_media_assets_audio_constraints.sql` and
  `20260711171512_backfill_missing_ready_audio_assets.sql` reached production.
  The first permits normalized audio rows; the second makes standalone audio
  part of `refresh_scan_media_assets(...)` and backfills every scan with a
  durable `audio_storage_urls` entry. After deploy, rerun the health monitor.
  If a sample remains, call `refresh_scan_media_assets(sample_scan_id)` and
  compare the ready audio URLs to `audio_storage_urls` before touching R2; the
  durable recording must be preserved.
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
  services/supabase/functions/_tests/migrationMediaContract.test.ts

make validate-supabase-migrations
make db-push
make functions-deploy
```

For local emergency migration pushes that should avoid `supabase link`, export a
database URL first:

```bash
export SUPABASE_DB_URL='postgresql://...'
make db-push
```

Or export the pooler pieces and let the shared script construct the URL:

```bash
export SUPABASE_PROJECT_ID='qlarqavoqhkuwzmevrmf'
export SUPABASE_DB_POOLER_HOST='aws-1-us-east-1.pooler.supabase.com'
export SUPABASE_DB_PASSWORD='...'
make db-push
```

If neither `SUPABASE_DB_URL` nor the pooler pieces are set, `make db-push` falls
back to the linked-project CLI behavior. `supabase link` reaches Supabase's
Management API to retrieve remote project status before it writes local link
metadata. A `504` at that step is a transient remote/status lookup failure, not a
migration failure. The GitHub workflow intentionally avoids that status lookup by
requiring an explicit database connection and using `db push --db-url` instead.
Direct Supabase database hosts can resolve to IPv6-only addresses; use the
pooler connection string in CI when a runner cannot reach IPv6. The warning
`environment variable is unset: SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` comes from
parsing the local Auth config and is not fatal for `db push`; only treat it as
actionable if a command fails while applying Auth provider config.

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
- For an exact external-reference-media suppression, apply its cleanup/write
  prevention migration before deploying dependent functions. Deploy every
  transitive consumer selected for `_shared/externalImagePolicy.ts`,
  `_shared/external.ts`, and `_shared/publicSpeciesProjection.ts` changes,
  including identify/enrichment, Species Dictionary, Explore post detail, and
  `refresh-species-content` surfaces. Query normalized and legacy reference
  data to confirm the denied path is absent, attempt a service-role normalized
  insert to confirm the trigger skips it, then confirm the public first-image
  helper promotes the next permitted URL. For media `605615444`, manually open
  the pictured Brown Tabby scan and verify the European wildcat card remains
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
  `profile_summaries` after the V1, V2, V3, V4, contextual-guide, and
  capture-context migrations plus the standard-preservation, Forest-retirement,
  completion-evidence, and publication-status follow-ups. Verify
  `capture_context` returns only accessible
  incomplete standard field trips and current-level unfinished targets, orders
  field trips by recent engagement, ignores Seasonal Challenge-specific completions
  without hiding the shared standard field trip, and returns no scan IDs, media,
  locations, field notes, species completion data, or other evidence. Confirm
  `PUBLIC`, `anon`, and `authenticated` cannot execute
  `public.get_field_trip_capture_context(uuid)` while `service_role` can.
  Verify catalog and template detail return each completed item's exact
  `user_field_trip_item_completions.scan_id`, return no media URL, and keep
  incomplete items evidence-free. Confirm `PUBLIC`, `anon`, and
  `authenticated` cannot execute `public.get_field_trip_catalog(...)` or
  `public.get_field_trip_template_detail(...)`, while `service_role` can.
  Confirm `completed_scan_id` is absent from capture context, public profile
  summaries, publication/challenge snapshots, Explore feed, and map payloads.
  Verify template detail returns `publication_id`/`published_at` only for the
  requesting owner's active non-deleted snapshot. Catalog and public/capture
  projections must remain unchanged, and direct client roles must remain unable
  to execute template detail.
  While Events are staged, verify a physical non-allowlisted account and ghost
  user see Outings but not the Events segment, requests, badges, routes, or
  hashtag suggestions; verify the allowlisted tester and simulator still see
  the full Events flow. Before public Events release, set the client release
  flag intentionally, promote the gated bundled changelog entry, update the
  rollout documentation and test lock, and rerun the Field trips iOS/Deno suites
  plus an unsigned device build. No backend deploy is implied unless a backend
  contract changed independently.
  Publishing a Field trip or challenge entry must not write `explore_posts`, map points,
  normal Explore post notification rows, APNs, widgets, public web share pages,
  prize rows, or leaderboard rows. Field trip comment/reply/followed-publication
  activity may appear in `field_trip_activity_notifications` and the in-app
  Explore activity feed.
- For Explore author-maintenance releases, apply
  `20260720042641_optimize_explore_author_maintenance.sql` before deploying the
  affected write and read functions. Confirm `PUBLIC`, `anon`, and
  `authenticated` cannot execute `refresh_public_author_identity(uuid)` or
  `repair_explore_post_ownership_for_user(uuid)`, while `service_role` can.
  Run `_tests/exploreIdentityDb.test.ts` with an explicit
  `SUPABASE_DB_TEST_URL`; verify a second converged refresh preserves the user
  row version. Smoke-test one feed/profile read and confirm it performs no
  maintenance RPC, then share or comment once and confirm the public author
  projection is current. During ghost-merge QA, verify scans and Explore posts
  move to the target account before the identity refresh and ghost purge.
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
- Inspect Cloudflare R2 lifecycle rules against `docs/r2-lifecycle.json` and
  confirm there is no enabled expiration rule for `avatars/`.
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
  widgets omit audio-only posts, and moderation logs contain no transcript or URL.
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
  classification. Replace the bytes and confirm a new decision is created.
  Query the attestation table as service role and verify it contains only
  checksum, policy/model, decision, MIME type, byte size, and timestamp.
- On a disposable legacy audio scan with a surviving local file, share once and
  confirm staging promotion populates `audio_storage_urls`, replaces the local
  `captured_media` audio reference, creates a ready normalized audio asset, and
  moderates before publication. Repeat with the local file unavailable and
  confirm no empty or phantom public post is created.
- Delete one disposable audio scan and purge one expired non-biological audio
  scan; confirm their source recordings and derived spectrogram objects
  disappear before their database rows do.
- Submit or replay a short video scan and verify Edge logs do not show
  `Payload Too Large` for the normal six-file manifest or
  `scan_media_assets` nullability errors during staged row creation.
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
