# Insight Chat

The `Chat` directory contains the logic and UI for the Pro-tier Field Chat
feature.

## Purpose

This area allows Pro users to ask contextual follow-up questions about a
completed biological scan without needing to re-upload raw images. It also
provides the shared presentation and floating control used by private per-viewer
chats on every visible Explore post, including the viewer's own posts. Insight
conversations use owner-only scan context; Explore conversations use only the
privacy-filtered public post and Species Dictionary projection. Loaded in-app
Species Dictionary pages use a third source grounded only in the latest bounded
canonical dictionary text. All three use Gemini 2.5 Flash and smart prompt
chips.

Generated Insight prompt chips are merged with deterministic local fallbacks,
deduplicated, and filtered against pending or previously sent questions. For an
identification below 70% confidence, the three-chip result reserves a
confidence-category slot. An available server confidence prompt owns that slot
even when it arrives after three ordinary suggestions; otherwise the local
uncertainty fallback does. This prevents evidence, ecology, or seasonal
suggestions from crowding out the observation's uncertainty context.
Explore-post prompt chips do not use private scan confidence and retain their
separate public fallback behavior. Species Dictionary chips use the same
confidence-free deterministic fallback and bounded server labels.

For Explore posts, the empty state uses the concise trust message
`This Field chat is private and visible only to you.` The conversation is never
shown to other viewers. Technical context limitations remain enforced by the
backend and documented in the API contract instead of being presented as
additional empty-state disclaimers.

## Connectivity Ownership

`InsightChatViewModel` consumes connectivity state; it does not create or own an
`NWPathMonitor`. Insight, Explore-post, and Species Dictionary hosts project the
existing app-scoped `OfflineQueueManager.isOnline` value into their chat view
model and apply its initial value when the host mounts. This keeps one
reachability authority for the process and prevents transient SwiftUI view
construction from repeatedly starting and canceling path monitors. Offline state
disables new sends without clearing an already-loaded private thread.

## Owned Insight Readiness

Insight Field Chat depends on the exact authenticated-owner `public.scans` row;
a locally completed `LocalScanRecord` alone is not sufficient. A valid toolbar
tap presents the Field Chat shell immediately, where a loading state calls
`ensureCloudScanAvailableForFieldChat(scan:expectedScanId:)` before the first
`/insight-chat` request. A successful readiness result flows directly into chat
loading instead of paying for a redundant second status request.

Both client presentation and the `/insight-chat` server boundary require a
resolved, non-Human biological taxonomy. The endpoint checks the confirmed
species relation first, rejects unresolved placeholders and `Homo sapiens`
(including legacy `Homo sapien`), and does not rely on a hidden toolbar action
as authorization.

The completed engine result is the presentation authority. Any cached local
record model, record ID, and toolbar snapshot must match that exact scan ID
before the action is enabled. The preflight independently rejects a mismatched
record, captures the selected chat scan ID, and revalidates it before and after
every asynchronous readiness step. The sheet uses that captured ID instead of
rereading a mutable engine ID; an engine scan change dismisses the sheet. A
delayed preflight therefore cannot recover one observation and populate another
observation's private thread.

Queued and completed presentations intentionally reuse one scan UUID. Promotion
advances the Insight presentation generation, and the delayed bottom-toolbar
task is keyed to that generation rather than the UUID. This guarantees Field
Chat is revealed for the completed record even when queued-state invalidation
canceled the prior toolbar task, while still rejecting every callback captured
by the queued presentation.

`InsightChatViewModel` provides a second subject boundary at presentation. The
toolbar activates the captured subject before making the shell visible, so a
different scan's in-memory transcript cannot flash during readiness. Opening a
different scan/post/species advances a subject generation, invalidates the prior
load and prompt tokens, and clears the prior private transcript, pending
message, draft, feedback, and note-summary state before the new request starts.
Load, send, delete, feedback, feature-feedback, summary, and prompt completions
must still own that exact subject generation before changing visible state.
Cross-subject availability preparation cancels and replaces the older request
instead of making the new chat fail merely because an obsolete preflight is
still running; same-subject requests remain single-flight. Even a
network-validated response is applied only when its exact `subject_id` also
matches the active generation. A late completion can therefore never replace
another observation's thread or copy its private draft into the new composer.
The parent Insight sheet applies the same scan/generation check to readiness
failure toasts, paywall routing, unavailable-state dismissal, explicit close,
and chat-provided toast callbacks. A callback owned by an older sheet therefore
cannot close, toast over, or reroute a newer observation's Field Chat.

Chat-to-alternatives, chat-to-reanalysis, and Pro-paywall follow-ups are typed
`InsightChatDismissalAction` values. `InsightSheetView` records the action,
closes Field Chat, and resumes it only from the chat sheet's exact `onDismiss`.
The captured scan ID and presentation generation are checked again before the
candidate modal, refinement route, or paywall can mount. Field-note confirmation
and copy acknowledgement timers are identity-keyed SwiftUI `.task` work, so
unmounting the chat cancels them. Copy acknowledgement stays inside
`InsightChatAnswerControls` as the transient `Copied` badge and never calls the
parent `onToast`; this shared rule covers Insight, Explore, and Species
Dictionary threads. The separate field-note confirmation toast cannot block
underlying controls.

The preflight:

1. polls `/check-scan-status` using the stable scan UUID;
2. returns immediately when the exact owner row is found;
3. leaves processing, finalizing, retrying, and retryable server ingestion under
   server ownership;
4. refuses known moderation, provider-safety, deletion, and ambiguous terminal
   state; and
5. for eligible historical drift only, builds a bounded non-media
   `OwnedScanRecoveryPayload`, submits it through single status recovery, and
   requires a final owner `found` response.

Recovery resolves the server species ID by scientific name and derives owner
from the current persisted Auth session. It never sends raw image/audio/video
bytes, local paths, object keys, direct cloud URLs, or a client-selected owner.
Field Chat does not restore or publish public media.

If status remains transiently unavailable, the button stays available for a
later retry and the user sees:

`This observation is still syncing. Please try Field chat again in a moment.`

Do not cache this result as permanent unavailability. A current Identify `200`
followed by this preflight returning missing is a severity incident because
durable owner read-back is part of Identify success.

`InsightChatViewModel` must make the same distinction after preflight. It stores
permanent `unavailableScanId` only for terminal ownership failure,
`unsupported_scan`, an unavailable Explore-post source identified by
`post_not_available`, or an unavailable dictionary subject identified by exact
`species_not_available`. Owned-scan `scan_not_ready`, action-level
`message_not_found` / `conversation_not_found` from either source, and a plain
status `not_found` remain retryable and must not hide the toolbar action.
`stillSyncingMessage` is the single client copy for this state.

Video owner readiness follows the canonical media timeline: one ready playback
clip and its poster, not separate ready image rows for sampled inference frames
retained in compatibility storage. The client does not manufacture frame media
to make Field Chat available; backend finalization migration
`20260729012153_fix_video_scan_canonical_finalization.sql` restores the shared
completed prerequisite while keeping Field Chat context text-only.

Platform route failure is distinct from a handler-owned missing scan.
`MerianError.edgeFunctionUnavailable` uses temporary service-unavailable copy
and must not enter owner-row recovery.

Every chat HTTP `200` is candidate evidence, not completion by itself. Before
the view model replaces the visible thread, the network client requires an exact
top-level `subject_id` echo even for an empty thread, valid v1 contract limits,
unique UUID message IDs, one valid conversation UUID when messages are present,
an exact subject match on every message, trimmed/nonempty message text no longer
than 4,000 characters, and a JSON body no larger than 1 MiB before decoding.
Insight messages must reference the requested scan; Explore and Species
Dictionary messages must reference the requested post/species through the
compatibility `scan_id` field. A send success additionally contains exactly one
persisted user message and one persisted assistant message carrying the original
`client_message_id`; its user row must acknowledge the exact trimmed question
sent. Malformed, incomplete, cross-subject, or cross-conversation payloads
become `MerianError.invalidResponse`. A failed send therefore remains visible
with retry/edit recovery instead of clearing the pending question or displaying
another thread.

`PendingInsightChatMessage.id` is the send's durable idempotency UUID. Automatic
network replay and `retryFailedMessage` must reuse it in canonical lowercase
form; a manual retry must never allocate a new UUID and insert a duplicate
question. Insight and Explore are currently in the audited automatic-replay
allowlist. Dictionary requests send the same idempotency header, but the current
candidate does not yet allow automatic ambiguous replay for
`species-dictionary-chat`; adding that route and proving a lost-response/`5xx`
retry returns one saved pair is a client-release blocker. Reusing the UUID for
edited text is a server-confirmed `field_chat_idempotency_conflict`, so Edit
intentionally starts a new send UUID. The backend coalesces an in-flight quota
replay into the exact saved pair or returns retryable
`field_chat_send_in_progress`. It reserves both persisted rows within the 30-row
conversation cap and gives the assistant a deterministic row identity,
preventing concurrent or ambiguous persistence from duplicating an answer.
Database admission is authoritative across devices and all three chat families:
it serializes the shared 20/day count, conversation capacity, and the user-row
insert. `field_chat_admission_unavailable` and `field_chat_recovery_unavailable`
are retryable failures, never permission to clear the pending bubble or create a
replacement UUID. A quota-committed unanswered request can be reopened only by
exact server proof after ten minutes; iOS does not calculate or assume that
state.

The 20/day count must survive deletion of retained conversation content. The
current backend candidate counts live user-message rows and cascades them on
conversation deletion, so it can restore same-day allowance and remains
release-held until durable admission accounting and delete-then-send tests pass
for all three sources.

Migration `20260730180000_bind_field_chat_rows_to_subjects.sql` makes the same
identity rule structural for retained server data. Every retained Insight
conversation is a deferred composite child of its exact scan owner, each message
is a child of its exact `(conversation, scan/post, user)`, and each answer
rating is a child of its exact copied message identity. Sheet-level feature
feedback remains independently bound to its exact scan owner even when it has no
conversation context. This remains compatible with the transactional
anonymous-account merge while preventing a malformed historical or future
service write from poisoning the whole strictly decoded thread. Insight
answer/feature-feedback tables are Edge-only as well; iOS must never bypass the
chat endpoint with direct Data API writes.

Migration `20260821030027_add_species_dictionary_field_chat.sql` adds the
equivalent Edge-only composite bindings for dictionary conversations, extends
atomic admission and stale recovery to the third subject type, and includes
these conversations in anonymous-account linking.

On load, `reconcileThread` distinguishes a completed historical user/assistant
turn from the latest unanswered UUID-bound user row whose answer never
persisted, even if a filtered orphan assistant follows it. That unanswered row
is removed from the delivered transcript and restored as the failed pending
bubble with its canonical UUID, text, timestamp, Retry, and Edit actions.
Orphan/duplicate UUID-bound assistant rows are not displayed. The separate
persisted-row count still controls composer capacity, so hiding an interrupted
row cannot create a local 29-row off-by-one send.

Action responses use the same subject rule. Answer feedback requires the exact
scan/post/species echo, `ok: true`, and the requested message UUID and rating;
feature feedback requires the exact scan echo, `ok: true`, a valid
saved-feedback UUID, and the requested sentiment. Field-note summaries must echo
the scan, be nonempty and bounded, and remain free of canonical internal UUIDs,
including UUIDv7. Prompt suggestions echo their scan/post/species and are
limited to three unique, trimmed, 120-character allowlisted safe prompts with an
optional valid conversation UUID. Invalid best-effort suggestions fall back to
local chips; invalid feedback or summaries never show success.

Send-time and prompt safety match unsafe action intent rather than isolated
words. Direct requests to harvest or handle the observation remain blocked,
while educational questions about poison ivy habitat, tea plants, animal
foraging, bee stings, or why handling is discouraged are not discarded or
automatically refused merely because they contain a safety-adjacent word.

## Context and Privacy

Owned Insight chat uses only saved owner text evidence. Explore-post chat is a
separate per-viewer source that uses only the privacy-filtered public post and
Species Dictionary projection. Dictionary chat uses only canonical names,
taxonomy, overview, habitat, hazard, conservation, group tags, and lookalikes;
it excludes sightings, observation charts, scans, notes, users, locations,
media, URLs, and attribution identities. No source receives raw media or exact
GPS. Dictionary product telemetry omits species names and UUIDs.

Before release, Dictionary refusals must be generated from source-specific copy
instead of partially replacing scan wording, and local fallback prompt chips
must normalize and bound the display label exactly like server suggestions. The
current candidate does not yet meet either requirement.

See:

- [`insight-chat` route contract](../../../../../../services/supabase/functions/insight-chat/README.md)
- [`species-dictionary-chat` route contract](../../../../../../services/supabase/functions/species-dictionary-chat/README.md)
- [Scan ingestion reliability and recovery](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#field-chat-readiness)
- [Insight sheet architecture](../../../../../../docs/features-and-hardware/05-insight-sheet.md)
