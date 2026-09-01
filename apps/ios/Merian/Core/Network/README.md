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

Every resolved Supabase origin must be credential-free HTTPS.
`MerianEnvironment`, `MerianSupabaseClientFactory`, and `MerianNetworkClient`
enforce `SecureTransportPolicy` before constructing a client or Edge endpoint.
Signed upload URLs and remote media references are validated at their
corresponding request boundaries. The main application has no ATS exception; see
the
[iOS App Transport Security Contract](../../../../../docs/development-guides/17-ios-transport-security.md).

## Supabase Auth cold-start adoption

`MerianSupabaseClientFactory` enables `emitLocalSessionAsInitialSession`. The
pinned Supabase Swift SDK therefore emits the cached session immediately,
including a session whose access token is expired, and refreshes an expired
session in the background. `SupabaseManager` classifies the initial value before
mutating observable auth state:

- no session is `.signedOut` and may resolve required-consent restoration as
  unauthenticated;
- a non-expired session is `.authenticated` and may start entitlement, identity,
  and synchronization work; and
- an expired session with a user is `.awaitingRefresh`. Authenticated request
  and RevenueCat mutation readiness remain closed and `currentUser` remains
  unset, but the known user ID is passed to `ConsentManager` so a completed user
  stays on the launch-matched restoration root.

The SDK's later `tokenRefreshed` event adopts the valid session through the
normal authenticated path and re-resolves the purchase identity. A terminal
refresh-token cleanup emits `signedOut`, immediately closes RevenueCat session
readiness without creating a provider-anonymous customer, and only then
establishes that no active account remains. Never route an expired cached
session through sign-out cleanup: doing so can briefly resolve restoration and
mount the Ready approval screen before refresh completes.

## `MerianNetworkClient`

- Builds authenticated requests to Supabase Edge Functions and retains the
  existing response/request DTO contracts.
- Rejects an existing but zero-byte foreground playback-video file before
  requesting an upload signature, matching the durable queue and Edge
  positive-size contract.
- Sends positive exact `sizeBytes` for every foreground/avatar/repair/restore
  signing request, validates each returned two-header `requiredHeaders` map, and
  applies its `Content-Type` and `Content-Length` to every PUT. File-backed work
  re-stats before upload and re-signs on mutation; no legacy no-size signing
  method remains.
- Uses one pinned `URLSession` for both inference and connection prewarming.
  `prewarmInferenceEndpoint()` sends `OPTIONS` to `/identify-multimodal`; an
  auth SDK request is not considered a prewarm because it uses another
  connection pool.
- Calls `ConsentManager.ensureCloudConsentForInference()` before constructing
  any provider request. That preflight resolves the active account, awaits
  pending consent synchronization, and requires a freshly fetched adult row,
  Terms row, and granted all-version Gemini stream head for the same account.
  Local onboarding completion or persisted `syncedUserId` values cannot open
  this request boundary.
- Maps only handler-owned HTTP `403` with stable code `ai_consent_required` to
  `MerianError.aiConsentRequired`. That is a disclosure transition—not quota
  exhaustion or generic authorization—and foreground callers must preserve the
  queued scan while the account returns to Ready. `402 pro_required` and the
  `429` quota/rate codes remain separate.
- Treats shared-auth `401 auth_session_missing` and `401 invalid_session_token`
  as refresh-first transitions. The pinned Supabase SDK refreshes the current
  session through its single-flight session manager, then the client rebuilds
  and retries the request once with the new access token. Anonymous identity
  replacement is considered only after that refresh fails, so an ordinary
  expired JWT cannot detach a first scan, consent ledger, or entitlement
  reservation from its existing account UUID. Every unclassified `401` preserves
  both Ghost and OAuth identities because route policy failure is not
  Auth-deletion evidence.
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
  sharing and Ask the Community first resolve and byte-validate a complete
  surviving local-media restore plan, then repair status, and only then request
  signing URLs and upload. They refuse owner-row reconstruction when no
  observation media survives. Field Chat may repair non-media status because it
  does not publish media. Explore can then combine the repaired row with
  owner-staged local image/video/audio; guarded inline repair remains compatible
  with an older released client that stages before Share. Recovery admits only a
  completed-but-missing job or exact authenticated-owner `replay_exhausted`
  reason, or `media_reconciliation_abandoned` with the matching composite
  dead-letter/quota/media-lifecycle proof. Active, retryable, current/later
  policy, unproven abandonment, deletion, foreign, no-ledger, and unknown state
  fails closed. Restore signing uses the explicit `scan_share_restore` purpose
  and deterministic scan/category filenames, so a completed ingestion can stage
  surviving local media only after an unrestricted scan read confirms the active
  JWT-owned row or proves it absent for guarded reconstruction; tombstoned and
  foreign rows fail closed. Bulk status never mutates server state.
- Enforces the inference/playback audio split before request creation. Ordinary
  inline and staged inference accepts only a local, structurally supported WAV;
  a URL-scheme path, compressed M4A, missing file, or extension-only spoof fails
  locally. The upload signer receives `.wav`/`audio/wav` for ordinary audio and
  may receive `.m4a`/`audio/mp4` only with `scan_share_restore`. Historical
  remote references are first materialized as bounded local WAV sidecars rather
  than passed through a file-path initializer. Edge repeats actual RIFF/WAVE and
  structural validation after resolving the bytes.
- Treats `failed_retryable` status as a two-step durable transition rather than
  permanent server ownership. The first observation schedules one
  generation-fenced retry. Its exact `server_retryable_failure` marker and
  attempt count are mirrored across the queued scan and durable job and survive
  required re-upload. Fresh reads consult both copies, counters use their
  monotonic maximum, and serialized transitions repair drift before mutation.
  After the persisted delay, only that marker lets the next preflight send
  Identify. A cloud-complete marker has higher authority and can never be
  replaced by retry state.
- Translates known technical Explore failures at the UI boundary so database
  authorization and missing-row implementation detail are not customer-facing.
- Decodes Explore media-health incidents from the canonical `{data:[...]}`
  envelope and one exact direct-array compatibility shape retained defensively.
  An empty `[]` is therefore a valid no-incidents result instead of a Scan
  Library decode error; retained traces do not prove that this shape was
  deployed, and any other malformed success shape becomes
  `MerianError.invalidResponse`. Scan Library coalesces rapid queue-event
  refreshes of this independent read-only endpoint, preserves one trailing
  refresh requested during an in-flight call, and revalidates the authenticated
  owner before projecting the private incident queue.
- Requires `/delete-scan` to return a decodable `success: true` envelope before
  confirming cloud erasure. A missing, false, malformed, or contradictory 2xx
  response is `MerianError.invalidResponse`; the durable
  `PendingCloudDeletionTask` remains queued because auth or response failure is
  never evidence that remote data is absent. Its capped-backoff retries do not
  expire; the next drain repairs legacy paused job state while the backend
  independently resumes any owner-bound tombstone it already accepted.

## Species Dictionary identity and cache boundary

`SpeciesDictionaryAPIModels.swift` contains only Codable wire DTOs. UI
presentation, routing, taxonomy conversion, and reference-image labels belong to
`Features/SpeciesDictionary/Shared` or the owning Catalog/Detail module.
`SpeciesDictionaryIdentity.swift` is the Core Network normalization owner: it
accepts only canonical UUID species IDs, collapses scientific-name whitespace,
enforces the 160-character name bound, and derives the case-insensitive cache
key.

`MerianNetworkClient` requires exact `schema_version = 1` for catalog, overview,
and detail responses. A detail response must match the requested UUID or the
exact normalized compatibility name before it can be returned. The 10-minute
in-memory memo stores only identifiers proven by the returned entry; it never
aliases a stale requested UUID or an `external:` identifier. Tests for wire
decoding and this request/response/cache boundary live in
`MerianTests/Features/SpeciesDictionary/SpeciesDictionaryTests.swift`.

## Entitlement protocol

The authenticated request builders attach `X-Merian-Entitlement-Protocol: 3` and
preserve `client_scan_id` as the idempotency and original-analysis key. This
covers the four public identification routes: `/identify`, `/identify-describe`,
`/identify-multimodal`, and `/audio-spec`. After the coordinated server cutover,
an older public client receives HTTP `426` with `code = client_update_required`
before provider work; only authenticated internal replay bypasses the public
protocol check.

Identify success envelopes may omit `entitlement` for historical stored
responses. When present, the generated DTO contains `user_id`, `plan_used`,
`credit_consumed`, and `entitlement_after`. The client validates the user,
balance identity, and monotonic `entitlement_version`; it never infers a trial
or Flash fallback from local dates. `get_my_entitlement()` establishes the
current-launch baseline before buffered response metadata can unlock
complimentary access.

Local funding completion uses `plan_used` and `credit_consumed` together.
`pro_complimentary` with `credit_consumed = true` settles the local blocker as
consumed; the same plan with `false` releases the local complimentary assumption
because paid access may have won before final settlement. Bulk
`check-scan-status` exposes owner-scoped `complimentary_state` for deferred
ordering, but that state-only response cannot prove the installed entitlement
snapshot includes terminal settlement. The scheduler performs an authoritative
entitlement refresh before it reopens capacity or removes a terminal consumed
blocker.

The server—not the request payload—classifies whether a single-evidence capture
can use the separate daily Flash policy after complimentary exhaustion. Video,
multiple or mixed evidence, and Pro-only actions remain upgrade-required. The
normative wire and rollout contract is
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Field trip completion evidence

`FieldTripAPIModels.swift` owns Codable DTOs and wire-compatibility fallbacks.
Catalog filtering, lifecycle display, dates, artwork, profile policy, and other
UI presentation belong to `Features/Explore/FieldTrips/Models`; do not add
SwiftUI-facing state or display extensions to the network model file.

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
is best effort and server-validated; older callers omit it. Eligible Capture
submissions also include the same object in the identification-ingestion
payload, allowing the scan-insert trigger to apply progress atomically. The
later Field trips call repeats the hint and retrieves the authoritative receipt
rather than creating a second mutation.

An unreviewed identification earns automatic credit only at the applicable
Possible-match boundary (`Flash >= 0.75`, `Pro >= 0.65`). A weaker result keeps
the preference pending until explicit confirmation or a confirmed
correction/community resolution. A later confidence, inference-tier, or
confirmation downgrade can remove that scan's credit and reopen completed
progress.

The client decodes standard updates from `data` plus Seasonal Challenge updates
from `challenge_updates`. Both update models optionally decode
`creditedLevelNumber`, `creditedLevelTitle`, `creditedCompletedCount`, and
`creditedTargetCount`, plus removed-item metadata used when an identification or
evidence correction invalidates credit. These fields describe the level changed
by the scan; when a completion advances immediately, current counts describe the
next level while credited counts preserve the just-completed full ring. Toast
accessors fall back to current counts against the legacy response shape.

Only updates with nonempty `newlyCompletedItems` represent a new credit. The
first item is in server checklist order and supplies the toast label/focus
target, with its prompt as the common-name fallback. Reapplying an already
credited scan is idempotent and yields no progress toast. Weak pending receipts
and downgrade reconciliation also return no newly completed items and must not
produce a progress toast.

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
only. New and migrated accounts normally receive Backyard Safari Level 1 from
the server's account-enrollment trigger/backfill. The response must not contain
scan evidence, media, location, or field notes.

`MerianNetworkClient` performs the request.
`Features/Explore/FieldTrips/Services/FieldTripCaptureGoalProvider.swift` maps
the source DTOs into a generic `CaptureGoalContextSnapshot`. After a successful
empty response it uses the existing authenticated `template_detail` slug lookup
to validate the optional post-Reset Backyard Safari introduction.
`ActiveCaptureGoalStore` owns the five-minute freshness policy, per-account
cache, selected-goal persistence, and silent stale-data retention. Concurrent
freshness checks share the provider request; an explicit invalidation received
while that request is active queues at most one forced follow-up. Capture never
imports these Field trip DTOs. Callers must never await this request before
starting the camera or accepting a capture. See
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

## Queue-backed Identify Foreground and Retry Ownership

The durable queue, rather than the foreground HTTP helper, owns retry after the
first transport failure of a queue-backed live Identify request. The client uses
one explicit per-call ownership policy:

- queue-backed `identifyMultiModal` gets one 15-second foreground attempt and
  returns its first transient `URLError` to `InferenceEngine`, after the
  idempotent body-sent callback releases the upload hold;
- `InferenceEngine` changes the exact still-current Insight to **Queued for
  later** and retires durable foreground ownership idempotently; and
- durable replay or exact-ID status recovery decides when another provider
  attempt is eligible.

This exception is scoped to queue-backed live Identify transport. It does not
remove reviewed replay from queue-less direct callers, audited read routes,
handler-owned authentication refresh, or Supabase route-propagation recovery. A
returned handler/provider `5xx` also remains a service failure rather than
evidence that the device is offline.

The 15-second foreground bound is intentionally more than twice the documented
six-second cache-hit end-to-end p95 target. It prevents black-holed Wi-Fi from
holding a saved scan in live analysis for the direct caller's 90-second window.
A slow valid server result remains recoverable under the same idempotency key
and durable scan ID; the foreground deadline is a presentation/ownership
handoff, not scan loss.

**Current source status (2026-08-10): remediated; release acceptance pending.**
`performAuthenticatedRequest` carries `allowsTransientTransportRetry` through
transport, auth-refresh, route-propagation, and handler retry recursion.
`identifyMultiModal` exposes `durableQueueOwnsRecovery`; queue-backed engine
calls set it to true, coupling the 15-second bound with no inline retry, while
queue-less calls keep the 90-second/replay default. Protected request-policy
regressions assert both request deadlines, one immediate queue-backed failure,
and one stable-key queue-less replay. The engine regression also proves that a
deadline timeout can retire the active owner without a prior path-monitor
callback. Exact-SHA hosted and physical connectivity evidence remain release
blockers in the
[live scan connectivity handoff incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).

## Deferred Context

`updateScanContext` sends owner-authenticated late WeatherKit/geocoding data to
`/update-scan-context`, keyed by `scan_id`. It carries only supported optional
elevation, weather, and semantic-location fields and never resubmits media or
starts another identification. This method is the transport adapter only.
`CaptureSubmissionDeferredContextService` owns local-first persistence and the
single optional 500 ms retry. Endpoint, transport, or task cancellation is
terminal and never starts that retry.

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

Queue-backed live Identify is the additional durable-owner exception described
above: once its first transport attempt fails, immediate UI handoff takes
priority over generic inline transport replay. The per-call policy is now
implemented and protected by transport-boundary request-count/timing tests;
release acceptance still depends on the incident's exact-SHA and device gates.

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

The Explore replay-cancellation unit regression must observe its first
`MockURLProtocol` dispatch through a bounded monotonic wait before canceling the
task. A fixed executor-yield count is not a URLSession scheduling guarantee on
hosted simulators. Keep both exact request-count assertions: one request before
cancellation and still one afterward, proving the cancellation-propagating retry
delay did not construct a replay.

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

An HTTP `200` is only a candidate background success. Its body must be nonempty,
decode as the generated Identify envelope, not explicitly report
`success: false`, contain a nonempty bounded scan ID, and contain a finite
confidence score from zero through one before local finalization starts. Empty,
truncated, or structurally unusable bodies are ambiguous transport outcomes and
enter exact-ID status recovery plus the durable retry path. The queue row is
removed and its job is marked complete only after response persistence and the
main-context queue deletion both commit. Wrong-scan envelopes, local save
failures, and cleanup save failures retain the queue instead of converting a
no-op save into data loss. A valid confidence-zero envelope for the exact scan
remains terminal and intentionally creates no `LocalScanRecord`, but its source
media stays intact until the main-context queue deletion commits and authorizes
file cleanup. The guarded deletion marks the job complete, inserts the completed
event, and removes the row in the same save; only explicit deletion records
cancellation.

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

Scan-status success is also treated as untrusted input. Single responses must
decode to the reviewed enum, may echo only the exact requested scan ID, and
cannot report a negative job-attempt count. A bulk response must contain exactly
one unique row for every requested scan ID and no foreign row. Duplicate,
missing, malformed, foreign, or negative-attempt rows become
`MerianError.invalidResponse`; bulk decoding never uses
`Dictionary(uniqueKeysWithValues:)`, whose duplicate-key precondition would
otherwise let a contradictory server response terminate the app.

Before the first Field Chat request,
`ensureCloudScanAvailableForFieldChat(scan:expectedScanId:)` first requires the
local record to match the engine result that will be presented, then polls the
exact owner status and uses bounded non-media recovery only for eligible
historical drift. Explore sharing can combine the same bounded owner recovery
with newly signed local user media. Both retain the stable scan UUID, reject a
stale record/engine identity combination, and keep transient/unknown state
retryable. A handler-owned missing scan is classified by stable
`code: "not_found"`; case-insensitive `Scan not found` text remains only a
released-backend compatibility fallback when no stable code is present. The
joined contract is
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

An HTTP-successful Explore-share response is not accepted on decoding alone.
`shareScanToExplore` requires `success: true`, the exact requested scan UUID, a
valid post UUID, a parseable ISO-8601 share timestamp, an authoritative
location-sharing value that equals an explicitly requested privacy mode, and an
explicit `published` publication status. Unknown location values are rejected
instead of being coerced into success. Any integrity mismatch becomes
`MerianError.invalidResponse`; callers must not cache the post ID or dismiss the
composer as though publication succeeded.

Ask the Community applies the same candidate-success rule: decoder failures,
unknown request statuses, false success flags, identity mismatches, invalid
UUIDs/timestamps, or non-`needs_id` results become
`MerianError.invalidResponse`.

Field Chat responses are decoded through one strict path for Insight scans,
Explore posts, and Species Dictionary entries. Requests select exactly one
source-specific key: `scan_id`, `post_id`, or `species_id`. Every envelope must
echo the requested subject through `subject_id`, including when the thread is
empty. Every message must have a unique UUID, match that same subject through
the compatibility `scan_id`, match the envelope's valid conversation UUID,
contain trimmed/nonempty text bounded to 4,000 characters, and fit the exact v1
server limits. Field Chat JSON is rejected above the reviewed 1 MiB decode
ceiling. A send response must also contain exactly one user message and one
assistant message carrying the requested `client_message_id`, and the
acknowledged user row must contain the exact trimmed text that was sent.
Invalid, contradictory, or incomplete envelopes never reach the Field Chat
feature's `InsightChatViewModel.apply`; failed sends remain retryable under the
same canonical lowercase idempotency UUID rather than clearing the pending
question or creating a duplicate on manual retry. A backend
`field_chat_idempotency_conflict` means that UUID was reused for edited text and
is never treated as confirmation of either send.

Core Network owns those wire contracts and validation rules. The source-specific
presentation adapter lives in
`Features/FieldChat/Services/FieldChatEndpoint.swift`; host views do not select
or call these routes directly.

Species Dictionary Field Chat calls `/species-dictionary-chat`; the app sends
only the canonical dictionary UUID as `species_id`. The route's stable
`species_not_available` response is permanent only for that dictionary subject,
while shared transport and admission failures remain retryable. Dictionary
product telemetry records the source/action outcome without the species UUID,
name, conversation ID, or message ID. Migration
`20260821030027_add_species_dictionary_field_chat.sql` extends atomic admission
and stale recovery to all three chat families;
`20260824210544_preserve_field_chat_daily_usage.sql` then makes its content-free
user/day counter the intended authority across conversation deletion. The
backend candidate remains release-held until its Ghost handler registry and real
three-family database paths execute without skips, cutover remains closed until
all three corrected bundles are explicitly activated, quota denial proves no
empty conversation, Swift/Deno prompt labels make identical normalization
decisions, and release clearance is bound to retained exact-SHA evidence. Client
replay correctness cannot substitute for those server gates.

The request sends the canonical `client_message_id` as `Idempotency-Key`, and
manual retry reuses it. `species-dictionary-chat` is also in
`idempotencyAwareFunctionNames`, so `canReplayAfterAmbiguousFailure`
automatically retries a lost response or retryable `5xx` with the exact same
body and lowercase UUID. The regression returns failure once, then one saved
pair, and asserts both attempts carried the identical key. Missing or malformed
`species_id` maps to `400 invalid_request`; only a valid canonical UUID that is
unavailable/nonbiological maps to the permanent `404 species_not_available`
subject state.

Atomic admission and stale-request recovery remain backend authority.
`field_chat_send_in_progress`, `field_chat_admission_unavailable`, and
`field_chat_recovery_unavailable` are temporary failures; network/UI callers
must preserve the exact pending UUID and text. The client never infers database
capacity, daily eligibility, or the ten-minute stale-recovery condition from a
local count or timeout.

Feedback, feature-feedback, field-note-summary, and prompt-suggestion responses
also require the exact subject echo plus confirmed action-specific evidence.
False `ok` values, mismatched message/rating/sentiment fields, invalid IDs,
empty or UUID-leaking summaries, and duplicate, oversized, unknown-category, or
locally unsafe prompts become `MerianError.invalidResponse`; no success UI is
applied.

## Consent synchronization identity boundary

Session observation never treats assignment of `currentSessionUserId` as proof
that account consent is current. Synchronization first activates the target
ledger with analytics fail-closed, pushes every target-owned pending adult,
Terms, Gemini, and analytics row, fetches the account's authoritative state, and
only then merges. Returning to a previously used account therefore flushes an
offline revocation before remote state can be applied.

The remote read retains current-disclosure rows as evidence but separately
fetches each provider's all-version greatest `consentRevision`. The final merge
uses that provider-wide head—not the version-filtered row—as permission
authority and as the causal parent for the next local action. A delayed
revocation created under older disclosure copy therefore closes Gemini and
PostHog even when a current-version grant is also present locally.

Every network await rechecks task cancellation, the observed account, the
Supabase SDK's synchronous `auth.currentSession` user, and the synchronization
generation. The final merge repeats that complete check inside the mutation
boundary immediately before changing or persisting the ledger or applying
analytics. A stale request can finish at the transport layer, but it cannot
install evidence, change the active ledger, or reopen PostHog for a replacement
account.

Non-cancellation synchronization failure is not remote authority. While a
completed account still lacks current local required evidence, `ConsentManager`
keeps the launch-matched neutral root active, exposes explicit retry, and runs
5-, 10-, and 20-second outer retries. Only the final identity-fenced merge after
verified ledger persistence may resolve to the workspace or Ready consent
screen.

Analytics-consent Realtime owns its requested channel user and confirmed
subscribed user independently of session observation. Failed subscriptions
retain an account-owned bounded retry, while session adoption and foreground
repair ensure the current channel without allowing a stale retry to attach to a
new account.

## OAuth account replacement

Linking an OAuth identity to an anonymous user keeps the same Supabase UUID and
does not replace the account. The provider-conflict fallback and ordinary OAuth
sign-in can install a different UUID, so they use one replacement boundary:

1. synchronously suppress analytics, invalidate stale consent synchronization,
   normalize any canceled same-account restoration wait back to `.reconciling`,
   and stop the prior consent Realtime channel;
2. ask Supabase Auth to install the target session; and
3. reconcile the SDK's actual current session on both success and failure.

The consent transition is generation-fenced. A delayed completion from an older
overlapping sign-in cannot reopen PostHog, restart a stale Realtime owner, or
overwrite `currentUser` after a newer transition starts. A failed replacement
restores the actual surviving session rather than assuming the preflight session
still exists. Provider-bound ghost handoff suppression remains independently
active until its durable queue has been fully reconciled.

## Sign in with Apple revocation credential

The Apple delegate requires both `identityToken` and `authorizationCode`.
Immediately after Supabase installs the permanent Apple session,
`SupabaseManager` sends both values and one registration UUID to the
authenticated `register-apple-revocation-token` endpoint. The same UUID and
payload receive one bounded response-loss retry. Server-side Apple verification
and Vault persistence are mandatory: if registration cannot be confirmed, the
manager clears the newly installed local session and requires a fresh Apple
authorization instead of completing an account that cannot later be revoked.

The manager also observes
`ASAuthorizationAppleIDProvider.credentialRevokedNotification`. It revalidates
the provider-specific Apple subject with `getCredentialState`, confirms that the
same Apple identity is still active when the asynchronous callback returns, and
then clears the local session for revoked, missing, transferred, unknown, or
failed state resolution. An authoritative `.authorized` result preserves the
session. This client transition does not fabricate a server revocation receipt.

## Sign-out and anonymous account transition

User-facing logout is **Sign out**. `ProfileViewModel.signOut()` and the
Settings danger-zone action call `transitionToGhostSession()`; user-facing copy
does not expose internal Ghost or guest-session terminology. Apple, Google, Sign
out, anonymous recovery, Apple credential revocation, and account deletion all
enter one `AuthTransitionCoordinator`. Its operation token owns the source
session, expected destination, phase, and Auth-event generation. A second
operation cannot start while one owns the SDK; late provider callbacks and
wrong-controller Apple callbacks are discarded. SDK events for an unadopted
intermediate or destination session cannot link RevenueCat, refresh entitlement,
write metadata, or change account routes ahead of the operation owner. The
Apple, Google, and destructive-account controls remain disabled for the whole
transition. Unowned account-scoped background work uses the same closed gate.
Every direct Supabase read/write, entitlement refresh, profile/preference
mutation, historical reconciliation, collection sync, and ordinary
`MerianNetworkClient` HTTP attempt acquires an exact-session account-work lease.
The transition closes admission synchronously, cancels and awaits consent
synchronization, closes `InferenceEngine` write admission, cancels and awaits
even non-cooperative presentation/metadata tasks, waits for all admitted leases
and collection work, and only then mutates the Auth SDK session. HTTP retries
release their lease before 401 recovery so recovery cannot deadlock on its
initiating request; payloads that embed an Auth UUID also pass that UUID as an
expected owner and fail before dispatch if the live account differs. Every
recursive transport, route, refresh, and service retry remains pinned to the
account that initiated the request; an unowned request cannot silently recapture
a replacement session. Foreground and background inference keep the request
body, JWT, and expected Auth UUID in one typed request value; the background
dispatcher persists that Auth UUID plus generation in the job metadata and
`inference_v3` task description before resume, then retains the exact account
lease until the URLSession terminal callback. Offline media staging does the
same through `upload_v2`, requires every returned R2 key to equal the prepared
owner key, and retains one exact lease per task through its terminal callback.
The transition drain first commits each affected queue row back to pending and
clears its source-owned staging keys, then cancels every matching task and waits
for both URLSession disappearance and lease release; there is no timeout that
allows Auth mutation to outrun a presigned PUT, and a failed durable retreat,
task cancellation, or bounded drain expiry aborts the transition and leaves the
source session intact for retry. Callbacks and relaunched tasks may mutate local
state only when their explicit owner/generation matches both the live Auth
session and durable job metadata. Before a relaunched terminal callback crosses
its first actor boundary, it atomically reacquires and retains an exact-session
account-work lease, so the transition drain cannot overtake persistence merely
because the original process-local lease was lost. Legacy or unprovable tasks
are cancelled and restaged rather than adopted by a replacement account.
Inference refuses any staged key whose canonical owner differs from its typed
request account. Realtime channels are keyed to the final account and close
while a transition is active. If collection work was already in flight, the
source session remains stable until it finishes, and local tombstones are
retained whenever the transition began before the local commit. Each URLSession
terminal delegate callback registers its asynchronous durable work synchronously
before crossing actors. The background-session `urlSessionDidFinishEvents`
callback waits for that tracker to drain before invoking the system completion
handler, preventing suspension between network completion and final queue/result
persistence. Anonymous bootstrap is itself a coordinator-owned transition, so
restore/create cannot be overtaken by Apple, Google, Sign out, recovery, or
deletion.

Every usable session outside a pending protocol-3 stable sign-out first calls
the additive `/resolve-purchase-principal` route. Its explicit `mode` selects
the stable or legacy branch; only a definite missing route may use legacy
fallback, while auth, timeout, provider, and database failures remain
fail-closed. A fresh anonymous destination owned by a pending stable journal
uses the exact reservation claim below and never enters ordinary resolution.
Once an installation has activated a stable principal, server rollback keeps
returning that exact principal; it never instructs iOS to rotate back to the
current Auth UUID. A response requiring a newer stable protocol also fails
closed until the app is updated. A verified device-only activation fingerprint
makes that transition monotonic: later `404` or `mode: legacy` responses are
rejected rather than used as compatibility fallback.

In stable mode, the client read-verifies a device-only installation capability
and advances/read-verifies its device-monotonic binding intent before each
ordinary resolver request. The server rejects any older intent, so a cancelled
Auth request that finishes late cannot replace the current binding. Stable
**Sign out** uses a separate protocol-3 state machine:

1. While the exact linked source session and binding generation are live, iOS
   generates a rotation UUID and 256-bit secret, persists/read-verifies a
   `preparing` Keychain journal, and invokes `prepare_signout_rotation`.
2. iOS validates the same principal, App User ID, binding generation, and
   server-issued expiry, then persists/read-verifies the `prepared` journal
   before closing the source session.
3. Only one different anonymous identity created no earlier than preparation may
   invoke `claim_signout_rotation`. A prepared reservation blocks generic
   resolver intent and binding writes. Its terminal intent fence also rejects
   any resolver completion begun before preparation after claim, cancellation,
   or expiry.
4. The client validates the atomic claim receipt and advanced generation,
   serially links the unchanged RevenueCat App User ID, requires
   `EntitlementManager.beginSession(...)` to return `true`, revalidates the same
   anonymous Auth generation, and removes the journal last.

An unrelated permanent session, old anonymous session, malformed/unreadable
journal, expired claim, provider failure, or entitlement failure remains closed
and cannot invoke the generic resolver or RevenueCat link. If local sign-out
fails or the exact source is restored first, that source invokes
`cancel_signout_rotation` with the same proof and clears the journal only after
a terminal `cancelled` or `expired` receipt; a `preparing` cancellation safely
tombstones a request whose prepare response was lost. Foreground activation
retries the exact durable destination and proof without creating a replacement
capability or provider customer. There is no `syncPurchases()` or RevenueCat
customer-transfer call. Email, username, display name, avatar, account kind, and
Auth UUID are never written to the shared stable provider customer; adoption
deletes any legacy values and synchronizes that deletion before stable paid
readiness opens. The rotation UUID, raw secret, capability/fingerprint, and
every journal identity field are bearer or identity material and never enter
logs, analytics, crash metadata, or request URLs.

In legacy mode, the client first calls `/transfer-signout-purchases` to snapshot
authoritative StoreKit-backed access and persists its one-use proof under
`Merian_PendingSignOutPurchaseHandoff_v1` with `whenUnlockedThisDeviceOnly`. A
preparation or verified-Keychain-write failure leaves the linked session
untouched. Only then does the client close the local Supabase session and create
one fresh anonymous identity. A linked SDK session is always presented as
linked; the retired `Merian_GhostModeUserID_v1` presentation marker is deleted
during startup and can no longer hide an authenticated account. The anonymous
Profile state offers **Continue with Apple** and **Continue with Google**.

The fresh legacy anonymous identity binds the proof before RevenueCat is linked
to its uppercase UUID. The client then calls `Purchases.syncPurchases()` under
the project's required **Transfer to new App User ID** restore behavior, asks
the server to verify authoritative destination CustomerInfo, refreshes the
Merian entitlement projection, verifies that the same anonymous session remains
active, and removes the proof last. Purchase/restore/redeem admission remains
disabled while that proof exists. Temporary failures retain it and auth-state
restoration retries the same destination. The anonymous Profile also exposes a
visible **Finish sign out** action, so recovery does not depend on a relaunch or
another provider attempt. A restored source account can cancel only a still-
unbound proof; the server refuses cancellation once receipt movement may have
begun. An already-issued compatibility proof always finishes against its exact
uppercase destination UUID even if `principal_mode` changes to `stable` while
the transition is in flight. Only after the proof is cleared may the resolver
adopt/rebind that installation to a stable principal; this prevents receipt sync
and server verification from targeting different customers. If a finite prepared
purchase expires before first completion, the server refreshes the source before
accepting the destination's current StoreKit state, so natural expiry can finish
free without overlooking a source renewal. Completed replay uses the immutable
attested state and snapshot.

While a proof is unresolved, generic auth-state bootstrap and refresh must not
link the anonymous RevenueCat identity early. A confirmed-missing-session `401`
also preserves the exact Auth session instead of rotating or locally clearing
it; an unreadable Keychain proof is treated as pending. Account deletion is
disabled in the UI while any local proof is unresolved. The server rejects
deletion of either side after binding; if deletion wins before binding, bind
fails before RevenueCat is mutated. The database also prevents anonymous cleanup
or profile merge from deleting a bound destination.

Only StoreKit-backed access moves. RevenueCat promotional/beta grants are
account-bound and remain on the linked source rather than being cloned onto a
second customer. The server requires an explicit RevenueCat v1
`store: app_store` purchase record; `store: promotional` and unknown/missing
stores fail closed. Active detached seven-day pass history is accepted only when
the durable database projection confirms the same expiry, preventing refunded
historical purchases from being resurrected.

`SupabaseManager` closes the authenticated-request gate and clears observable
account state before asking Supabase Auth to invalidate the local session. It
cancels its ghost-session and public-author refresh tasks first, ignores late
authenticated SDK events while sign-out is active, and serializes concurrent
sign-out callers through one task. `getValidAuthHeaders()` fails closed during
that interval, checking both before and after asynchronous token retrieval, and
session-refresh retries cannot reopen authenticated state. Explore, Field trip,
and profile Edge requests therefore cannot launch with a token that is being
invalidated.

Low-level `signOut()` cannot later recover the same Supabase anonymous account.
Ordinary user logout therefore calls `transitionToGhostSession()` to request one
replacement anonymous identity after the mode-specific durable boundary is
prepared. Stable success means that replacement Auth session claims the exact
server reservation, links the unchanged purchase principal, establishes a
current entitlement session, and clears the journal last. Legacy success means
the anonymous Supabase identity, exact custom RevenueCat identity, receipt sync,
server verification/reconciliation, and current entitlement read all completed.
An anonymous-session result by itself is not success. The same identity rotation
remains available for stable missing/invalid-session recovery after SDK refresh
fails only when no purchase handoff is pending; a generic `401` never reaches
it. Account deletion intentionally calls `signOut()` alone so it does not
recreate an identity during deletion. `/safe-delete` returns
`409 purchase_continuity_pending` if either side of an active handoff is
targeted; the user must use **Finish sign out** first. The `/safe-delete` call
may return immediate `200` completion or `202` durable acceptance. The shared
request layer strictly decodes the matching status plus the required
`manual_provider_revocation_required` boolean; missing or contradictory receipts
are invalid responses. A legacy Apple disposition is persisted before sign-out
so the app-root manual-removal notice survives local account and SQLite cleanup.
Backend intent and relational cleanup are persisted before the client signs out.
The scheduled account-deletion reaper owns cursor-persisted R2 sweeps, delayed
empty verification, Apple provider revocation when a Vault credential exists,
and terminal Auth removal; a new request therefore normally receives `202`.

This strict receipt and durable notice exist only in supporting binaries. An
older client can ignore `manual_provider_revocation_required`, so publishing the
new build does not prove fallback delivery. Public promotion remains blocked
until an enforceable minimum-supported-build control or an independent
server-delivered manual fallback covers those installed clients.

Account deletion retains ownerless exact scientific facts under the
[`scientific-observation retention contract`](../../../../../docs/backend-and-data/17-scientific-observation-retention.md);
`signOut()` must not imply that every submitted observation is erased. The
provider-specific lifecycle is canonical in the
[`Sign in with Apple account-deletion contract`](../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).
Before `/safe-delete` can commit, iOS generates an atomic Keychain envelope with
independent 256-bit recovery and acknowledgement capabilities and verifies the
exact encoded bytes. It writes `capability_preparation_pending`, performs the
server's non-destructive v2 preparation, writes `capability_prepared_pending`,
then writes `capability_intake_pending` before destructive commit. This closes
both lost-request and lost-response windows: a relaunch from either preparation
phase re-enters the deletion transition; a crash before commit publicly cancels
as `not_committed` without erasing Auth or SwiftData, while a crash after commit
recovers the job receipt. If another device commits first, the database
atomically binds every still-live prepared proof to the same deletion job and
tombstones expired proof hashes as committed. No expired preparation is promoted
into a 180-day recovery capability. While commit is unresolved, the only
permitted authenticated call is an exact-transition replay. If the cached Auth
session is gone, the app submits only the recovery capability to
`/recover-account-deletion`; acknowledgement after verified cleanup uses only
its distinct proof. Neither request contains an account, job, provider, or
purchase identity.

A returned durable receipt promotes the marker to `capability_cleanup_pending`;
only then may iOS sign out locally and purge SwiftData. After cleanup, iOS
acknowledges recovery, records `capability_retirement_pending`,
read-after-delete verifies Keychain removal, and clears the marker last.
Relaunch from retirement re-verifies local Auth absence and repeats the
idempotent SwiftData purge before proof removal, so a marker-writing durability
failure cannot skip either cleanup boundary. A definitive
`409 purchase_continuity_pending` first records
`capability_rejection_retirement_pending`, then read-after-delete verifies the
unused proof is gone, and clears the marker last. Relaunch in this phase
performs only that proof-and-marker retirement; it never signs out or purges
local data because the server proved the deletion intake did not win. Transport,
Auth, gateway, `5xx`, cancellation, and malformed responses retain the proof and
barrier because commit may still be in flight. An unknown legacy v1 proof also
remains ambiguous. An unknown v2 proof permits proof-only retirement because
commit requires the missing server preparation. A `not_committed` or genuinely
unknown v2 proof first retires the unused proof, then adopts only the exact
cached unexpired Supabase session into the transition coordinator while the
barrier remains. It clears the barrier before publishing that same UUID and
anonymous/account kind or reopening account work. The distinct
`account_deletion_recovery_preparation_expired` response is a non-authorizing
tombstone match and retains the barrier. Only a matched committed capability's
`account_deletion_recovery_expired` `410` is positive evidence that deletion was
accepted; it permits conservative local erasure, after which the independent
acknowledgement proof remains valid and then permits verified retirement. It
does not reveal pre-cleanup job state. Legacy `intake_pending` and
`cleanup_pending` remain readable during the installed-client compatibility
window. No marker or proof stores an account, provider, job, or request
identifier. A refreshable `401` renews only the transition's exact expected
Supabase session; it cannot start nested recovery or relink RevenueCat,
analytics, profile metadata, or entitlements.
