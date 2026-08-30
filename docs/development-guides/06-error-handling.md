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
    case aiConsentRequired
    case proRequiredForOfflineTracking
    case hardwareUnavailable
}
```

| Case                            | Meaning                                                                                 | Caller contract                                                                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `invalidURL`                    | URL construction failed (programming error)                                             | Log and abort. Do not retry.                                                                                                        |
| `uploadFailed`                  | R2 `PUT` returned non-200.                                                              | Retain local media; retry transient 429/5xx and use needs-attention for auth/policy. Never infer deletion.                          |
| `invalidResponse`               | Missing/non-HTTP, malformed-success, or unresolved auth response.                       | Never infer a remote mutation from this error. Preserve durable retry state and surface the appropriate UI error.                   |
| `decodingFailed`                | `JSONDecoder` failed on a network response.                                             | Surface "Analysis Failed" graceful degradation result in `InsightSheet`; queued retry keeps the consumed scan.                      |
| `httpError`                     | A handler or service returned non-2xx.                                                  | Classify by stable handler code and durable ownership; never infer device connectivity from a `5xx`.                                |
| `networkTimeout`                | The request boundary classified connectivity loss.                                      | Queue-backed work changes to the exact queued presentation; only queue-less direct work shows "Network timeout".                    |
| `aiConsentRequired`             | Required adult, Terms, or Gemini cloud evidence is absent or rejected.                  | Preserve the saved scan, return the account to Ready, and never increment the network circuit breaker.                              |
| `proRequiredForOfflineTracking` | Legacy compatibility signal; current scan submissions are queue-backed before inference | Do not use it to delete or reject an already-durable ordinary Flash queue item. Pro-only mode selection is gated before submission. |
| `hardwareUnavailable`           | LiDAR or other required physical drivers failed to boot.                                | Show UI alert explaining hardware constraints.                                                                                      |

---

## Required-Consent Restoration Errors

Required-consent restoration has a separate root-presentation contract from
ordinary onboarding errors. Once an authenticated account with missing local
evidence enters `.reconciling`, a fetch, decode, push, or verified-ledger-write
error must not set restoration to `.resolved`, route to the Ready consent
screen, or infer that consent is absent.

- A non-cancellation failure remains on the neutral `ConsentRestorationView`,
  enters `.waitingToRetry`, and schedules account- and
  synchronization-generation-fenced retries after 5, 10, and 20 seconds.
- **Try Again** may replace a pending timer with an immediate attempt. After the
  automatic budget is exhausted, `.retryRequired` keeps the same action
  available and resets the budget when the user invokes it.
- Duplicate same-account auth notifications preserve pending retry state and do
  not consume attempts. Account or generation changes cancel stale work; if the
  same unresolved account loses a retry timer during invalidation, its state
  returns to `.reconciling` under the new generation.
- An expired cached Supabase session is a refresh transition, not an auth
  failure. It keeps authenticated requests closed while its known account owns
  the neutral restoration root; only `tokenRefreshed` or `signedOut` may
  complete that auth decision.
- Cancellation remains pending for the next session/account decision. Only an
  identity-fenced authoritative merge followed by verified persistence may
  resolve a restoration that began because local evidence was missing.

See the
[state machine](../features-and-hardware/04-onboarding.md#root-presentation-gate)
for the complete transition matrix and UI contract.

---

## Inference Consent-Policy Errors

`MerianError.aiConsentRequired` is a policy transition, not an ordinary network,
entitlement, or retry-budget failure. It can arise either because the
authoritative pre-dispatch cloud proof is absent or because a handler-owned
response is exactly HTTP `403` with code `ai_consent_required`.

- `MerianNetworkClient` performs the cloud proof before building an Identify
  body. A first-time account must push pending adult, Terms, and Gemini evidence
  and fetch those account rows plus the all-version Gemini head before its first
  request.
- Foreground and background paths durably fence only the active account,
  invalidate its cloud-ready marker, and return a completed user to the Ready
  disclosure after restoration resolves.
- `OfflineQueueManager` keeps the observation and every media file, records
  needs-attention with `ai_consent_required`, and returns without scheduling
  automatic inference backoff. **Retry now** cannot be offered as though the
  unchanged request could repair policy state.
- Reapproval creates fresh evidence. The Gemini grant extends the provider head
  fetched after rejection. Once **Start scanning** opens the local lifecycle
  gate, the queue resumes only the newest exact-account, exact-scan row with an
  unreleased, dispatchable funding reservation. Another authoritative fetch is
  still required before provider dispatch. Released, deferred, mismatched,
  legacy, and cross-account rows remain paused for manual review.
- A different `403` remains ordinary authorization/needs-attention.
  `402 pro_required` uses the upgrade path, while `429 ai_quota_daily_exceeded`
  and rate-limit codes use their bounded delay paths. The substring `quota` in
  the database RPC name is never a UI classifier.

The complete evidence and release closure test are in the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).

---

## Inference Error Routing

Scan-admission preflight occurs before this inference taxonomy. Its isolated
request is capped at two seconds, does not wait for connectivity, and does not
retry. Only a classified URL transport failure may consult current local
eligibility and return a queue-only route; that route persists the observation
without a foreground generation, so it never becomes an inference
`networkTimeout`. A valid plan/quota denial opens the paywall. Cancellation,
missing or malformed preview data, authentication/TLS failure, and server
failure preserve staged input and show retry feedback instead of bypassing
admission.

`InferenceEngine.analyze` handles errors in this priority order:

1. **`CancellationError`** (or `URLError.cancelled`) — inference was cancelled
   (user navigated away or backgrounded). Do not refund the scan token. Do not
   surface any UI. The scan is already durably enqueued in the offline queue
   (written to disk synchronously in `submitStagedCapture` before `analyze()`
   was called) and will complete via the background URLSession path.
   Authenticated/public transport, `5xx`, route-propagation, and guest-session
   retry sleeps must propagate this cancellation before issuing another request;
   never use `try?` around those sleeps.
2. **Recoverable exact-ID ingestion conflict** — Publish **Restoring scan /
   Safely saved**, retain the exact presentation scan ID, and allow background
   or status recovery to hydrate only that same UUID.
3. **`MerianError.aiConsentRequired`** — Keep the saved observation and media,
   publish **Approval needed / Scan saved** only as a temporary fallback while
   root presentation returns the account to Ready, and stop. Do not record a
   circuit-breaker failure: a policy rejection is not evidence that transport is
   unhealthy, and repeated rejections must not create a 15-minute cooldown after
   fresh approval.
4. **Exact provider-admission errors** — Route `402 pro_required`, daily quota,
   and stable user/IP rate-limit codes to their distinct saved-scan recovery
   states. These authenticated admission decisions do not record a network
   circuit failure.
5. **Exact `400 observation_rejected`** — Publish **Try another capture / Scan
   not processed**, mirror the background queue's terminal non-actionable
   disposition, and do not record a network circuit failure or retry the same
   rejected media as though connectivity had failed.
6. **Queue-backed connectivity failure** — Release the upload hold, retire the
   foreground provider owner idempotently, publish the exact
   `queuedPresentationScanId`, and stop live processing without `SpeciesData`,
   error haptic, or network-circuit failure. The open Insight binds only that
   durable row and shows **Queued for later**. A first transport failure returns
   directly to this branch; a silently stalled request reaches the same branch
   through the queue-owned 15-second foreground deadline. The durable queue owns
   later retry. A direct queue-less request retains its reviewed 90-second
   window and timeout presentation.
7. **`MerianError.decodingFailed`** — Gemini returned a malformed or unreadable
   response. Do **not** refund the token — the scan is already in the offline
   queue and will be retried by the background upload path. Refunding here would
   give the user a free extra scan against a quota already consumed. Set
   `speciesData` to an **Analysis Failed / Data Unreadable** error placeholder.
8. **Remaining failures** — Classify connectivity separately from service or
   client-contract failure. Queue-less connectivity may show **Network timeout /
   Please try again**. A saved service failure uses **Analysis delayed / Scan
   saved** while the durable queue owns recovery. Both are error-presentation
   states, never non-biological classifications; placeholder routing must hide
   collection/retention success treatment.

The queue-backed branch above is implemented source behavior, not current
release evidence. The catch path now preserves exact local presentation
authority after connectivity monitoring retires the durable generation, and
queue-backed Identify disables the shared helper's inline transient replay.
Protected URLSession-level race, request-count, queue-less timeout, provider
failure, and stale-result controls cover the joined boundary. Error producers
set `SpeciesData.presentationRole` to `.inferenceError`; decoded and persisted
classifications use `.inferenceResult`. `isInferenceErrorPlaceholder` therefore
does not depend on display copy such as **Analysis delayed**. See the
[live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md)
for the ownership split, no-inline-replay rule, regression matrix, and remaining
hosted/device closure status.

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
    ├── HTTP 401 → retain for authenticated durable retry
    ├── Exact 403 ai_consent_required → needs attention until fresh approval
    ├── Other HTTP 403 → needs attention (authorization failure)
    └── HTTP 4xx (other) → needs attention (terminal)

Inference (background URLSession download task)
    ├── Status found → persist completed-result marker before local hydration
    │   ├── Hydration/promotion/delete succeeds → delete queue row and complete
    │   ├── Transient local recovery failure → remain .inferencing; bounded owner-result recovery only
    │   └── Captured-media contract mismatch → needs attention immediately; preserve no-redispatch fence
    ├── Transport error with no durable completed-result marker → handleInferenceRetry: persist retry and reset to .staged until retry budget ends
    ├── Transport/status error with durable completed-result marker → wait for server/local recovery; never dispatch provider again
    ├── HTTP 200 → processInferenceDownloadResult → persist LocalScanRecord, delete OfflineQueuedScan
    ├── Platform route 404 or handler 401 / 408 / 409 / 425 / 429
    │   └── handleInferenceRetry: preserve media, poll the ledger, and persist bounded retry
    ├── HTTP 402 / stable entitlement code → preserve media with needs-attention and View plans guidance
    ├── Exact observation_rejected → terminal policy outcome
    ├── Other handler 4xx → preserve media with queueNeedsAttention for retry/cancel
    └── HTTP 5xx → handleInferenceRetry: persist retry and reset to .staged until retry budget ends

Cloud deletion (PendingCloudDeletionTask)
    ├── Decoded success: true → remove the local task and complete its OfflineJobRecord
    └── Any error, including invalidResponse/auth/malformed 200 → retain the task and schedule capped-backoff retry without expiration

Collection sync (OfflineJobRecord id "collection-sync")
    ├── HTTP 200 → mark complete and clear pending bridge bit
    └── Push failure → retain as OfflineJobRecord waiting for nextRunAt until retry budget ends
```

`queueNextRetryAt` is durable eligibility state, not evidence that a timer is
running. Every successful retry-date write must ask `OfflineJobScheduler` to
reselect its earliest wake. Foreground activation and connectivity restoration
must rebuild that wake from SwiftData because delayed Swift tasks do not survive
process termination and are cancelled on network loss. Queue UI resolves only
stable machine codes into safe customer categories; it must never display
`queueLastErrorMessage`. A future online deadline combines the safe reason with
a live countdown and optional **Retry now** action. Offline work explains that
retry resumes with connectivity and suppresses both the numeric countdown and
**Retry now**. It may retain a local navigation action such as **View plans**,
which does not dispatch queue work. An elapsed deadline renders no helper or
retry action because the analyzing state already communicates the retry.
Consent, entitlement, missing-media, retry-limit, and terminal cases use
dedicated copy or actions rather than a generic retry.

Both uploads and inference use the same background `URLSession`
(`URLSessionConfiguration.background`) with `sessionSendsLaunchEvents = true`,
so iOS can re-attach in-flight tasks on app relaunch and deliver inference
results while the app is completely suspended. Current upload task descriptions
are
`upload_v2|{ownerUUID}|{scanId}|{uploadIndex}|{syncGeneration}|{serverObjectKey}`.
Current inference task descriptions are
`inference_v3|{ownerUUID}|{inferenceGeneration}|{scanId}`. Parsers continue to
accept the earlier three-, four-, and five-part upload forms,
`inference_v2|{inferenceGeneration}|{scanId}`, and `inference_{scanId}` for
in-flight tasks created by an older app version; unknown ownership remains
fail-closed across account transitions.

The generation in each current description is an ownership fence, not merely a
deduplication key. Delayed callbacks, retry timers, server-status probes, and
background-expiration handlers must still own that exact generation before they
clear manager state, cancel a URLSession task, delete a queued scan, or complete
a UI progress token. Cancellation remains cooperative, so task dictionaries also
use compare-before-clear registry tokens. Retry state itself lives in SwiftData
(`OfflineQueuedScan.queue*` plus `OfflineJobRecord`) rather than in process
memory. If a task loses its Auth lease after durable upload/inference ownership
was written, the client makes a bounded durable-retreat attempt before
cancellation. A persistent save failure leaves the transport suspended or the
durable owner intact, and the independent Auth-transition sweep must commit the
retreat or abort the identity change; the client never cancels first and leaves
an unowned `.uploading` or `.inferencing` row. High-authority scan-ingestion
retry/completion markers and attempt counts are redundant copies, not
alternatives: fresh reads consult both, writers repair drift before mutation,
counts use the nonnegative monotonic maximum, and cloud completion outranks
retry state. Never authorize Identify from only one cached model fault.

Delayed status probes and server polls retain their registry token across
awaited status checks, URLSession cancellation, targeted recovery, and queue
state transitions. Every post-await mutation requires the same token and a
non-cancelled task. Do not clear a slot before starting its async action: doing
so permits a replacement to install itself while the old action is still able to
write.

---

## UI Error Surface Patterns

| Error scenario                                                                                                                        | UI outcome                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Inference decoding failure (`MerianError.decodingFailed`)                                                                             | InsightSheet opens with "Analysis Failed" / "Data Unreadable" placeholder result                                                                                                                                                                                                                                                                                                                                                           |
| Admission preview reaches its two-second deadline or reports another classified URL transport failure while local eligibility permits | Persist the capture queue-only, show queued confirmation, and start no foreground inference even if reachability still reports online                                                                                                                                                                                                                                                                                                      |
| Admission preview is cancelled, malformed, unauthorized, or fails at TLS/server policy                                                | Preserve staged input and show scan-availability retry feedback; do not create a queue row or infer offline admission                                                                                                                                                                                                                                                                                                                      |
| Known offline before queue-backed provider dispatch                                                                                   | Keep the exact durable row and show queued confirmation; do not start live provider transport                                                                                                                                                                                                                                                                                                                                              |
| First queue-backed connectivity failure after dispatch                                                                                | Source result is same-ID **Queued for later** with automatic-resume copy, no synthetic result/haptic/circuit failure, and exactly one live request. Exact-SHA and physical-device acceptance remain release-gated by the live scan connectivity incident.                                                                                                                                                                                  |
| Queue-less direct connectivity failure                                                                                                | InsightSheet may show **Network timeout / Please try again** as an inference error placeholder; never show non-biological collection/retention copy                                                                                                                                                                                                                                                                                        |
| Exhausted queue-backed handler/provider service failure                                                                               | Show **Analysis delayed / Scan saved** as an inference error placeholder and retain durable retry; never label the device offline or present non-biological success treatment                                                                                                                                                                                                                                                              |
| Exact handler-owned `402 pro_required`                                                                                                | Show **Upgrade needed / Scan saved** for the retained observation; entitlement policy, not connectivity, owns the next action                                                                                                                                                                                                                                                                                                              |
| Exact handler-owned `403 ai_consent_required` or missing authoritative pre-dispatch consent proof                                     | Preserve the saved observation and media, pause inference while consent is invalid, durably route only the active account to Ready, and collect fresh head-anchored approval. **Start scanning** resumes at most the newest same-account, same-ID row with an unreleased dispatchable reservation; provider dispatch still requires another authoritative fetch. This is not quota exhaustion and must not show paywall or daily-limit UI. |
| R2 upload failure (missing source file)                                                                                               | Queued scan remains visible with needs-attention copy plus retry/cancel actions                                                                                                                                                                                                                                                                                                                                                            |
| R2 upload transient failure                                                                                                           | Queued scan remains saved locally with persisted next retry time                                                                                                                                                                                                                                                                                                                                                                           |
| Automatic scan retry budget is exhausted                                                                                              | Pause in needs-attention. An explicit user retry resets the automatic count under the same scan UUID before the atomic claim path, including for description-only staged work; it never allocates a replacement observation UUID.                                                                                                                                                                                                          |
| Known cloud-complete scan cannot hydrate locally                                                                                      | Persist `server_result_local_recovery_pending`, keep the row `.inferencing`, and retry only exact-owner result recovery. A later status outage or relaunch cannot reset it to `.staged`; exhaustion pauses with a manual retry action.                                                                                                                                                                                                     |
| Cloud-complete row violates Captured Media Wire V1                                                                                    | Persist `server_result_local_recovery_contract_mismatch`, pause on the first targeted hydration attempt, skip the full-history fallback, and retain server completion/status plus the no-redispatch fence. Manual retry remains available after a compatible app update; never spend ten transient retries on the same deterministic decode failure.                                                                                       |
| Durable scan-image URL returns R2/CDN 404 with no local match                                                                         | Scan/post metadata remains; the image surface shows a retryable unavailable fallback. Do not label the record archived, hide it from owner history, or delete the relational row as a display fix.                                                                                                                                                                                                                                         |
| Durable scan-image URL has a strongly matched local file                                                                              | Render the local file immediately and enqueue owner-authenticated cloud inspection/repair while online; local visibility is not cloud-restoration confirmation.                                                                                                                                                                                                                                                                            |
| Cloud scan-image repair fails                                                                                                         | Preserve the local file and metadata, pause the process-local repair queue for 15 minutes, log a sanitized request-correlated failure, and retry after the dependency/deployment recovers.                                                                                                                                                                                                                                                 |
| Explore media receives one direct R2-origin 404                                                                                       | Mark only `suspected_missing`; retain public projection and schedule a confirmation no earlier than five minutes later.                                                                                                                                                                                                                                                                                                                    |
| Some Explore primary media is confirmed missing                                                                                       | Omit confirmed-missing items, keep the post public as `degraded`, preserve engagement, and expose owner recovery state.                                                                                                                                                                                                                                                                                                                    |
| All Explore primary media is confirmed missing                                                                                        | Reversibly quarantine every public projection; preserve author publish state, row, likes, comments, reports, and recovery evidence.                                                                                                                                                                                                                                                                                                        |
| Explore origin check times out or returns non-404 failure                                                                             | Record a retryable result. Never turn transport, credentials, `5xx`, CDN, or client failure into confirmed loss.                                                                                                                                                                                                                                                                                                                           |
| Supabase gateway returns platform `404 NOT_FOUND` with no Merian handler execution                                                    | Replay the unchanged authenticated request after bounded one-, two-, and four-second delays. If routing remains unavailable, throw the typed temporary-service error and show `Explore is temporarily unavailable. Please try again in a few minutes.` Never treat this as a missing scan or persist scan unavailability.                                                                                                                  |
| Identify Recent activity encounters a temporary service/platform failure                                                              | Keep the independently loaded request preview visible and format the Activity section through `ExploreErrorFormatter.recentActivityMessage(for:)`: `Recent activity is temporarily unavailable. Please try again in a few minutes.` Retry reloads Activity only.                                                                                                                                                                           |
| Explore share exposes internal service-role authorization text                                                                        | Translate to `Explore is temporarily unavailable. Please try again in a few minutes.`                                                                                                                                                                                                                                                                                                                                                      |
| Explore share cannot find an eligible owner row after recovery                                                                        | Translate to `This observation is still syncing. Please wait a moment and try sharing again.`                                                                                                                                                                                                                                                                                                                                              |
| Explore share returns a malformed or contradictory `200`                                                                              | Reject it as `MerianError.invalidResponse`; do not cache a post ID or dismiss the composer. Keep the current draft mounted and show retry feedback.                                                                                                                                                                                                                                                                                        |
| Explore share request fails after composer submission                                                                                 | Keep notes, hashtags, location choice, and ordered media selection mounted in the same composer; dismiss only after validated publication success.                                                                                                                                                                                                                                                                                         |
| Explore final relational publication fails                                                                                            | The atomic owner-checked RPC rolls back post metadata, timestamp, media, hashtags, and resolved-community state together. Return failure without caching or dismissing; never repair by making separate direct table writes.                                                                                                                                                                                                               |
| Ask the Community returns a malformed or contradictory `200`                                                                          | Reject it as `MerianError.invalidResponse`; do not show a created request or cache publication state. Preserve the current observation and recovery media for retry.                                                                                                                                                                                                                                                                       |
| Insight Field Chat owner row is still syncing, or an action target is missing                                                         | For sync state show `This observation is still syncing. Please try Field chat again in a moment.`; leave `unavailableScanId` unset and keep the action available. Only terminal ownership/unsupported-scan state hides it.                                                                                                                                                                                                                 |
| Field Chat returns a malformed, oversized, cross-subject, cross-conversation, incomplete send-pair, or unconfirmed action `200`       | Reject it as `MerianError.invalidResponse`. Do not replace the loaded private thread, clear the pending send, record feedback, show a note summary, or use generated prompts; retry/edit recovery retains the original send UUID and does not become permanent chat unavailability.                                                                                                                                                        |
| Field Chat returns `503 field_chat_send_in_progress`                                                                                  | The same UUID is still completing after bounded coalescing, or another UUID in that conversation is unanswered. Keep the failed question visible and retryable; replay must preserve its UUID rather than inserting a duplicate.                                                                                                                                                                                                           |
| Field Chat returns `503 field_chat_admission_unavailable`                                                                             | The atomic database admission could not be verified. Fail closed without dispatching the provider or inserting a user row; keep the question retryable under its UUID.                                                                                                                                                                                                                                                                     |
| Field Chat returns `503 field_chat_recovery_unavailable`                                                                              | Narrow stale-quota recovery could not be verified. Do not reopen or redispatch the charged request; keep the same UUID retryable.                                                                                                                                                                                                                                                                                                          |
| Field Chat returns `409 field_chat_idempotency_conflict`                                                                              | The UUID was reused with different normalized text. Do not accept the old pair as confirmation of the edited question; keep recovery visible and allocate a new UUID only when the user chooses Edit and submits a new send.                                                                                                                                                                                                               |
| Field Chat load ends with a UUID-bound user row and no assistant                                                                      | Reconcile it into the failed pending bubble with the same UUID, text, and Retry/Edit actions. Do not show it as delivered or discard it on relaunch; retain the server's unfiltered row count for conversation-capacity checks.                                                                                                                                                                                                            |
| SwiftData save failure during deletion                                                                                                | `.error` logged; file deletion aborted; DB state remains consistent (record still exists, deletion task not persisted)                                                                                                                                                                                                                                                                                                                     |
| Multiple wake sources request cloud-deletion drain                                                                                    | A process-local single-flight latch admits one drain. Persisted `.running` state remains restartable after process loss; the owner-fenced endpoint makes repeated remote deletion idempotent.                                                                                                                                                                                                                                              |
| SwiftData store corruption at startup                                                                                                 | Store artifacts are quarantined, a support manifest is written, store-aware persistent open is retried once, and the user sees "Library Repaired" if recovery succeeds                                                                                                                                                                                                                                                                     |
| SwiftData schema migration failure at startup                                                                                         | Legacy store artifacts are archived under `store-rescue/`, a fresh persistent current-schema store opens, and the user sees "Library Rebuilt" with `legacy_store_rescued` telemetry; safe mode is only used if rescue fails                                                                                                                                                                                                                |
| Non-corruption `ModelContainer` startup failure                                                                                       | Local store files are not moved; app boots in in-memory safe mode with a startup notice                                                                                                                                                                                                                                                                                                                                                    |
| JWT expiry (authenticated OAuth user)                                                                                                 | `MerianError.invalidResponse` thrown; callers surface a re-auth prompt                                                                                                                                                                                                                                                                                                                                                                     |
| Photos import blocked by quota                                                                                                        | Existing paywall opens; the durable inbox receipt remains pending for an entitlement retry                                                                                                                                                                                                                                                                                                                                                 |
| Photos import blocked by capture capacity                                                                                             | Capture shows "Finish your current capture to import the shared photo." and retains the receipt until staged media clears                                                                                                                                                                                                                                                                                                                  |
| Photos import unsupported, missing, or unreadable                                                                                     | Error haptic plus "Naturebook couldn’t import that photo."; any durable receipt is removed as terminal                                                                                                                                                                                                                                                                                                                                     |

An unanswered Field Chat request remains in progress for ten minutes after quota
commit. After that safety window, only the service-only database recovery
routine may prove the exact subject/user/request user row exists, prove its
assistant is absent, and fail that committed quota reservation. The route must
re-read completion before starting a newly metered retry; client code never
guesses staleness or refunds committed usage.

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

For video, canonical completeness means the exact owner's ready playback row,
standalone image rows represented by the captured timeline (or legacy
`max(images - videos × 5, 0)` prefix), and standalone audio rows. Sampled
inference frames may remain in the compatibility image array and are not
standalone media. Migration
`20260729012153_fix_video_scan_canonical_finalization.sql` corrects the former
over-strict check. A real missing projected row still produces retryable
`503 scan_persistence_failed`; neither Edge nor iOS may convert it to success,
hydrate inference frames as display images, or suppress the Field Chat/Explore
prerequisite check.

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
scan. Endpoint, transport, and task cancellation are terminal for this optional
remote enrichment and must not be converted into the retry; the local queue
remains the fallback.

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
abandonment the worker may mark a nonterminal job `failed_terminal` with the
`media_reconciliation_abandoned` reason so support can separate missing-media
terminal failures from retryable server failures. It never rewrites an existing
terminal decision. The reason is recovery-eligible only with exact composite
service proof: a matching post-result dead letter no earlier than the latest
charged normal/replay scan-inference reservation, no exact reserved attempt or
invalid timestamp lineage, and no moderation-rejected or
moderation-pipeline-failed capture lifecycle row. Modern rows additionally bind
exact quota/provider/safety evidence. Legacy unstructured rows must belong to
the immutable exact-ID snapshot taken by the hardening migration, predate the
database rollout cutoff, and match the narrow historical lineage. Timestamp
alone is not authority because a DDL-blocked insert can resume after migration
while retaining an earlier transaction-start `now()`.

### Owner-row recovery decision

Recovery is a compatibility repair for older/interrupted local-cloud drift; it
is not part of a normal current multimodal success.

| Server state                                                                                                                                                                            | Recovery action                                                     |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Owner row exists                                                                                                                                                                        | Return `found`; do not write                                        |
| Job is processing, finalizing, retrying, or `failed_retryable`                                                                                                                          | Defer to the richer ingestion attempt                               |
| Job is a known moderation or provider safety-policy rejection                                                                                                                           | Refuse repair                                                       |
| No job / missing ledger                                                                                                                                                                 | Defer; arbitrary local state is not recovery authority              |
| `complete` without a row                                                                                                                                                                | Allow duplicate-safe minimal owner-row repair, then reload by owner |
| `failed_terminal` with exact `terminal_reason_code = 'replay_exhausted'`                                                                                                                | Allow duplicate-safe minimal owner-row repair, then reload by owner |
| `failed_terminal / media_reconciliation_abandoned` plus exact composite proof                                                                                                           | Allow duplicate-safe minimal owner-row repair, then reload by owner |
| Same reason without charged quota/dead-letter lineage, with an active attempt, older/post-cutoff/incomplete evidence, invalid timestamps, or with moderation rejection/pipeline failure | Refuse repair; terminal label alone is insufficient authority       |
| Any other terminal or unknown reason                                                                                                                                                    | Refuse repair; do not infer policy from error text                  |

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

A handler-owned `503 service_unavailable` while a single status request is
processing `recovery_scan` occurs before restore signing. Preserve the local
record and every media source, present a retryable failure, and require the
production proof/recovery RPC readiness gates; do not continue to upload or
infer owner-row creation. All exact failed/committed normal and replay
reservations remain retained as chronological authority while an eligible
media-abandonment ledger is unresolved, but refunded and unrelated terminal
states retain ordinary 30-day pruning.

The complete error and recovery ordering contract is
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#error-semantics).

## Startup and Auth Failures Are Recoverable

- Apple Sign-In bootstrap failures are no longer fatal. Missing presentation
  anchors, missing callback nonces, and `SecRandomCopyBytes` failures now log
  and return control to the UI instead of terminating the app.
- Missing Apple authorization codes and failed server credential registration
  also fail closed. The client performs one bounded same-request retry for a
  lost response, then clears a newly installed local session and requires a
  fresh Apple authorization. The server attempts compensating revocation if code
  exchange succeeded but Vault persistence failed; neither side logs token
  material.
- Apple's credential-revoked notification is a prompt to revalidate, not proof
  that the active credential was revoked. The app queries the exact active
  provider-specific subject and ignores a stale callback after identity change.
  `.authorized` preserves the session; revoked, missing, transferred, unknown,
  or failed resolution clears the matching local session. None of these client
  outcomes marks the durable deletion provider stage complete.
- During account deletion, an Apple revoke failure is retryable server state,
  not permission to continue. The database retains the Auth user and Vault
  credential, releases the claim with backoff, and the existing deletion health
  monitor surfaces the failure inside `auth_pending`.
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

1. A shared-auth stable code of `auth_session_missing` or
   `invalid_session_token` first calls the pinned Supabase Swift SDK's
   `refreshSession()`. The SDK coalesces concurrent refreshes, rotates the
   access/refresh pair, and the client reconstructs the original request once
   with the fresh access token. A handler auth rejection happens before the
   endpoint's domain mutation, so this one replay is safe even for a POST.
2. If refresh fails, account recovery remains identity-sensitive:
   - an authenticated OAuth account is preserved and the unresolved response
     becomes `MerianError.invalidResponse`; and
   - an anonymous account may enter the existing Ghost replacement path, wait
     1.5 seconds for gateway propagation, and retry once. Its durable local scan
     and media remain queued throughout.
3. An unclassified 401 never replaces either a Ghost or OAuth account. Endpoint
   policy/configuration rejection is not Auth-deletion evidence, so it becomes
   `MerianError.invalidResponse` without rotating the Supabase UUID or creating
   another RevenueCat customer.

This logic is centralized in `performAuthenticatedRequest` — callers never need
to handle JWT refresh themselves. In particular, `invalid_session_token` must
not skip directly to anonymous identity replacement: an expired access JWT can
coexist with a valid refresh token and account-owned first-scan state.
