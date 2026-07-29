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
eligible for retry so a minimal recovery row cannot race the richer insert. The
server independently enforces the same guard and refuses recovery after known
terminal moderation or provider safety-policy rejection, so correctness does not
depend on client behavior.

When the exact owner scan is still absent after optional bounded row recovery,
the route also invokes service-only stranded-attempt reconciliation before it
reads the client-safe job state. This does not create a guessed row:

- an existing scan or deletion tombstone wins;
- a live lease and active/retryable richer ingestion win;
- an ordinary scanless committed provider attempt may be moved only to the exact
  quota-retry state proven by its matching reservation/job topology;
- a generation fenced as `identity_merge_interrupted` may resolve only to the
  target owner proven by the completed merge handoff;
- retired source staging is never accepted and may be converted only to a stable
  fresh-restage requirement; and
- endpoint, quota operation, owner, handoff, lease, or media ambiguity returns
  not applicable and leaves the generation closed.

The reconciliation outcome is intentionally not returned as a new public field.
The response exposes only the resulting owner-safe job state; iOS then uses its
normal status/backoff/fresh-upload policy.

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
  geoprivacy, and calls one per-scan-locked database routine so the row plus
  completed recovery ledger are atomic and cannot overwrite an existing row. The
  shared repair write requires an existing ledger and allows
  completed-but-missing or structured `replay_exhausted` state. Exact
  `media_reconciliation_abandoned` additionally requires matching composite
  dead-letter/quota/media-lifecycle proof. No-ledger, active, retryable,
  current/later policy, unproven abandonment, legacy-unknown, and arbitrary
  terminal reasons remain untouched. If the service-only proof/recovery routines
  are unavailable, stale in the Data API schema cache, or reject internally, the
  handler returns customer-safe `503 service_unavailable` before restore signing
  and leaves local media authoritative.
- The service-only proof call is a mandatory rollout-readiness fence before
  `recover_missing_owned_scan`, not an authorization shortcut. The baseline and
  hardening migrations are separate migration-file transactions, so this
  exact-SHA consumer predeploys before either file and cannot reach the
  intermediate recovery definition. An empty proof response is valid boundary
  readiness for completed or replay-exhausted repair; malformed, foreign,
  missing, or denied responses fail closed.
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
- Without `recovery_scan`, the endpoint never inserts or updates `public.scans`.
  A missing scan may still invoke the narrow service-only stranded-attempt
  reconciliation described above.
- The service-only stranded-attempt reconciliation may update only the exact
  scanless job/quota/staging state needed to make its existing retry path
  coherent. It never inserts a caller-supplied scan, refunds committed provider
  usage, reparents arbitrary rows, or returns the authorized source identity.

## Caller Behavior

- **Offline queue:** poll before replaying an ambiguous inference response. Keep
  `processing`, `finalizing`, and retry-eligible server generations under server
  ownership. A proven scanless durability/promotion retry clears consumed local
  staged keys and returns to signing; provider-only retry may reuse a
  still-valid staged manifest.
- **Field Chat:** preflight the exact owner scan before presenting
  `/insight-chat`. Eligible historical drift may use one bounded
  `recovery_scan`; transient not-ready state remains retryable and must not be
  cached as permanently unavailable.
- **Ask the Community:** repair the owner row here before separately staging
  eligible local image media.
- **Explore sharing:** ordinary publication probes status first, while
  `/share-scan-to-explore` can combine bounded non-media recovery with validated
  owner-staged image/audio/video restoration in one guarded request.

A current scan-producer `200` followed immediately by `not_found` is a severity
incident even if this endpoint can later repair the row.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-scan-status/index.ts
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/scanRecovery_test.ts \
  services/supabase/functions/_shared/scanIngestionJobs_test.ts \
  services/supabase/functions/check-scan-status/status_test.ts \
  services/supabase/functions/_tests/identityMergeScanRecoveryMigrationContract.test.ts
```

The joined queue, persistence, Field Chat, Explore, rollout, and security
contract is in
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
