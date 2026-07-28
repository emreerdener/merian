# `reconcile-scan-media-assets`

Service-role worker for staged scan-media upload-session reconciliation.

## Responsibilities

- Scans stale `scan_media_assets` rows where `source = 'capture_upload'` and
  `status = 'staged'`.
- If the cloud scan row already exists, repairs safe media drift:
  - image rows are marked promoted when the scan already has the matching public
    image URL.
  - standalone audio rows are marked promoted when `scans.audio_storage_urls`
    has the matching public URL; only extracted video-companion audio is deleted
    as an inference-only input.
  - playback video rows are promoted from `staging/` to `public_uploads/` when
    the staged object still exists, then `scans.video_storage_urls` and
    `scans.captured_media` are rebuilt so sampled frames collapse behind one
    playable video item. Rebuilt ready playback rows mark `has_audio` only when
    the captured-media video item has an audio reference.
- If no scan row exists after the abandonment TTL, deletes any remaining staging
  object and marks the asset failed for audit.
- Checks `scan_ingestion_jobs` before abandoning orphaned staged media: active
  leases and future `retry_after` windows keep media pending, repaired scans can
  mark their job complete only through the shared claimed-key/canonical-media
  finalization transaction, and TTL-abandoned media marks the job
  `failed_terminal`.
- Writes summary rows to `scan_media_reconciliation_runs` and logs structured
  completion counts.

## Invocation

The function is scheduled hourly by
`20260705110000_schedule_scan_media_asset_reconciliation.sql` through `pg_cron`
/ `pg_net`. It uses `verify_jwt = false` at the gateway, then requires an exact
platform-managed current or legacy server key inside the function. The
scheduling migration also repairs early `scan_media_assets` table shapes before
creating the staged capture-upload index, so remote databases that already
applied an older media-assets migration can deploy the worker safely.

Optional POST body:

```json
{
  "limit": 100,
  "repairAfterMinutes": 15,
  "abandonAfterHours": 36,
  "dryRun": false
}
```

The worker deliberately does not replay AI inference. It only finalizes existing
scan rows, updates the ingestion-job ledger around media repair/abandonment, or
cleans abandoned staging artifacts. Sanitized `scan_ingestion_intents` rows give
`replay-scan-ingestion` the accepted staged media/audio/video or text-only
request shape; this worker does not consume those intents. Inline/redacted scans
still depend on the iOS offline queue, while resumable staged media/audio/video
and text-only scans are retried by `replay-scan-ingestion`.

## Uniqueness invariant

Generated `scan_refresh`/`backfill` rows and promoted `capture_upload` lifecycle
rows are separate records and may legitimately share a scan `order_index`.
Migration `20260720230648_repair_scan_media_asset_uniqueness.sql` removes the
legacy global `UNIQUE (scan_id, order_index)` rule and replaces it with:

- source-aware generated uniqueness on `(scan_id, source, role, order_index)`
  for `scan_refresh` and `backfill`;
- staged-session uniqueness on `(upload_session_id, order_index)` when an upload
  session is present;
- active staging-key uniqueness on `(user_id, client_scan_id, storage_key)` for
  `capture_upload / staged` rows. Upload-signing retries reuse the canonical
  row/session; the forward repair keeps preexisting extras as explicitly
  superseded failed audit rows.

If consecutive reconciliation runs report PostgreSQL `23505` errors naming
`scan_media_assets_scan_id_order_index_key`, deploy that migration before
rerunning the worker. Start with `dryRun: true`; proceed with a live invocation
only when the dry run reports the expected candidate count and zero errors.
