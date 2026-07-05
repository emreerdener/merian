# `reconcile-scan-media-assets`

Service-role worker for staged scan-media upload-session reconciliation.

## Responsibilities

- Scans stale `scan_media_assets` rows where `source = 'capture_upload'` and
  `status = 'staged'`.
- If the cloud scan row already exists, repairs safe media drift:
  - image rows are marked promoted when the scan already has the matching public
    image URL.
  - audio rows are deleted because they are inference-only staging inputs.
  - playback video rows are promoted from `staging/` to `public_uploads/` when
    the staged object still exists, then `scans.video_storage_urls` and
    `scans.captured_media` are rebuilt so sampled frames collapse behind one
    playable video item.
- If no scan row exists after the abandonment TTL, deletes any remaining staging
  object and marks the asset failed for audit.
- Writes summary rows to `scan_media_reconciliation_runs` and logs structured
  completion counts.

## Invocation

The function is scheduled hourly by
`20260705110000_schedule_scan_media_asset_reconciliation.sql` through
`pg_cron` / `pg_net`. It uses `verify_jwt = false` at the gateway, then requires
`Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` inside the function.

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
scan rows or cleans abandoned staging artifacts; the iOS offline queue remains
the source of truth for retrying scans that never reached inference.
