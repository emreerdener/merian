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

The workflow performs the following steps:

1. Installs Deno 2, matching `services/supabase/config.toml`.
2. Installs the Supabase CLI.
3. Fails fast if required deployment secrets are missing.
4. Validates Edge Function formatting, lint, type checks, and focused shared
   helper tests.
5. Validates static Supabase migration contracts, including media-schema drift
   repair required before production `db push`.
6. Prepares a Postgres connection string for database migrations without
   calling `supabase link`. The workflow prefers a full `SUPABASE_DB_URL`, but
   can also construct a session-pooler URL from `SUPABASE_DB_POOLER_HOST` plus
   `SUPABASE_DB_PASSWORD`.
7. Pushes database migrations with `supabase db push --db-url`.
8. Deploys all Edge Function directories with `supabase functions deploy`.
9. Smoke-tests the Community Taxonomy status endpoint, the scan-media health
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

Media-upload contract changes are migration-plus-function releases. For example,
the video staging contract that allows five sampled inference frames plus one
playback clip requires the `scan_media_assets.scan_id` nullable repair migration
to be pushed before the updated `/generate-upload-urls` bundle handles six-file
signing requests in production. A database-only deploy leaves clients on the old
signing cap; a function-only deploy can still fail staged row creation if an
early production table kept `scan_id NOT NULL`.

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
  the iOS queue. For a manual service-role retry, POST
  `{ "limit": 5, "awaitInvocations": true }` to
  `/functions/v1/replay-scan-ingestion`.
- `video_scan_missing_captured_media_video`: inspect the scan's
  `video_storage_urls`, `captured_media`, and ready playback
  `scan_media_assets`; repair should go through `reconcile-scan-media-assets` or
  the local `.mp4` restore path.
- `video_scan_missing_ready_playback_asset`: run or inspect
  `refresh_scan_media_assets(scan_id)` and the reconciliation worker result.
- `explore_video_missing_thumbnail`: inspect `explore_post_media.thumbnail_url`
  and the source scan's first safe image/poster thumbnail.
- `latest_reconciliation_run_not_clean`: inspect
  `scan_media_reconciliation_runs.errors` before rerunning the worker.

Manual dispatch can use `fail_on = warning` for stricter validation before a
media-path release, or `fail_on = never` to collect a non-gating diagnostic
snapshot.

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
- For video-upload contract releases, confirm `scan_media_assets.scan_id` is
  nullable in production (`information_schema.columns.is_nullable = YES`) before
  expecting six-file video signing to work.
- Confirm `auto-purge-nonbio` and `delete-scan` were deployed after any
  `_shared/aws.ts` change.
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
- Submit or replay a short video scan and verify Edge logs do not show
  `Payload Too Large` for the normal six-file manifest or
  `scan_media_assets.scan_id` nullability errors during staged row creation.
- Confirm `sync-community-taxonomy-index` accepts a tiny `dry_run = true` Birds
  request without advancing `taxonomy_coverage_targets.next_import_offset`.
- Smoke-test `/insight-chat` with `action: "load"` and
  `action:
  "suggest_prompts"` against an owned completed biological scan.
