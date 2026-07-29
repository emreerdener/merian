# Core Network

This directory owns Merian's authenticated, certificate-pinned foreground
network client. Durable background uploads and replay scheduling live under
`Core/Data/OfflineSync`.

## Environment selection

`SupabaseManager` is initialized from the typed `MerianEnvironment`
configuration. Missing or invalid Supabase values keep app startup non-crashing
but block real endpoint construction. A Debug simulator that resolves to the
known production Supabase host is different: the configuration remains valid,
and the app logs a conspicuous production-use diagnostic while auth, reads, and
writes continue.

Use matching local/staging URL and client-key overrides in ignored
`Config.local.xcconfig` for routine simulator work. For a deliberate production
smoke test, the Xcode Run environment variable
`MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1` suppresses only the
diagnostic. It does not redirect traffic, isolate rows, or prevent a cleared
session from creating an anonymous production user.

## `MerianNetworkClient`

- Builds authenticated requests to Supabase Edge Functions and retains the
  existing response/request DTO contracts.
- Uses one pinned `URLSession` for both inference and connection prewarming.
  `prewarmInferenceEndpoint()` sends `OPTIONS` to `/identify-multimodal`; an
  auth SDK request is not considered a prewarm because it uses another
  connection pool.
- Adds `X-Merian-Constrained-Network` for aggregate diagnostics without exposing
  the active interface or user identity.
- Reads privacy-safe `Server-Timing` and `X-Merian-Edge-Region` response
  headers.
- Records URLSession request-upload, time-to-first-byte-after-upload, and
  response-transfer intervals.
- Treats current `/identify-multimodal` `200` as a server durability fence:
  moderation, required media promotion, primary species resolution, scan
  creation, and owner-scoped read-back have completed.
- Builds `OwnedScanRecoveryPayload` only from an owned local record. Single
  `/check-scan-status` can repair eligible non-media state; record-based Explore
  sharing can combine it with owner-staged local image/video/audio. Ask the
  Community repairs status first. Bulk status never mutates server state.
- Translates known technical Explore failures at the UI boundary so database
  authorization and missing-row implementation detail are not customer-facing.

## Field trip completion evidence

Catalog and template-detail checklist items may decode an optional private
`completed_scan_id` into `FieldTripChecklistItem.completedScanId`. The ID is the
exact saved scan that completed that item; clients must not infer completed
slots from `completed_count` or array order. The API supplies no media URL.
Explore resolves the identifier against the current device's `LocalScanRecord`
library and reuses `ScanThumbnail`/Insight navigation when available.

The backing catalog/detail RPCs are service-role-only. iOS reaches them through
the authenticated `/field-trips` Edge Function, which supplies the verified
caller ID. Never add this field to public Field trip profiles, publication or
challenge DTOs, Explore feed/map DTOs, or the capture-context DTO.

Template detail additionally decodes optional `FieldTripProgress.publicationId`
/ `publishedAt`. These fields refer only to the requesting owner's active,
non-deleted outing publication. The title badge derives Published from a
non-null publication ID; completion and Community results are not substitutes.
Missing fields remain backward-compatible and render Private during a staged
backend/client rollout.

## Field trip scan progress

`applyFieldTripProgress(scanId:preferredGoal:)` posts
`{"action":"apply_scan_progress","scan_id":"..."}` and may add an optional
`preferred_goal` object containing `user_field_trip_id` and `item_id`. The hint
is best effort and server-validated; older callers omit it. The client decodes
standard updates from `data` plus Seasonal Challenge updates from
`challenge_updates`. Both update models optionally decode `creditedLevelNumber`,
`creditedLevelTitle`, `creditedCompletedCount`, and `creditedTargetCount`, plus
removed-item metadata used when a correction invalidates earlier unfinished
credit. These fields describe the level changed by the scan; when a completion
advances immediately, current counts describe the next level while credited
counts preserve the just-completed full ring. Toast accessors fall back to
current counts against the legacy response shape.

Only updates with nonempty `newlyCompletedItems` represent a new credit. The
first item is in server checklist order and supplies the toast label/focus
target, with its prompt as the common-name fallback. Reapplying an already
credited scan is idempotent and yields no progress toast.

`getFieldTripScanContributions(scanId:)` posts
`{"action":"scan_contributions","scan_id":"..."}` and decodes one
`FieldTripScanContribution` per credited standard outing or Event. The DTO
contains only source IDs, labels, credited item/level counts, artwork inputs,
and typed-routing inputs. It must never grow media, coordinates, notes, or
public evidence. The Insight view model silently treats empty and failed reads
as no card.

## Field trip capture context

`getFieldTripCaptureContext()` posts `{"action":"capture_context"}` to the
authenticated `/field-trips` Edge Function and decodes the narrow
`FieldTripCaptureContextResponse`. The response contains standard field
trip/current level metadata, aggregate progress, and unfinished target prompts
only. It must not contain scan evidence, media, location, or field notes.

`MerianNetworkClient` performs the request. `FieldTripCaptureGoalProvider` maps
the source DTOs into a generic `CaptureGoalContextSnapshot`. After a successful
empty response it uses the existing authenticated `template_detail` slug lookup
to validate the optional Backyard Safari introduction. No database or Edge
contract changes are required. `ActiveCaptureGoalStore` owns the five-minute
freshness policy, per-account cache, selected-goal persistence, and silent
stale-data retention. Concurrent freshness checks share the provider request; an
explicit invalidation received while that request is active queues at most one
forced follow-up. Capture never imports these Field trip DTOs. Callers must
never await this request before starting the camera or accepting a capture. See
`docs/backend-and-data/05-api-contracts.md` and
`docs/features-and-hardware/25-field-trips.md`. The source-agnostic ownership
decision and future provider aggregation rules live in
`docs/rfcs/active-capture-goal-context.md`.

## Request-Body Completion

`performAuthenticatedRequest` accepts an optional, idempotent body-upload-
complete callback. `MerianRequestUploadDelegate` fires it from
`urlSession(_:task:didSendBodyData:...)` when all expected bytes have been sent.
Receiving the response is the fallback for protocols that do not deliver upload
progress; a transport failure fires it immediately.

For eligible live-camera still-image analysis this callback releases the durable
queue row for background upload after the inline body no longer competes for
uplink capacity. The caller also installs a two-second fail-safe. Connectivity
loss and app backgrounding release ownership through `OfflineQueueManager`
directly.

## Deferred Context

`updateScanContext` sends owner-authenticated late WeatherKit/geocoding data to
`/update-scan-context`, keyed by `scan_id`. It carries only supported optional
elevation, weather, and semantic-location fields and never resubmits media or
starts another identification.

## Failure Rules

Authentication failures propagate to callers; they are not converted to missing
headers. TLS pin failures, invalid HTTPS URLs, and response validation failures
remain fail-closed. Upload-completion callbacks release queue ownership on
failure, but they do not delete the durable row; the existing live-success path
alone performs queue cleanup and task cancellation.

Transport failures and returned `5xx` responses are ambiguous: the server may
have committed before the connection failed. Foreground replay is therefore
limited to the audited read-route inventory and exact endpoint contracts that
receive a server-supported idempotency key. New routes default to no ambiguous
replay. Insert-only comments/feedback/flags, toggle actions, and multi-action
Field trip requests never gain replay merely because they use `POST`. Signed
upload-session and upload-URL preparation remains excluded from the generic
foreground request replay inventory because avatar and legacy signing requests
do not have a stable scan registration identity. Structured scan signing with
`clientScanId` is database-idempotent on owner/scan/object key, but its durable
retry is owned explicitly by `OfflineQueueManager`; do not turn that guarantee
into blanket replay for every signer caller.

Every retry delay is cancellation-propagating. A task canceled while waiting for
transport, server, route-propagation, or guest-session retry exits with
`CancellationError` before constructing another request. Do not replace these
awaits with `try?`: URLSession cancellation is cooperative, and swallowing the
sleep error would let stale inference work replay after ownership moved to a
newer generation. Foundation may surface its async URLSession bridge as
`NSURLErrorCancelled`; the shared request boundary normalizes that error to
`CancellationError` only when the enclosing Swift task is canceled. Session
invalidation or another transport-owned cancellation retains its original
`URLError`.

A Supabase platform `404 NOT_FOUND` is not an application-level missing record.
`performAuthenticatedRequest` classifies it only when the fixed
`X-Merian-Handler: 1` response marker is absent and the response contains the
stable `SB-Error-Code: NOT_FOUND` header, official missing-function envelope, or
equivalent gateway-without-execution headers. It then replays the same request
after one-, two-, and four-second delays. The handler did not execute, so replay
is safe; request bodies and idempotency keys remain unchanged. A marked
handler-owned `404`, including `Scan not found`, is never route-retried and
remains eligible for the normal owner-row recovery flow. Exhausted platform
route retries become `MerianError.edgeFunctionUnavailable`, so downstream
missing-record logic cannot mark the scan unavailable. Customer surfaces use
temporary-availability copy rather than exposing Supabase router text.

Background `/identify-multimodal` downloads retain the same selected response
headers and run this classifier before general HTTP handling. A platform route
`404` preserves the queued scan and schedules its normal durable retry. A queued
handler `401`, `408`, `409`, `425`, or `429` is also retryable because a fresh
request can refresh authentication, recover an already-finalized result, or
honor transient capacity. Integer `Retry-After` values are bounded by the
queue's maximum delay. Other handler-owned `4xx` responses preserve the local
media as `queueNeedsAttention`; only the exact stable `observation_rejected`
policy response is terminal.

Foreground Identify handling does not translate every `409` into a network
timeout. Only handler responses whose stable code is exactly
`ai_request_in_progress`, `ai_request_already_completed`,
`scan_already_complete`, or `scan_already_finalized` enter the **Restoring
scan** state and remain eligible for exact-ID queue/status hydration. Generic
conflicts, malformed envelopes, and `409` responses from other routes keep their
normal error semantics. Current functions should normally absorb these four
cases and replay `200`; the client branch is a rolling-deployment and
unexpected-race safety net.

Owner-row repair is not a fallback table upsert. The server derives owner
identity, validates/gates recovery, inserts without overwrite, reloads by owner,
and restores media only through validated staging keys. A processing/retryable
or exact policy-rejected job remains unrepaired.

Before Field Chat presentation, `ensureCloudScanAvailableForFieldChat(scan:)`
polls the exact owner status and uses bounded non-media recovery only for
eligible historical drift. Explore sharing can combine the same bounded owner
recovery with newly signed local user media. Both retain the stable scan UUID
and keep transient/unknown state retryable. The joined contract is
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

An HTTP-successful Explore-share response is not accepted on decoding alone.
`shareScanToExplore` requires `success: true`, the exact requested scan UUID,
a valid post UUID, a parseable ISO-8601 share timestamp, an authoritative
location-sharing value, and an explicit `published` publication status. Any
integrity mismatch becomes
`MerianError.invalidResponse`; callers must not cache the post ID or dismiss the
composer as though publication succeeded.

## Sign-out transition

`SupabaseManager` closes the authenticated-request gate and clears observable
account state before asking Supabase Auth to invalidate the local session. It
cancels its ghost-session and public-author refresh tasks first, ignores late
authenticated SDK events while sign-out is active, and serializes concurrent
sign-out callers through one task. `getValidAuthHeaders()` fails closed during
that interval, checking both before and after asynchronous token retrieval, and
session-refresh retries cannot reopen authenticated state. Explore, Field trip,
and profile Edge requests therefore cannot launch with a token that is being
invalidated.

Call `transitionToGhostSession()` for user-facing sign-out or anonymous-session
recovery. It creates the replacement guest identity only after sign-out and
external identity cleanup finish. Account deletion intentionally calls
`signOut()` alone so it does not recreate an identity during deletion. The
`/safe-delete` call may return immediate `200` completion or `202` durable
acceptance; the shared request layer treats either 2xx response as success.
Backend intent and relational cleanup are persisted before the client signs out.
The scheduled account-deletion reaper owns cursor-persisted R2 sweeps, delayed
empty verification, and terminal Auth removal; a new request therefore normally
receives `202`.
