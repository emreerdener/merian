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

`MerianSupabaseClientFactory` enables
`emitLocalSessionAsInitialSession`. The pinned Supabase Swift SDK therefore
emits the cached session immediately, including a session whose access token is
expired, and refreshes an expired session in the background. `SupabaseManager`
classifies the initial value before mutating observable auth state:

- no session is `.signedOut` and may resolve required-consent restoration as
  unauthenticated;
- a non-expired session is `.authenticated` and may start entitlement,
  identity, and synchronization work; and
- an expired session with a user is `.awaitingRefresh`. Authenticated request
  state remains closed and `currentUser` remains unset, but the known user ID is
  passed to `ConsentManager` so a completed user stays on the launch-matched
  restoration root.

The SDK's later `tokenRefreshed` event adopts the valid session through the
normal authenticated path. A terminal refresh-token cleanup emits `signedOut`
and only then establishes that no active account remains. Never route an
expired cached session through sign-out cleanup: doing so can briefly resolve
restoration and mount the Ready approval screen before refresh completes.

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
- Maps only handler-owned HTTP `403` with stable code
  `ai_consent_required` to `MerianError.aiConsentRequired`. That is a
  disclosure transition—not quota exhaustion or generic authorization—and
  foreground callers must preserve the queued scan while the account returns
  to Ready. `402 pro_required` and the `429` quota/rate codes remain separate.
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

`MerianNetworkClient` performs the request. `FieldTripCaptureGoalProvider` maps
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

Before Field Chat presentation,
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

Field Chat responses are decoded through one strict path for both Insight scans
and Explore posts. Every envelope must echo the requested scan/post through
`subject_id`, including when the thread is empty. Every message must have a
unique UUID, match that same subject through `scan_id`, match the envelope's
valid conversation UUID, contain trimmed/nonempty text bounded to 4,000
characters, and fit the exact v1 server limits. Field Chat JSON is rejected
above the reviewed 1 MiB decode ceiling. A send response must also contain
exactly one user message and one assistant message carrying the requested
`client_message_id`, and the acknowledged user row must contain the exact
trimmed text that was sent. Invalid, contradictory, or incomplete envelopes
never reach `InsightChatViewModel.apply`; failed sends remain retryable under
the same canonical lowercase idempotency UUID rather than clearing the pending
question or creating a duplicate on manual retry. A backend
`field_chat_idempotency_conflict` means that UUID was reused for edited text and
is never treated as confirmation of either send.

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
acceptance. The shared request layer strictly decodes the matching status plus
the required `manual_provider_revocation_required` boolean; missing or
contradictory receipts are invalid responses. A legacy Apple disposition is
persisted before sign-out so the app-root manual-removal notice survives local
account and SQLite cleanup. Backend intent and relational cleanup are persisted
before the client signs out. The scheduled account-deletion reaper owns
cursor-persisted R2 sweeps, delayed empty verification, Apple provider
revocation when a Vault credential exists, and terminal Auth removal; a new
request therefore normally receives `202`.

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
