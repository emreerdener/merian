# Supabase Deployment Runbook

Merian's long-term Supabase release path is GitHub Actions, not an interactive
developer shell. Local `supabase login` is useful for emergency maintenance, but
production deploys should be repeatable from CI with explicit secrets and
validation.

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

The workflow performs the following steps:

1. Writes the workflow context summary.
2. Installs Deno 2, matching `services/supabase/config.toml`.
3. Installs the Supabase CLI.
4. Fails fast if required deployment secrets are missing.
5. Validates Edge Function formatting, lint, type checks, and focused shared
   helper tests.
6. Validates static Supabase migration contracts, including media-schema drift
   repair required before production `db push`.
7. Prepares a Postgres connection string for database migrations without
   calling `supabase link`. The workflow prefers a full `SUPABASE_DB_URL`, but
   can also construct a session-pooler URL from `SUPABASE_DB_POOLER_HOST` plus
   `SUPABASE_DB_PASSWORD`.
8. Pushes database migrations with `supabase db push --db-url`.
9. Deploys all Edge Function directories with `supabase functions deploy`.
10. Smoke-tests the Community Taxonomy status endpoint, the scan-media health
   endpoint, and a dry-run bounded GBIF import with the production service-role
   credential.

Actual GBIF taxonomy imports are intentionally separated into
`.github/workflows/import-community-taxonomy.yml`. The deploy workflow only
smoke-tests a dry run; it does not write taxonomy rows or advance import
cursors.

Deploying all function directories is intentional. Shared modules such as
`functions/_shared/aws.ts`, `functions/_shared/mediaBudgets.ts`, and
`functions/_shared/concurrency.ts` are bundled into each dependent Edge Function
at deploy time; deploying a hand-maintained partial list risks leaving
production on mixed helper versions.

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

Field Trips releases are migration-plus-function releases too. Deploy
`20260708021110_field_trips_v1.sql` before
`20260708033451_field_trips_v2.sql` before
`20260708042713_field_trips_v3_community.sql` before
`20260708051414_field_trips_v4_challenges.sql`, then deploy the `field-trips`
Edge Function and the updated Explore/profile activity bundles together. V1
creates the Field Trip tables, progress/publication/comment storage, profile
visibility helpers, and publication snapshots. V2 adds guided template detail,
explicit starts, Recent compatibility pagination, and profile pins. V3 adds
the Community publication RPC, Field Trip in-app activity storage, and Explore
activity union/read/count RPC updates. V4 adds curated seasonal challenge
storage, explicit joins, challenge-specific item completions, completion badges,
challenge entry snapshots, challenge entry comments/likes, and scan-scoped
hashtag suggestion helpers. A function-only deploy cannot serve V4 actions
until all migrations are applied; a database-only deploy leaves the app without
the Field Trips action router.

Each deployed function directory must also have a `[functions.<name>]` entry in
`services/supabase/config.toml` so JWT behavior is explicit. Most
anonymous-compatible app routes set `verify_jwt = false` and then perform manual
auth inside Deno; the known authenticated-only exceptions are documented in
`docs/backend-and-data/02-supabase-edge-and-database.md`.

The deploy command relies on `services/supabase/functions/deno.json`, which the
current Supabase CLI discovers during function graph creation. Do not pass the
old `--import-map` flag; newer Supabase CLIs reject that flag during deploy. The
Deno config keeps dependency resolution stable while Supabase builds each
function graph: historical `https://esm.sh/@supabase/supabase-js@2.49.1` imports
are remapped to the npm package, and runtime dependencies such as `aws4fetch`
and `jszip` also resolve through npm instead of esm.sh. Edge entrypoints should
use `Deno.serve(...)` directly rather than importing `serve` from Deno std.
Shared runtime helpers should prefer local utilities such as
`_shared/encoding.ts` for base64/hex helpers so production deploys do not fail
when deno.land or esm.sh returns a transient 5xx during bundling.

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
- `explore_video_missing_thumbnail`: inspect `explore_post_media.thumbnail_url`
  and the source scan's first safe image/poster thumbnail.
- `latest_reconciliation_run_not_clean`: inspect
  `scan_media_reconciliation_runs.errors` before rerunning the worker.

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
  services/supabase/functions/_shared/aws.ts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/mediaBudgets.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/_shared/encoding.ts \
  services/supabase/functions/_shared/concurrency.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility_test.ts \
  services/supabase/functions/_tests/scanMediaIngestionContract.test.ts \
  services/supabase/functions/_tests/migrationMediaContract.test.ts \
  services/supabase/scripts/monitor_scan_media_health.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/generate-upload-urls/index.ts \
  services/supabase/functions/generate-upload-urls/storage_test.ts \
  services/supabase/functions/update-public-avatar/index.ts \
  services/supabase/functions/update-public-display-name/index.ts \
  services/supabase/functions/insight-chat/index.ts \
  services/supabase/functions/scan-media-health/index.ts \
  services/supabase/functions/auto-purge-nonbio/index.ts \
  services/supabase/functions/delete-scan/index.ts \
  services/supabase/functions/replay-scan-ingestion/index.ts

deno test --config services/supabase/functions/deno.json \
  --allow-read=docs/contracts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/_shared/scanIngestionCompatibility_test.ts \
  services/supabase/functions/_tests/scanMediaIngestionContract.test.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/update-public-avatar/avatar_test.ts \
  services/supabase/functions/_tests/updatePublicDisplayName.test.ts \
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

## Post-Deploy Smoke Checks

After deployment:

- Confirm `supabase db push` applied the newest migration.
- For Field Trips releases, confirm `field-trips` serves `catalog`,
  `template_detail`, `start`, `community_publications`, `recent_publications`,
  `challenges_catalog`, `challenge_detail`, `join_challenge`,
  `challenge_publications`, `scan_challenge_hashtags`, and
  `profile_summaries` after the V1, V2, V3, and V4 migrations. Publishing a
  Field Trip or challenge entry must not write `explore_posts`, map points,
  normal Explore post notification rows, APNs, widgets, public web share pages,
  prize rows, or leaderboard rows. Field Trip comment/reply/followed-publication
  activity may appear in `field_trip_activity_notifications` and the in-app
  Explore activity feed.
- For video-upload contract releases, confirm `scan_media_assets.scan_id` and
  `scan_media_assets.url` are nullable in production
  (`information_schema.columns.is_nullable = YES`) before expecting six-file
  video signing to work.
- Confirm `auto-purge-nonbio` and `delete-scan` were deployed after any
  `_shared/aws.ts` change.
- For public Explore audio, confirm both audio migrations are applied,
  `GEMINI_API_KEY` exists as an Edge secret, and `identify-multimodal`,
  `share-scan-to-explore`, `delete-scan`, `auto-purge-nonbio`, and
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
  scan; confirm their R2 objects disappear before their database rows do.
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
