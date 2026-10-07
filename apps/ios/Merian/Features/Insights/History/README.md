# Identification history

Prepared history presentation. Normal Shell access remains nil: the App
installation boundary is fixed false and does not construct the prepared bundle.
Only explicit test injection currently opens this screen. When qualified, all
Insight hosts receive History, status and saved-result entry together from the
same App-owned bundle as Capture; reading history never enrolls an observation.

- `Models` maps each result's own display and authority to bounded rows/details.
- `Services` owns the account-session adapter to Core listing, preview,
  selection/Undo and private image resolution. It never writes projections.
- `ViewModels` owns one page, one preview, pending/retry state, receipt-bound
  Undo and cancellation. Acknowledged state changes alone refresh the parent
  Insight and invalidate authority-bearing rows/details. Delayed pages/previews
  must still match current context before presentation; selection acknowledgment
  refreshes the newest bounded page without making its success depend on that
  read.
- `Views` renders a native list/preview in Shell's existing modal slot. Opening
  a row never chooses it; Use this identification is explicit.

Back cannot abandon an active selection dispatch. Optional alternatives from an
incompatible legacy candidate schema are omitted without blocking a valid saved
identification preview.

Core owns persisted fences and selection transactions. Shell owns
scan-generation admission and teardown; Toolbars receives only an optional
action. There is no ordinary enrollment, sync scheduling, public update or
reanalysis activation in this feature.

A prepared access assembler may explicitly inject `AppRouteRequesting` through
`prepared(routes:)`. Its callback constructs only the exact
`historicalReanalysis` route with `internalUserAction` origin. Only then does a
validated preview expose **Reanalyze from this identification**. The session
derives capability from the exact immutable local source and current
owner/context, independently of current selection and inference consent. Missing
source, pending selection or invalid context hides the action without removing
read-only preview. The action never calls ordinary refinement, funding,
selection or inference.

Shell stages one handoff with the originating scan and presentation generation,
then dismisses the nested sheet. Its exact dismissal callback consumes the
handoff once, revalidates account generation, observation context and immutable
source, and invokes the injected historical route callback. Root routing then
owns dismissal of Insight before opening Capture. Changed parent presentation,
account, revision, deletion or source suppresses dispatch; no delay timer is
used. The handoff retains immutable values and no account-work lease. Dismissed
history closes its session and private presentation; an explicitly staged action
has its own bounded validation closure for the dismissal boundary. Ordinary
history and Capture access remain nil. UI fixtures contain synthetic values and
call no live provider.

The canonical
[product and lifecycle contract](../../../../../../docs/features-and-hardware/05-insight-sheet.md#prepared-identification-history-sheet)
owns paging, offline limitations, preview content, memory limits and user copy.
The
[Core boundary](../../../Core/Data/AnalysisHistory/README.md#prepared-bounded-listing-and-presentation)
owns persistence and authority. Verification lives in
`IdentificationHistoryViewModelTests`, `IdentificationHistoryReanalysisTests`,
`ObservationHistoryListingTests` and `IdentificationHistoryUITests`; the runtime
audit manifest registers the UI flow.

## Prepared reanalysis status

`ReanalysisStatusAccess` is a separate optional Shell entry, independent of the
history menu's multiple-result condition. It reuses
`IdentificationHistorySession` for owner/session/generation checks but exposes
only Core's bounded operation pages. A page with omitted rows and a continuation
still offers access to later pages; it does not prove those unseen rows are
active requests.

`ReanalysisStatusViewModel` retains only one page of closed status summaries and
cancels and clears them on account, parent or presentation invalidation. The
native `ReanalysisStatusSheet` offers refresh and bounded paging, with distinct
consent, unavailable-evidence, reconciliation, retry-limit and terminal-failure
copy. It has no admission, retry, discard, source-photo or provider action.
Refresh reads status only. Completed identifications remain in history and
current selection is unchanged. Ordinary `reanalysisStatusAccess` remains nil.
`ReanalysisStatusViewModelTests` covers single-result availability, corrupt-page
continuation, exact session reads, late-result rejection and
account/parent/generation teardown. Core `ReanalysisOperationStatusTests` covers
disk restart and distinct inert holds.

The App-owned prepared composition can supply an explicit cloud and session
factory to both access values. Availability and opening validate that session;
listing uses the same cloud instead of a global client. History photo delivery
uses its injected resolver/downloader as well. The default prepared convenience
remains for existing explicit fixtures; ordinary live access stays nil. Opening
or probing either menu never enrolls a scan or requests inference consent.

## Prepared saved-result entry

`SavedIdentificationReanalysisAccess` is a separate explicit-tap capability. The
App composition supplies its cloud/account, enrollment owner and current
container predicate. Preparing a request freezes the displayed correction before
suspension. A legacy scan enrolls through the retained owner using that exact
ticket; the returned baseline analysis ID is revalidated without changing
selection. An enrolled scan freezes its selected source and acknowledged
revision immediately. Both produce a final synchronous source-qualified action,
so selection, authority, source deletion or account changes prevent dispatch.

This path requires no inference consent merely to open the editor. Submission
and execution retain their own consent/funding checks. It never borrows mutable
parent media, retries inference, or falls back to legacy refinement. History and
status reads never invoke enrollment. Ordinary access remains nil.

`SavedReanalysisHandoff` owns one prepared request and cancellable UI waiter per
parent Insight. Child presentations retain revocable tickets that reference the
owner weakly, not the private request. A ticket resumes at most once; an old
ticket cannot resume or cancel newer work. Parent cancellation drops pending
private state while durable enrollment remains owned by QueueManager.

Each child-local ticket owner cancels and clears its pending handle on
disappearance, including removal before a nested dismissal callback. Forwarding
clears local state first, so disappearance cannot cancel a request already
passed onward. Parent cancellation also clears its pending chat ticket.

## Prepared analysis review controls

An explicitly composed preview may offer confirmation, an incorrect mark and
receipt-backed Undo for that exact historical result. The immutable primary's
scientific name labels primary confirmation; a mutable row title never labels
its target. Explicit species-name input uses the same bounded request validator.
Capabilities come from explicit biological/primary evidence and current
result-specific authority, including eligible imported results.

`IdentificationHistoryReviewModel` freezes the request and operation UUID and
stages it synchronously at the button callback, before the injected queue wake.
It retains the exact request after an uncertain save, including when status is
nil or unreadable. Retry saving reuses that request. A held operation never
rearms from this UI. Undo rechecks the completed applied same-target Reject
receipt and current association at the actual tap.

The App-owned composition injects local admission/status, queue wake and the
observable actual-pass-exit generation. The generation only prompts an
owner/parent/child-scoped local refresh; it is not a receipt or authority. No
idle polling or retained Auth lease is introduced. Returning to the foreground
also checks local state. Pending work on another result blocks new decisions for
the observation. Fresh checks fence restore, selection Undo and reanalysis,
including the historical route's final handoff.

Back, close, paging, revision and account changes invalidate the nested model.
Terminal negative receipts require a new preview even when the local revision
has not changed. Completion does not select an identification. Ordinary access
and the atomic App installation gate remain disabled. Tests cover synchronous
admission, uncertain-save identity, stale receipt Undo, held work, other-target
blocking and nested lifecycle teardown in
`IdentificationHistoryReviewModelTests` and
`IdentificationHistoryReviewLifecycleTests`.

## Prepared community-help consent access

The inert App composition explicitly injects the retained preparation owner,
fixed owner-bound preflight fetch, queue wake and actual-exit generation into
its existing History session factory. `IdentificationHistoryPublicationAccess`
exposes exact-ticket preparation, synchronous final-acceptance persistence and
owner/parent/child/operation status. Construction and opening perform no
preflight or publication. Ordinary session dependencies remain nil.

Shared preparation checks the common account/session/container environment; the
waiter separately checks its presentation after the await. Closing one sheet
therefore withholds its private result without poisoning another joined sheet.
Final consent still requires explicit ordered media acceptance, and the caller
must retain that Acceptance across uncertain saves. Status is a local operation
receipt, never public visibility. The existing exact private-photo loader
remains the image boundary. The prepared consent UI below consumes this access;
ordinary access and all activation gates remain false.

## Prepared photo consent presentation

The injected History preview now offers an explicit community-help flow through
`IdentificationPublicationModel`. It first checks local and remote observation
requests. Occupied or uncertain targets cannot prepare a new request; a remote
null alone is not consent. A fresh vacant target can explicitly prepare its
frozen ticket and choose one to six photos from the complete candidate list.
Selection starts empty and preserves the user's selection order. A single
bounded preview uses the exact historical analysis/media loader; parent media
and private notes are never borrowed. Final sharing confirmation creates and
synchronously saves one immutable Acceptance before delivery wakes.

`PublicationConsentContinuation` lives in the parent Insight presentation. It
retains an unacknowledged Acceptance across History back, dismissal, reopening
and authority changes. Different historical results cannot replace the held
observation-wide request. Exact saving retries use the original UUID and ticket;
status recovery never adopts a remote request or authorizes a replacement.
Successful staging transfers recovery to the durable operation and retains a
minimal settled-operation marker so another open chooser cannot mint again.
Actual parent teardown, account/container change and confirmed deletion clear
private continuation state; generic view disappearance or revision refresh does
not.

Saved status refresh uses the injected delivery-exit generation and foreground
opportunities, without timers or idle account leases. A historical admission is
not presented as proof of public visibility. Ordinary access and every
activation gate remain disabled.

The selected Insight entry reuses its retained History session and frozen review
ticket through `SelectedAnalysisReviewHost`. Toolbar, biological content and
nested confidence/candidate actions prepare a one-use `CommunityConsentTicket`
at the actual tap, before child dismissal. Resuming validates the original
binding token, both presentation domains, container and displayed authority; it
never opens a replacement session or substitutes a newer selection. The native
`IdentificationPublicationSheet` consumes the same consent model and parent
continuation as History. Protected scans with missing access remain withheld;
unenrolled scans retain their fenced legacy route. Closing the sheet clears its
private presentation, while an uncertain Acceptance remains parent-owned.

### Photo-consent UI verification

The Debug-only `-seedPublicationConsentChooser` scenario seeds two decoded V2
results and their selected authority in SwiftData. Its retained fixture supplies
strict synthetic account, history, preflight, recovery and private-photo
boundaries; the visible chooser uses production preparation and durable staging.
The UI scenario chooses the second photo before the first, previews exact
private evidence, saves, then reopens from selected Insight and a different
History result. The fixture's local wake verifies one durable request with that
order, no notes and unchanged selection. It never schedules delivery or enables
ordinary access. The selector is owned by
`scripts/config/ios-runtime-audit.json`.

### Selected broader-taxon name confirmation

Selected Insight uses the same retained review model for explicit species-name
confirmation when the immutable primary cannot be confirmed directly. Its shell
owns the temporary `SelectedAnalysisNameConfirmation` form and
identity-qualified dismissal. Opening or editing does not create a request;
final confirmation validates the captured ticket and synchronously stages one
exact operation. Closing the form preserves the host's uncertain request for
retry. The dedicated Debug chooser fixture also covers a genus result and
verifies production review staging, original revisions and unchanged selection
without delivery.

## Durable confirmation Undo

Existing review controls accept primary/name confirmation reversal through the
same durable review owner. Presentation-scoped eligibility can come from a
completed local receipt or exact server recovery after reinstall; recovered
admission never fabricates or requires a local original receipt. A retained,
max-four lookup owner drains account leases before Auth transition. Imported
confirmations without exact receipts explain their unavailability. Named Undo
warns that the original AI identification returns; primary Undo is direct.
Selection and the alternatives card are unchanged.

Explicit opening and every staging attempt (including an uncertain save) request
one persisted-job discovery wake. Status refresh/render does not wake or poll.
Commit-then-throw followed by reopening observes and resumes the original UUID;
held jobs never rearm automatically. The Core transaction remains the final
scope/authority check, with no optimistic review mutation or legacy fallback.

A closed presentation cancels its waiter and withholds the result. It does not
cancel a shared lookup needed by another presentation. The retained owner keeps
at most four scopes until actual completion, uses a five-second RPC timeout, and
cancels/awaits account leases at both Auth teardown boundaries. It owns no idle
polling lease. A full owner can reject another lookup until a slot exits; that
does not authorize a different confirmation or a new mutation.

See
[confirmation Undo verification](../../../../../../docs/development-guides/08-testing-strategy.md#durable-confirmation-undo-verification)
for exact tests, including six primary/name Undo UI paths and cancellation of
one joined presentation while another completes. Older named-confirmation and
chat UI smokes exercise different actions. Ordinary access and the independent
API gate remain disabled.

## Recovered rejection Undo

The existing incorrect-mark controls can resolve the original rejection after
reinstall through an exact, read-only server lookup. The retained
`ObservationRejectionUndoOwner` coalesces at most four account/session/container
and displayed-ticket scopes; both Auth teardown boundaries cancel and await
actual lease release. Closing one presentation cancels its waiter, not another
presentation's shared lookup. There is no idle lease, timer or automatic lookup
retry.

A completed local rejection receipt remains the first eligibility source. A
strict server reply can instead produce typed recovered eligibility without a
local original rejection job. Fresh staging reconstructs the exact ticket and
rechecks owner, deletion, idle selection, settled legacy review, unfinished
operations and the current rejection association in the transaction. The server
revalidates the original applied rejection against current outer target-review
revision; its older observation revision and the independent nested AI counter
do not invalidate an otherwise current rejection.

Exact persisted Undo requests replay before fresh eligibility. Reopening and
save uncertainty discover the original durable job; neither creates a
replacement UUID nor automatically rearms a held operation. Lookup failure or a
changed record explains unavailability and never enables a legacy mutation. Undo
restores unreviewed AI authority without confirmation, evidence replacement or
selection change. This composition remains inert while ordinary access is
disabled.

## Immutable candidate correction foundation

`ObservationAnalysisReviewTicket.candidateChoices` derives alternatives directly
from the saved result, pairing each display value with its original raw array
ordinal and analysis ID before filtering or reordering. Only the supported
species-ranked V1/V2 representation is eligible. Duplicate scientific names
remain distinct members; display labels and mutable parent candidates never
establish membership.

The handwritten review request emits schema 2 only for `confirmCandidate`, with
an exact nested reference and the original scientific name. Existing schema-1
requests remain unchanged. Fresh admission reconstructs and compares the whole
displayed ticket, including immutable result bytes, before saving. Durable
fingerprints, claims and receipts retain the reference across restart; a
name-only request or different ordinal cannot replace that operation. Candidate
corrections remain `confirm_name` authority for confirmation Undo, which
restores the original AI identification without changing selection.

This foundation does not yet connect the alternatives UI. The legacy swipe
session uses scientific names as identity and cannot carry protected provenance.
Its card design and layout remain unchanged; protected wiring must retain the
exact choice through the existing review owner and final synchronous admission.
