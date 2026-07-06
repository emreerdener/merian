# `scan-media-health`

Service-role health endpoint for scan media durability.

## Responsibilities

- Reports stuck `scan_ingestion_jobs` that are still processing/finalizing past
  their lease window or have retryable failures past `retry_after`; operators
  can inspect the job's `manifest_checksum` and `upload_session_ids` to match
  the stuck attempt back to staged scan media.
- Reports in-flight/retryable ingestion jobs that are missing
  `scan_ingestion_intents` rows or whose intents are non-resumable because
  inline media bytes were intentionally redacted.
- Reports stale `scan_media_assets` capture-upload rows, failed media assets,
  and recent video scans whose durable media surfaces disagree.
- Detects recent video-specific drift such as `video_storage_urls` without a
  video item in `captured_media`, missing ready playback `scan_media_assets`, or
  frame-only video-smell rows.
- Reports Explore video media rows that are missing poster thumbnails.
- Includes the latest reconciliation run status so operators can tell whether
  the repair worker is healthy.

The endpoint is read-only. It does not repair media or replay inference. Repairs
stay owned by `identify-multimodal`, `replay-scan-ingestion`, the iOS offline
queue, and `reconcile-scan-media-assets`.

## Invocation

`verify_jwt = false` is configured so service-role automation can reach Deno,
then the function requires `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`
or an equivalent service-role `apikey`.

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
or `fail_on = never` when collecting a non-gating diagnostic snapshot.

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
