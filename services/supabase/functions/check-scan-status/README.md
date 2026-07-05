# check-scan-status

Confirms whether an authenticated user's scan row exists in `public.scans`.
iOS uses this as the outbox probe before retrying a background inference request
whose response body may have been lost after the server committed the scan.

## Request

```json
{
  "scan_id": "uuid",
  "required_video_count": 1
}
```

`required_video_count` is optional. Image-only and legacy probes should omit it
or send `0`. Video replay recovery sends the number of video items in the queued
captured-media timeline.

## Response

```json
{
  "status": "found",
  "job_status": null,
  "job_stage": null,
  "job_attempt_count": null,
  "retry_after": null,
  "last_error": null
}
```

or:

```json
{
  "status": "not_found",
  "job_status": "finalizing",
  "job_stage": "video_promotion_started",
  "job_attempt_count": 1,
  "retry_after": null,
  "last_error": null
}
```

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- `scan_id` must belong to the current user; ownership is enforced in the DB
  query and non-owned rows are indistinguishable from missing rows.
- When `required_video_count > 0`, the endpoint returns `found` only if the scan
  row has at least that many non-empty `video_storage_urls` and at least that
  many ready playback entries in `scan_media_assets` or video entries in
  `captured_media`.
- This prevents the offline queue from treating a legacy frame-only cloud row as
  a completed video scan. If the durable playback `.mp4` is missing, the queue
  retries instead of deleting the local video.
- `status` remains compatibility-only (`found` or `not_found`). When the scan
  row is not yet complete, optional job fields come from `scan_ingestion_jobs`
  and expose owner-safe processing/finalization/retry state.
- The endpoint is read-only.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-scan-status/index.ts
```
