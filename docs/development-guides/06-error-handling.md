# Error Handling Patterns

This document explains the unified `MerianError` taxonomy, how offline fallback
works at the network boundary, and how errors surface to the UI.

---

## `MerianError` Taxonomy

`MerianError` conforms to `LocalizedError` and acts as the singular error
boundary for the entire application, bridging HTTP limits, missing hardware, and
SwiftUI catch blocks.

```swift
public enum MerianError: LocalizedError, Equatable {
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
    case httpError(statusCode: Int, message: String)
    case networkTimeout
    case proRequiredForOfflineTracking
    case hardwareUnavailable
}
```

| Case                            | Meaning                                                  | Caller contract                                                                                                 |
| ------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `invalidURL`                    | URL construction failed (programming error)              | Log and abort. Do not retry.                                                                                    |
| `uploadFailed`                  | R2 `PUT` returned non-200.                               | Retain in queue for recoverable codes (429, 5xx). Tombstone for auth failures (401, 403).                       |
| `invalidResponse`               | HTTP error or auth failure from Edge.                    | For sync deletions: treat as terminal. For other callers: log and surface a UI error or route to offline queue. |
| `decodingFailed`                | `JSONDecoder` failed on a network response.              | Surface "Analysis Failed" graceful degradation result in `InsightSheet`; queued retry keeps the consumed scan.  |
| `networkTimeout`                | The network request timed out aggressively.              | Surface a "Network timeout" retry placeholder + scan queued silently                                            |
| `proRequiredForOfflineTracking` | Free user failed inference with no network               | Refund scan token, post `TriggerPaywall` notification. Never enqueue offline.                                   |
| `hardwareUnavailable`           | LiDAR or other required physical drivers failed to boot. | Show UI alert explaining hardware constraints.                                                                  |

---

## Inference Error Routing

`InferenceEngine.analyze` handles errors in this priority order:

1. **`CancellationError`** (or `URLError.cancelled`) — inference was cancelled
   (user navigated away or backgrounded). Do not refund the scan token. Do not
   surface any UI. The scan is already durably enqueued in the offline queue
   (written to disk synchronously in `submitActiveScan` before `analyze()` was
   called) and will complete via the background URLSession path.
   Authenticated/public transport, `5xx`, route-propagation, and guest-session
   retry sleeps must propagate this cancellation before issuing another request;
   never use `try?` around those sleeps.
2. **`MerianError.decodingFailed`** — Gemini returned a malformed or unreadable
   response. Do **not** refund the token — the scan is already in the offline
   queue and will be retried by the background upload path. Refunding here would
   give the user a free extra scan against a quota already consumed. Set
   `speciesData` to an "Analysis Failed" placeholder
   (`commonName: "Analysis Failed"`, `scientificName: "Data Unreadable"`). Show
   InsightSheet with degraded result.
3. **All other errors (network failure, timeout, etc.)** — Record circuit
   failure via `CircuitBreakerManager.shared.recordFailure()`. Set `speciesData`
   to a "Network timeout" placeholder with automatic-retry recovery copy. Do not
   refund and do not re-enqueue — the scan is already in the offline queue and
   will be retried by the background upload path. This placeholder is not a
   non-biological model classification even though it suppresses the biological
   result UI, so it must not show the non-biological badge, collection copy, or
   retention warning.

---

## Offline Fallback Pattern

When a network call fails in `OfflineQueueManager`, the error classification
determines queue behavior:

```
Upload (background URLSession upload task)
    ├── generateUploadURLs failure → reset .uploading scans to .pending and persist queueNextRetryAt until retry budget ends
    ├── File missing (NSURLErrorFileDoesNotExist / CannotOpenFile)
    │   └── mark queueNeedsAttention; keep local row for retry/cancel
    ├── Transient connectivity error (TimedOut / NetworkConnectionLost /
    │   NotConnectedToInternet / DataNotAllowed / InternationalRoamingOff)
    │   └── retain in queue with persisted queueNextRetryAt until retry budget ends
    ├── Other transport error → log, retain in queue with persisted retry metadata until retry budget ends
    ├── HTTP 200 → dispatch a generation-tagged background inference download task
    ├── HTTP 429 / 5xx → retain in queue (recoverable)
    ├── HTTP 401 / 403 → needs attention (auth failure, terminal)
    └── HTTP 4xx (other) → needs attention (terminal)

Inference (background URLSession download task)
    ├── Transport error → handleInferenceRetry: persist retry and reset to .staged until retry budget ends
    ├── HTTP 200 → processInferenceDownloadResult → persist LocalScanRecord, delete OfflineQueuedScan
    ├── Platform route 404 or handler 401 / 408 / 409 / 425 / 429
    │   └── handleInferenceRetry: preserve media, poll the ledger, and persist bounded retry
    ├── Exact observation_rejected → terminal policy outcome
    ├── Other handler 4xx → preserve media with queueNeedsAttention for retry/cancel
    └── HTTP 5xx → handleInferenceRetry: persist retry and reset to .staged until retry budget ends

Cloud deletion (PendingCloudDeletionTask)
    ├── MerianError.invalidResponse → tombstone (resource already gone, no point retrying)
    └── All other errors → retain as OfflineJobRecord waiting for nextRunAt until retry budget ends

Collection sync (OfflineJobRecord id "collection-sync")
    ├── HTTP 200 → mark complete and clear pending bridge bit
    └── Push failure → retain as OfflineJobRecord waiting for nextRunAt until retry budget ends
```

`queueNextRetryAt` is durable eligibility state, not evidence that a timer is
running. Every successful retry-date write must ask `OfflineJobScheduler` to
reselect its earliest wake. Foreground activation and connectivity restoration
must rebuild that wake from SwiftData because delayed Swift tasks do not survive
process termination and are cancelled on network loss. Queue UI must use live
relative copy (`Automatic retry in …`, `Automatic retry is starting`, or
`Retry when connection returns`) and refresh the value snapshot; a rounded clock
time alone is not a valid progress indicator.

Both uploads and inference use the same background `URLSession`
(`URLSessionConfiguration.background`) with `sessionSendsLaunchEvents = true`,
so iOS can re-attach in-flight tasks on app relaunch and deliver inference
results while the app is completely suspended. Current upload task descriptions
are `upload|{scanId}|{uploadIndex}|{syncGeneration}|{serverObjectKey}`. Current
inference task descriptions are `inference_v2|{inferenceGeneration}|{scanId}`.
Parsers continue to accept the earlier three- and four-part upload forms and
`inference_{scanId}` for in-flight tasks created by an older app version.

The generation in each current description is an ownership fence, not merely a
deduplication key. Delayed callbacks, retry timers, server-status probes, and
background-expiration handlers must still own that exact generation before they
clear manager state, cancel a URLSession task, delete a queued scan, or complete
a UI progress token. Cancellation remains cooperative, so task dictionaries also
use compare-before-clear registry tokens. Retry state itself lives in SwiftData
(`OfflineQueuedScan.queue*` plus `OfflineJobRecord`) rather than in process
memory.

Delayed status probes and server polls retain their registry token across
awaited status checks, URLSession cancellation, targeted recovery, and queue
state transitions. Every post-await mutation requires the same token and a
non-cancelled task. Do not clear a slot before starting its async action: doing
so permits a replacement to install itself while the old action is still able to
write.

---

## UI Error Surface Patterns

| Error scenario                                                                     | UI outcome                                                                                                                                                                                                                                                                                                                |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inference decoding failure (`MerianError.decodingFailed`)                          | InsightSheet opens with "Analysis Failed" / "Data Unreadable" placeholder result                                                                                                                                                                                                                                          |
| Network timeout (Pro user)                                                         | InsightSheet opens with a "Network timeout" placeholder, explains automatic retry/reconnect behavior, and suppresses non-biological collection/retention copy                                                                                                                                                             |
| Network timeout (Free user)                                                        | Paywall sheet presented via `TriggerPaywall` notification                                                                                                                                                                                                                                                                 |
| R2 upload failure (missing source file)                                            | Queued scan remains visible with needs-attention copy plus retry/cancel actions                                                                                                                                                                                                                                           |
| R2 upload transient failure                                                        | Queued scan remains saved locally with persisted next retry time                                                                                                                                                                                                                                                          |
| Durable scan-image URL returns R2/CDN 404 with no local match                      | Scan/post metadata remains; the image surface shows a retryable unavailable fallback. Do not label the record archived, hide it from owner history, or delete the relational row as a display fix.                                                                                                                        |
| Durable scan-image URL has a strongly matched local file                           | Render the local file immediately and enqueue owner-authenticated cloud inspection/repair while online; local visibility is not cloud-restoration confirmation.                                                                                                                                                           |
| Cloud scan-image repair fails                                                      | Preserve the local file and metadata, pause the process-local repair queue for 15 minutes, log a sanitized request-correlated failure, and retry after the dependency/deployment recovers.                                                                                                                                |
| Explore media receives one direct R2-origin 404                                    | Mark only `suspected_missing`; retain public projection and schedule a confirmation no earlier than five minutes later.                                                                                                                                                                                                   |
| Some Explore primary media is confirmed missing                                    | Omit confirmed-missing items, keep the post public as `degraded`, preserve engagement, and expose owner recovery state.                                                                                                                                                                                                   |
| All Explore primary media is confirmed missing                                     | Reversibly quarantine every public projection; preserve author publish state, row, likes, comments, reports, and recovery evidence.                                                                                                                                                                                       |
| Explore origin check times out or returns non-404 failure                          | Record a retryable result. Never turn transport, credentials, `5xx`, CDN, or client failure into confirmed loss.                                                                                                                                                                                                          |
| Supabase gateway returns platform `404 NOT_FOUND` with no Merian handler execution | Replay the unchanged authenticated request after bounded one-, two-, and four-second delays. If routing remains unavailable, throw the typed temporary-service error and show `Explore is temporarily unavailable. Please try again in a few minutes.` Never treat this as a missing scan or persist scan unavailability. |
| Explore share exposes internal service-role authorization text                     | Translate to `Explore is temporarily unavailable. Please try again in a few minutes.`                                                                                                                                                                                                                                     |
| Explore share cannot find an eligible owner row after recovery                     | Translate to `This observation is still syncing. Please wait a moment and try sharing again.`                                                                                                                                                                                                                             |
| Insight Field Chat owner row is still syncing                                      | Show `This observation is still syncing. Please try Field chat again in a moment.` and keep the action retryable                                                                                                                                                                                                          |
| SwiftData save failure during deletion                                             | `.error` logged; file deletion aborted; DB state remains consistent (record still exists, deletion task not persisted)                                                                                                                                                                                                    |
| SwiftData store corruption at startup                                              | Store artifacts are quarantined, a support manifest is written, store-aware persistent open is retried once, and the user sees "Library Repaired" if recovery succeeds                                                                                                                                                    |
| SwiftData schema migration failure at startup                                      | Legacy store artifacts are archived under `store-rescue/`, a fresh persistent current-schema store opens, and the user sees "Library Rebuilt" with `legacy_store_rescued` telemetry; safe mode is only used if rescue fails                                                                                               |
| Non-corruption `ModelContainer` startup failure                                    | Local store files are not moved; app boots in in-memory safe mode with a startup notice                                                                                                                                                                                                                                   |
| JWT expiry (authenticated OAuth user)                                              | `MerianError.invalidResponse` thrown; callers surface a re-auth prompt                                                                                                                                                                                                                                                    |
| Photos import blocked by quota                                                     | Existing paywall opens; the durable inbox receipt remains pending for an entitlement retry                                                                                                                                                                                                                                |
| Photos import blocked by capture capacity                                          | Capture shows "Finish your current capture to import the shared photo." and retains the receipt until staged media clears                                                                                                                                                                                                 |
| Photos import unsupported, missing, or unreadable                                  | Error haptic plus "Naturebook couldn’t import that photo."; any durable receipt is removed as terminal                                                                                                                                                                                                                    |

Photos document-import failures use `ExternalImageImportError` and capture
feedback rather than broadening `MerianError`, because they occur before a scan
or network request exists. Temporary quota/capacity states are not errors and
must not delete the Application Support inbox copy. See
`docs/features-and-hardware/26-photos-share-import.md`.

The platform `404` row above is deliberately narrower than HTTP status alone.
The response must omit `X-Merian-Handler: 1` and match Supabase's stable
`SB-Error-Code: NOT_FOUND` header, official missing-function envelope, or
gateway-without-execution headers. A marked handler-owned `404` is an
application response and must not be replayed by the route-propagation branch.
Background inference applies this classification before general `4xx` handling.
A platform route `404` preserves the queued scan for durable retry. Handler
`401`, `408`, `409`, `425`, and `429` responses are also retryable and honor a
bounded integer `Retry-After`. Other marked handler `4xx` responses retain local
media as `queueNeedsAttention`; only exact `observation_rejected` is terminal.

For a foreground scan, never label an arbitrary `409` as connectivity loss. Only
exact stable Identify codes `ai_request_in_progress`,
`ai_request_already_completed`, `scan_already_complete`, and
`scan_already_finalized` use the temporary **Restoring scan / Safely saved**
customer state and exact-ID background hydration. Current Edge functions should
normally absorb those cases by returning the completed envelope as marked
idempotent `200`; the client branch protects rolling deployments and unresolved
races. Generic conflicts and malformed payloads retain normal error handling.

The `store-rescue` archive in the startup rows above is a local SQLite support
copy. It does not set cloud scan state or call R2. See the
[July 2026 account-scoped R2 image-loss incident report](../incidents/2026-07-account-scoped-r2-image-loss.md)
for the distinct local-store and cloud-object failure boundaries.

Media-health state is server-owned. Image-loader callbacks must not write
`missing`, set `unshared_at`, remove engagement, or substitute reference art.
Verified repair or a later direct healthy check restores system quarantine
automatically, but it cannot override a later author unpublish or moderation
hide. See
[Explore Media Health and Quarantine](../backend-and-data/12-explore-media-health-and-quarantine.md).

---

## Durable Ingestion, Compatibility Dead Letters, and Owner Repair

The active `/identify-multimodal` route does not return `200 OK` until
moderation, required media promotion, primary species resolution, the
duplicate-safe scan write, and an owner-scoped read-back all succeed. A
constraint failure, database timeout, network partition, or other operational
finalization failure returns retryable `503 scan_persistence_failed` to that
fresh invocation; a later same-UUID marked replay may reconstruct from the exact
owner row while canonical repair continues, without another provider call. A
known terminal media-policy rejection returns customer-safe
`400 observation_rejected`. The client must not persist either error response as
a successful local observation.

The route claims `scan_ingestion_jobs` before AI inference and updates it
through `processing`, `finalizing`, `failed_retryable`, `failed_terminal`, and
`complete` states. `/check-scan-status` can therefore distinguish active,
retryable, terminal, complete, and genuinely absent work instead of reducing
every missing row to a bare `404`.

For eligible live-camera still-image analysis, request-body completion releases
the matching durable queue row for background upload. Transport failure,
connectivity loss, app backgrounding, and a two-second fail-safe release it too;
release is idempotent and never deletes the row. Only the established
live-success cleanup path adopts saved media, cancels duplicate tasks, and
removes the queue record. This keeps a failed or suspended foreground request
recoverable without allowing two uploads to contend from the start.

`/update-scan-context` may return `409` when the late WeatherKit/geocoding
result arrives before the ingestion claim. The live caller retries once after a
short delay and the local queued record retains the context for normal replay. A
409 must not trigger another identification request and must not discard the
scan.

Compatibility scan-producing endpoints (`identify`, `identify-describe`, and
`audio-spec`) now use the shared compatibility ledger to claim the same
job/intent rows before provider dispatch, then record final parsed output before
returning success; staged image/audio and text-only compatibility intents are
shaped for `/identify-multimodal` replay, while inline media is redacted and
remains client-retry only. Their required insertion/finalization task is
awaited. Failure before an exact owner row returns retryable
`503 scan_persistence_failed`, never provider-only HTTP success. If only
finalization or bookkeeping fails after exact owner-row commit, a compatibility
invocation may return its validated response while leaving the ledger
`failed_retryable` for same-UUID repair. A later marked replay may use that same
row without provider redispatch. The required failure path:

1. Logs a structured error via
   `logStructuredError("background_ingestion_failed", { scan_id, user_id, error })`.
2. Inserts a row into `public.failed_scan_ingestions` (dead-letter table) with
   the `scan_id`, `user_id`, and `error_message`.
3. If the dead-letter insert also fails, logs
   `logStructuredError("dead_letter_write_failed", ...)` and continues — the
   primary failure is already logged.
4. Preserves committed quota and promoted media when the write/read response is
   ambiguous; destructive cleanup occurs only after an exact owner read proves
   the scan absent.

**Ops replay**: Start with `scan_ingestion_jobs` for current state, attempt
count, stage, retryability, `upload_session_ids`, and `manifest_checksum`, then
inspect the paired `scan_ingestion_intents` row for `resumable`,
`payload_checksum`, `inline_media_redacted`, and the sanitized
`request_payload`. Query `failed_scan_ingestions` by `user_id` and `failed_at`
only as the older dead-letter fallback and detailed insert-failure history. The
scheduled `replay-scan-ingestion` worker claims staged media/audio/video and
text-only jobs with resumable intents and re-invokes `identify-multimodal` with
the same `client_scan_id` and media manifest; inline-media redacted jobs still
require the iOS queue to retry. Scan creation uses duplicate protection and then
reloads by both `id` and authenticated `user_id`; a raced insert, no-op
collision, or cross-owner UUID can never be reported as success without the
correct owner row. The compatibility `ERROR` status guard prevents inserting
scans where moderation itself failed, so only genuine insertion failures reach
the dead-letter table. Staged media that still belongs to an active lease or
future retry remains pending in `reconcile-scan-media-assets`; after TTL
abandonment the worker marks the job `failed_terminal` with the
`media_reconciliation_abandoned` stage so support can separate missing-media
terminal failures from retryable server failures.

### Owner-row recovery decision

Recovery is a compatibility repair for older/interrupted local-cloud drift; it
is not part of a normal current multimodal success.

| Server state                                                             | Recovery action                                                     |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| Owner row exists                                                         | Return `found`; do not write                                        |
| Job is processing, finalizing, retrying, or `failed_retryable`           | Defer to the richer ingestion attempt                               |
| Job is a known moderation or provider safety-policy rejection            | Refuse repair                                                       |
| No job / missing ledger                                                  | Defer; arbitrary local state is not recovery authority              |
| `complete` without a row                                                 | Allow duplicate-safe minimal owner-row repair, then reload by owner |
| `failed_terminal` with exact `terminal_reason_code = 'replay_exhausted'` | Allow duplicate-safe minimal owner-row repair, then reload by owner |
| Any other terminal or unknown reason                                     | Refuse repair; do not infer policy from error text                  |

Single `/check-scan-status` requests may include a bounded, non-media
`recovery_scan`; bulk status probes never insert or update `public.scans`, but a
missing probe may still invoke narrow service-only stranded-attempt
reconciliation for already-existing job/quota/staging state. Explore sharing may
combine the same object with staged image, video, or audio restoration and then
continues through normal eligibility and publication checks. Ask the Community
first repairs through `/check-scan-status`, then restores owner image media
through its existing endpoint. Field Chat also preflights the single status
contract before presentation. Direct media URLs, caller-selected ownership, and
client-side table upserts are not recovery paths. A transient still-syncing
result remains retryable and must not permanently hide Field Chat.

The complete error and recovery ordering contract is
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#error-semantics).

## Startup and Auth Failures Are Recoverable

- Apple Sign-In bootstrap failures are no longer fatal. Missing presentation
  anchors, missing callback nonces, and `SecRandomCopyBytes` failures now log
  and return control to the UI instead of terminating the app.
- `presentationAnchor(for:)` must always return a best-effort anchor. If no
  active key window exists yet, the flow cancels gracefully rather than crashing
  the scene.
- `ModelContainer` bootstrap failures now follow a recovery ladder: store-aware
  migration strategy selection → Objective-C exception bridge → duplicate
  checksum retry ladder → corruption detection → quarantine + store-aware retry
  → legacy migration rescue → in-memory safe mode with startup notice.
- Store recovery is local persistence repair only. It must not clear Keychain,
  Supabase sessions, device identity, profile state, or public Explore
  ownership. See `docs/backend-and-data/08-startup-store-recovery.md`.
- Remote export/download flows must reject invalid or non-allowlisted URLs
  before any network call. Use `URLComponents`, require `https`, and allow only
  exact approved hosts.

---

## Handling `401 Unauthorized`

`MerianNetworkClient.performAuthenticatedRequest` intercepts 401 responses:

1. Checks
   `KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)`.
   - **Authenticated OAuth user** (`hasAuthenticatedOAuth == true`): throws
     `MerianError.invalidResponse` immediately — the expired JWT must be
     re-authenticated. No Ghost session overwrite is attempted.
   - **Ghost/anonymous session** (`hasAuthenticatedOAuth == false`): detects a
     zombie session, calls `SupabaseManager.shared.signOut()` followed by
     `initializeGhostSession()`, waits 1.5 seconds for the Kong API Gateway to
     sync the new ES256 signature, then retries the request once with
     `isRetry: true`.
2. If the retry also fails, throws `MerianError.invalidResponse`.

This logic is centralized in `performAuthenticatedRequest` — callers never need
to handle JWT refresh themselves.
