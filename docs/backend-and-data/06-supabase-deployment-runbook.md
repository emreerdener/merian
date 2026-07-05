# Supabase Deployment Runbook

Merian's long-term Supabase release path is GitHub Actions, not an
interactive developer shell. Local `supabase login` is useful for emergency
maintenance, but production deploys should be repeatable from CI with explicit
secrets and validation.

## Production Path

Pushes to `main` and manual `workflow_dispatch` runs execute
`.github/workflows/deploy.yml`.

The workflow performs the following steps:

1. Installs Deno 2, matching `services/supabase/config.toml`.
2. Installs the Supabase CLI.
3. Fails fast if required deployment secrets are missing.
4. Validates Edge Function formatting, lint, type checks, and focused shared
   helper tests.
5. Validates static Supabase migration contracts, including media-schema drift
   repair required before production `db push`.
6. Links the Supabase project.
7. Pushes database migrations.
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
`functions/_shared/concurrency.ts` are bundled into each dependent Edge
Function at deploy time; deploying a hand-maintained partial list risks leaving
production on mixed helper versions.

Each deployed function directory must also have a `[functions.<name>]` entry in
`services/supabase/config.toml` so JWT behavior is explicit. Most
anonymous-compatible app routes set `verify_jwt = false` and then perform
manual auth inside Deno; the known authenticated-only exceptions are documented
in `docs/backend-and-data/02-supabase-edge-and-database.md`.

The deploy command relies on `services/supabase/functions/deno.json`, which the
current Supabase CLI discovers during function graph creation. Do not pass the
old `--import-map` flag; newer Supabase CLIs reject that flag during deploy.
The Deno config keeps dependency resolution stable while Supabase builds each
function graph: historical `https://esm.sh/@supabase/supabase-js@2.49.1`
imports are remapped to the npm package, and runtime dependencies such as
`aws4fetch` and `jszip` also resolve through npm instead of esm.sh. Edge
entrypoints should use `Deno.serve(...)` directly rather than importing `serve`
from Deno std. Shared runtime helpers should prefer local utilities such as
`_shared/encoding.ts` for base64/hex helpers so production deploys do not fail
when deno.land or esm.sh returns a transient 5xx during bundling.

## Required GitHub Secrets

Set these in the repository's GitHub Actions secrets:

- `SUPABASE_ACCESS_TOKEN` — Supabase CLI access token for the deployment actor.
- `SUPABASE_DB_PASSWORD` — database password used by `supabase link` and
  `supabase db push`.

The production Supabase project ref is intentionally stored in the workflow as
`qlarqavoqhkuwzmevrmf`. Project refs are routing identifiers, not credentials;
the deployment authority still comes from `SUPABASE_ACCESS_TOKEN` and
`SUPABASE_DB_PASSWORD`. Post-deploy smoke checks and manual taxonomy imports
resolve the service-role key at runtime through
`supabase projects api-keys --project-ref qlarqavoqhkuwzmevrmf`, then mask it in
GitHub Actions logs.

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
summary.

Scheduled runs use:

- `limit`: `25`
- `recent_scan_limit`: `250`
- `fail_on`: `critical`

Warnings are visible in the summary but do not fail the scheduled run. A failed
run means the endpoint returned `critical` or the monitor could not reach the
service-role endpoint. Start triage from the issue code:

- `stuck_ingestion_jobs`: inspect `scan_ingestion_jobs.stage`,
  `lock_expires_at`, `retry_after`, `manifest_checksum`, `upload_session_ids`,
  and `last_error`; retryable rows should be retried by the client/server queue,
  while expired active rows may need operator replay. If the stuck job still has
  staged `scan_media_assets`, `reconcile-scan-media-assets` will keep those
  rows pending while the lease or retry window is active, mark the job complete
  after a successful media repair, or mark it `failed_terminal` after the
  abandonment TTL.
- `video_scan_missing_captured_media_video`: inspect the scan's
  `video_storage_urls`, `captured_media`, and ready playback
  `scan_media_assets`; repair should go through `reconcile-scan-media-assets`
  or the local `.mp4` restore path.
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
  services/supabase/functions/_shared/encoding.ts \
  services/supabase/functions/_shared/concurrency.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/scripts/monitor_scan_media_health.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/update-public-avatar/index.ts \
  services/supabase/functions/update-public-display-name/index.ts \
  services/supabase/functions/insight-chat/index.ts \
  services/supabase/functions/scan-media-health/index.ts \
  services/supabase/functions/auto-purge-nonbio/index.ts \
  services/supabase/functions/delete-scan/index.ts

deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/scripts/monitor_scan_media_health_test.ts \
  services/supabase/functions/update-public-avatar/avatar_test.ts \
  services/supabase/functions/_tests/updatePublicDisplayName.test.ts \
  services/supabase/functions/insight-chat/guards_test.ts \
  services/supabase/functions/insight-chat/prompt_test.ts \
  services/supabase/functions/scan-media-health/health_test.ts

make validate-supabase-migrations
make db-push
make functions-deploy
```

If `make db-push` reports a missing access token, authenticate the local CLI:

```bash
supabase login
```

For non-interactive local environments, export `SUPABASE_ACCESS_TOKEN` and
`SUPABASE_DB_PASSWORD` instead of relying on a browser login or password prompt.

## Post-Deploy Smoke Checks

After deployment:

- Confirm `supabase db push` applied the newest migration.
- Confirm `auto-purge-nonbio` and `delete-scan` were deployed after any
  `_shared/aws.ts` change.
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
- Confirm `sync-community-taxonomy-index` accepts a tiny `dry_run = true` Birds
  request without advancing `taxonomy_coverage_targets.next_import_offset`.
- Smoke-test `/insight-chat` with `action: "load"` and `action:
  "suggest_prompts"` against an owned completed biological scan.
