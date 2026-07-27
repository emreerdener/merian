# `scan-media-health`

Service-role health endpoint for scan media durability.

## Responsibilities

- Reports stuck `scan_ingestion_jobs` that are still processing/finalizing past
  their lease window or have retryable failures past `retry_after`; operators
  can inspect the job's `manifest_checksum` and `upload_session_ids` to match
  the stuck attempt back to staged scan media.
- Surfaces replay exhaustion as terminal ingestion state: server replay is
  capped at 10 claims per sanitized intent and over-budget jobs are marked
  `server_replay_limit_reached`.
- Reports in-flight/retryable ingestion jobs that are missing
  `scan_ingestion_intents` rows or whose intents are non-resumable because
  inline media bytes were intentionally redacted.
- Reports stale `scan_media_assets` capture-upload rows, failed media assets,
  and recent video/audio scans whose durable media surfaces disagree.
- Detects recent video-specific drift such as `video_storage_urls` without a
  video item in `captured_media`, missing ready playback `scan_media_assets`, or
  frame-only video-smell rows.
- Reports Explore video media rows that are missing poster thumbnails.
- Reports durable audio missing its captured-media manifest or ready normalized
  asset, plus public Explore audio rows without playable URLs.
- Includes the latest reconciliation run status so operators can tell whether
  the repair worker is healthy.

The endpoint is read-only. It does not repair media or replay inference. Repairs
stay owned by `identify-multimodal`, `replay-scan-ingestion`, the iOS offline
queue, and `reconcile-scan-media-assets`.

For `audio_scan_missing_ready_audio_asset`, first confirm
`20260711171512_backfill_missing_ready_audio_assets.sql` is deployed. That
migration extends the canonical `refresh_scan_media_assets(...)` RPC to rebuild
standalone audio and backfills scans with durable `audio_storage_urls`. Rerun
the monitor after deployment. Do not delete or replace the R2 recording to
repair a missing normalized row.

## Invocation

`verify_jwt = false` is configured so service-role automation can reach Deno,
then the function requires either the legacy service-role JWT in matching
`apikey` and Bearer headers, or an exact named `sb_secret_...` project secret in
`apikey` only. Values are compared against the platform environment; no
database/RLS capability probe is allowed, and mixed credentials fail closed.
Database access uses the server-managed environment key rather than the caller
value.

Optional POST body:

```json
{
  "limit": 25,
  "stuckAfterMinutes": 20,
  "staleAssetAfterMinutes": 15,
  "recentScanLimit": 250
}
```

Response:

```json
{
  "success": true,
  "generated_at": "2026-07-05T15:00:00.000Z",
  "status": "warning",
  "counts": {
    "issues": 1,
    "critical_issues": 0,
    "warning_issues": 1
  },
  "asset_breakdown": {
    "stale_capture_upload_assets": [
      { "kind": "image", "role": "display", "count": 1 }
    ],
    "failed_assets": []
  },
  "issues": [
    {
      "code": "stale_capture_upload_assets",
      "severity": "warning",
      "count": 1,
      "sample": []
    }
  ]
}
```

`status = critical` means a video/share durability invariant is broken or an
active ingestion job is stuck past its lease. `status = warning` means
repair/retry work may still succeed, or a terminal ingestion failure may need
review if unexpected.

## Scheduled Monitor

`.github/workflows/scan-media-health-monitor.yml` calls this endpoint every 30
minutes with `fail_on = critical`. The workflow writes JSON and Markdown
artifacts for each run and appends the Markdown summary to the GitHub job
summary. The summary includes an **Incident Actions** table with an owner,
next-step, runbook, and sample-field hint for each issue code, so a critical run
is immediately actionable without opening the endpoint source. It also renders a
visible **Sample Preview** table with the first sample row for each issue code;
download the JSON artifact or expand the per-issue sample blocks for the full
sample set. Manual dispatch can use `fail_on = warning` for stricter validation
or `fail_on = never` when collecting a non-gating diagnostic snapshot. Read-only
calls retry bounded transient network, routing, propagation, rate-limit, and
server failures up to six attempts. A final failure exposes only the numeric
status, bounded SDK failure class, and fixed handler-marker presence; it cancels
and withholds the operational body and never prints a request ID or credential.

## Validation

```bash
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/scan-media-health/health_test.ts
deno check --config services/supabase/functions/deno.json \
  services/supabase/functions/scan-media-health/index.ts
deno test --config services/supabase/functions/deno.json \
  services/supabase/scripts/monitor_scan_media_health_test.ts
deno test --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/migrationMediaContract.test.ts
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_tests/scanMediaIngestionContract.test.ts
```
