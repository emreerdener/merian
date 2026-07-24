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
    ├── HTTP 4xx → needs attention (permanent failure, terminal)
    └── HTTP 5xx / 429 → handleInferenceRetry: persist retry and reset to .staged until retry budget ends

Cloud deletion (PendingCloudDeletionTask)
    ├── MerianError.invalidResponse → tombstone (resource already gone, no point retrying)
    └── All other errors → retain as OfflineJobRecord waiting for nextRunAt until retry budget ends

Collection sync (OfflineJobRecord id "collection-sync")
    ├── HTTP 200 → mark complete and clear pending bridge bit
    └── Push failure → retain as OfflineJobRecord waiting for nextRunAt until retry budget ends
```

Both uploads and inference use the same background `URLSession`
(`URLSessionConfiguration.background`) with `sessionSendsLaunchEvents = true`,
so iOS can re-attach in-flight tasks on app relaunch and deliver inference
results while the app is completely suspended. Current upload task descriptions
are `upload|{scanId}|{uploadIndex}|{syncGeneration}`. Current inference task
descriptions are `inference_v2|{inferenceGeneration}|{scanId}`. Parsers continue
to accept the earlier three-part upload form and `inference_{scanId}` for
in-flight tasks created by an older app version.

The generation in each current description is an ownership fence, not merely a
deduplication key. Delayed callbacks, retry timers, server-status probes, and
background-expiration handlers must still own that exact generation before
they clear manager state, cancel a URLSession task, delete a queued scan, or
complete a UI progress token. Cancellation remains cooperative, so task
dictionaries also use compare-before-clear registry tokens. Retry state itself
lives in SwiftData (`OfflineQueuedScan.queue*` plus `OfflineJobRecord`) rather
than in process memory.

Delayed status probes and server polls retain their registry token across
awaited status checks, URLSession cancellation, targeted recovery, and queue
state transitions. Every post-await mutation requires the same token and a
non-cancelled task. Do not clear a slot before starting its async action: doing
so permits a replacement to install itself while the old action is still able
to write.

---

## UI Error Surface Patterns

| Error scenario                                            | UI outcome                                                                                                                                                                                                    |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inference decoding failure (`MerianError.decodingFailed`) | InsightSheet opens with "Analysis Failed" / "Data Unreadable" placeholder result                                                                                                                              |
| Network timeout (Pro user)                                | InsightSheet opens with a "Network timeout" placeholder, explains automatic retry/reconnect behavior, and suppresses non-biological collection/retention copy                                                  |
| Network timeout (Free user)                               | Paywall sheet presented via `TriggerPaywall` notification                                                                                                                                                     |
| R2 upload failure (missing source file)                   | Queued scan remains visible with needs-attention copy plus retry/cancel actions                                                                                                                               |
| R2 upload transient failure                               | Queued scan remains saved locally with persisted next retry time                                                                                                                                              |
| SwiftData save failure during deletion                    | `.error` logged; file deletion aborted; DB state remains consistent (record still exists, deletion task not persisted)                                                                                        |
| SwiftData store corruption at startup                     | Store artifacts are quarantined, a support manifest is written, store-aware persistent open is retried once, and the user sees "Library Repaired" if recovery succeeds                                        |
| SwiftData schema migration failure at startup             | Legacy store artifacts are archived under `store-rescue/`, a fresh persistent current-schema store opens, and the user sees "Library Rebuilt" with `legacy_store_rescued` telemetry; safe mode is only used if rescue fails |
| Non-corruption `ModelContainer` startup failure           | Local store files are not moved; app boots in in-memory safe mode with a startup notice                                                                                                                       |
| JWT expiry (authenticated OAuth user)                     | `MerianError.invalidResponse` thrown; callers surface a re-auth prompt                                                                                                                                        |
| Photos import blocked by quota                            | Existing paywall opens; the durable inbox receipt remains pending for an entitlement retry                                                                                                                   |
| Photos import blocked by capture capacity                 | Capture shows "Finish your current capture to import the shared photo." and retains the receipt until staged media clears                                                                                    |
| Photos import unsupported, missing, or unreadable         | Error haptic plus "Naturebook couldn’t import that photo."; any durable receipt is removed as terminal                                                                                                      |

Photos document-import failures use `ExternalImageImportError` and capture
feedback rather than broadening `MerianError`, because they occur before a scan
or network request exists. Temporary quota/capacity states are not errors and
must not delete the Application Support inbox copy. See
`docs/features-and-hardware/26-photos-share-import.md`.

---

## Background Ingestion Dead-Letter Pattern

When an inference endpoint fires `runBackgroundIngestion()` and `insertScan()`
fails (FK violation, DB timeout, network partition), the iOS client may already
have received a `200 OK` with the AI result. The active multimodal path claims a
`scan_ingestion_jobs` row before AI inference and updates it through
`processing`, `finalizing`, `failed_retryable`, `failed_terminal`, and
`complete` states so `/check-scan-status` can report more than a bare not-found
result.

For eligible live-camera still-image analysis, request-body completion releases the matching durable
queue row for background upload. Transport failure, connectivity loss, app
backgrounding, and a two-second fail-safe release it too; release is idempotent
and never deletes the row. Only the established live-success cleanup path adopts
saved media, cancels duplicate tasks, and removes the queue record. This keeps a
failed or suspended foreground request recoverable without allowing two uploads
to contend from the start.

`/update-scan-context` may return `409` when the late WeatherKit/geocoding result
arrives before the ingestion claim. The live caller retries once after a short
delay and the local queued record retains the context for normal replay. A 409
must not trigger another identification request and must not discard the scan.

Compatibility scan-producing endpoints (`identify`, `identify-describe`,
and `audio-spec`) now use the shared compatibility ledger to claim the same
job/intent rows after inference and before returning success; staged image/audio
and text-only compatibility intents are shaped for `/identify-multimodal`
replay, while inline media is redacted and remains client-retry only. The
background task still catches insertion failures and:

1. Logs a structured error via
   `logStructuredError("background_ingestion_failed", { scan_id, user_id, error })`.
2. Inserts a row into `public.failed_scan_ingestions` (dead-letter table) with
   the `scan_id`, `user_id`, and `error_message`.
3. If the dead-letter insert also fails, logs
   `logStructuredError("dead_letter_write_failed", ...)` and continues — the
   primary failure is already logged.

**Ops replay**: Start with `scan_ingestion_jobs` for current state, attempt
count, stage, retryability, `upload_session_ids`, and `manifest_checksum`, then
inspect the paired `scan_ingestion_intents` row for `resumable`,
`payload_checksum`, `inline_media_redacted`, and the sanitized
`request_payload`. Query `failed_scan_ingestions` by `user_id` and `failed_at`
only as the older dead-letter fallback and detailed insert-failure history. The
scheduled `replay-scan-ingestion` worker claims staged media/audio/video and
text-only jobs with resumable intents and re-invokes `identify-multimodal` with
the same `client_scan_id` and media manifest; inline-media redacted jobs still
require the iOS queue to retry. The `ignoreDuplicates: true` guard in
`insertScan` makes replay idempotent - a re-run will not create duplicate rows.
The `ERROR` status guard in `identify/index.ts` prevents inserting scans where
the moderation pipeline returned an error status (null images), so only genuine
ingestion failures reach the dead-letter table. Staged media that still belongs
to an active lease or future retry remains pending in
`reconcile-scan-media-assets`; after TTL abandonment the worker marks the job
`failed_terminal` with the `media_reconciliation_abandoned` stage so support can
separate missing-media terminal failures from retryable server failures.

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
