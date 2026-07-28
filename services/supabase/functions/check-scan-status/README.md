# check-scan-status

Confirms whether an authenticated user's scan row exists in `public.scans`. iOS
uses this as the outbox probe before retrying a background inference request
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

For a single owner scan that completed locally but is missing from
`public.scans`, iOS may also send a validated `recovery_scan` object before
opening Field Chat or retrying an Explore or Ask the Community action:

```json
{
  "scan_id": "uuid",
  "recovery_scan": {
    "id": "same-scan-uuid",
    "user_id": "authenticated-user-uuid",
    "species_id": "uuid-or-null",
    "confirmed_species_id": null,
    "image_storage_urls": [],
    "timestamp": "2026-07-27T18:00:00Z",
    "geoprivacy": "private",
    "ai_confidence_score": 0.94,
    "ecology_type": "wild",
    "is_invasive": false,
    "is_live_capture": true,
    "is_biological_subject": true,
    "inference_tier": "flash",
    "user_confirmed_identification": false,
    "user_review_state": "unreviewed"
  }
}
```

The full object includes the optional observation fields accepted by
`_shared/scanRecovery.ts`. Direct media URLs are rejected; Explore restores
media separately through validated owner staging keys. Recovery is deliberately
unavailable in bulk probes. iOS polls the ingestion ledger first and defers
repair while the original job is processing, finalizing, retrying, or still
eligible for retry so a minimal recovery row cannot race the richer insert.
The server independently enforces the same guard and refuses recovery after
known terminal moderation or provider safety-policy rejection, so correctness
does not depend on client behavior.

Bulk probes use the same fields per scan and are capped at 50 entries:

```json
{
  "scans": [
    { "scan_id": "uuid-1", "required_video_count": 1 },
    { "scan_id": "uuid-2" }
  ]
}
```

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

Bulk responses include the probed scan id on each result:

```json
{
  "results": [
    {
      "scan_id": "uuid-1",
      "status": "found",
      "job_status": null,
      "job_stage": null,
      "job_attempt_count": null,
      "retry_after": null,
      "last_error": null
    }
  ]
}
```

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- `scan_id` must belong to the current user; ownership is enforced in the DB
  query and non-owned rows are indistinguishable from missing rows.
- A single request with `recovery_scan` may idempotently recreate an absent
  owner row. The route derives identity from the authenticated user, requires
  matching UUIDs, validates all fields, derives public coordinates from
  geoprivacy, and uses duplicate protection so it cannot overwrite an existing
  row. The shared repair write allows only legacy jobs with no ledger entry,
  completed-but-missing rows, and non-policy terminal failures; active,
  retryable, moderation-rejected, and provider-policy-rejected jobs remain
  untouched.
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
- Terminal replay exhaustion appears through those optional job fields as
  client-facing `job_status = "failed"` and
  `job_stage = "server_replay_limit_reached"`; the backing ledger row remains
  `failed_terminal`. iOS also accepts legacy `failed_terminal` response values
  and maps both forms to a user-visible needs-attention state rather than
  continuing local automatic retry.
- The response intentionally does not expose `media_object_keys`,
  `upload_session_ids`, `manifest_checksum`, `request_payload`, or
  `payload_checksum`; those remain server/operator diagnostics for tying retries
  and reconciliation back to the staged media set.
- Without `recovery_scan`, the endpoint is read-only.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-scan-status/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/_shared/scanRecovery_test.ts services/supabase/functions/check-scan-status/status_test.ts
```
