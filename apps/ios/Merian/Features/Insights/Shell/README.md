# Insight Shell

The `Shell` directory acts as the root container and primary structural layout
for the Insight sheet.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the
assembly of the various insight components (`Media`, `Content`,
`IdentificationReview`, `FieldNotes`, `Sharing`, `Toolbars`) into a single
cohesive scrollable view. It handles the lifecycle and presentation state of the
sheet without embedding deep domain logic.

The canonical product and lifecycle contract is
[Insight Sheet](../../../../../../docs/features-and-hardware/05-insight-sheet.md);
typed cross-feature presentation ownership is documented in
[Event and Presentation Routing](../../../../../../docs/system-architecture/10-event-and-presentation-routing.md).

## Ownership

The Shell uses responsibility-specific implementation folders:

- `Models` owns deterministic presentation identities, binding keys, and display
  values. It does not import SwiftUI or UIKit.
- `Services` owns `InsightShellDependencies`, the only Shell declaration that
  resolves live network clients, repositories, app routing, authentication,
  feature access, badge updates, or haptic feedback. The dependency value uses
  narrow initializer-injected closures rather than a feature-wide protocol or
  singleton.
- `ViewModels` owns scan-bound state and lifecycle, record, capability, media,
  content, and presentation projections. View-model files consume injected
  dependencies and make no direct endpoint calls.
- `Views` owns the root composition, content and Shell presentation hosts,
  presentation bindings, lifecycle attachment, toolbar assembly, content/toast
  routing, and UI-only dismissal timing.
- `Components` owns Shell-only leaf presentation such as the first-render probe.
- `Modifiers` owns embedded navigation behavior shared by Shell views.

The responsibility splits are explicit rather than another aggregate:

- `InsightSheetViewModel.swift` owns stored scan-bound state, initialization,
  reset, and `UIState`.
- `InsightSheetViewModel+Lifecycle.swift` and `+Records.swift` own lifecycle and
  local-record mutation/handoff behavior.
- `+Capabilities.swift`, `+ContentPresentation.swift`,
  `+MediaPresentation.swift`, and `+PresentationIdentity.swift` own pure or
  state-derived capability, display, media, and identity projections.
- `InsightSheetView.swift` and `InsightContentView.swift` remain the stable root
  compositions. Their `+Presentations`, `+PresentationHost`, and
  `+PresentationBindings` extensions serialize modal ownership; `+Lifecycle`,
  `+Toolbar`, `+ChatActions`, `+Content`, and `+ExploreComposer` retain the
  corresponding view-owned timing and action adapters.

`InsightSheetView` and `InsightContentView` retain their existing initializer
and presentation contracts. Their source is split into focused extensions so no
production Shell Swift file exceeds the 600-line review guard. Views retain
gallery selection, sheet ownership, scroll state, and dismissal timing; those
states must not move into the view model merely to reduce file size.
`InsightSheetView` and `InsightSheetViewModel` accept an optional trailing
`InsightShellDependencies`; `nil` resolves `.live`, preserving every existing
call site while focused tests inject deterministic closures. The view model's
existing product-area dependency slots now also include
`InsightFieldNotesDependencies`; Field Notes owns that closure value and its
live repository/haptic resolution under `FieldNotes/Services`, not in Shell.

Tests mirror these owners under `MerianTests/Features/Insights/Shell`, with
presentation-specific suites retained under `Content`, `FieldNotes`, `Media`,
and `Sharing`. `InsightShellArchitectureTests` enforces the folder shape,
deterministic Models boundary, live-resolution boundary, absence of direct
network clients in views/view models, removal of the former source and test
aggregates, single-owner modal/embedded dismissal, and the 600-line ceiling.

## Presentation Modes

`InsightPresentationStyle.sheet` is the ordinary modal presentation.
`embeddedInScansLibrary` hosts the same Insight content as a pushed destination
inside an existing navigation stack and owns its back arrow/back-swipe behavior.
Dismissal has exactly one owner per mode after the presentation session is
ended: modal Insight calls the environment dismiss action, while embedded
Insight writes `false` through its route binding. A close path must not emit
both signals, because the root router may advance to a queued presentation while
the previous dismiss action is still unwinding. `ScanInsightRoute` carries only
the stable scan ID. Route tap handlers must not load `InferenceEngine` before
mounting a sheet or navigation destination. `LocalScanInsightLoader` commits
that presentation first, performs one fetch-limited local-record lookup, and
then hydrates the engine before it constructs `InsightSheetView`. A record
deleted during the handoff renders **Scan unavailable** instead of stale Insight
content. The sheet's normal record binding recognizes that exact already-loaded
scan and does not cancel and restart its hydration.

The Scans library also uses the embedded mode for queued and staged scans. Their
private navigation route retains `QueuedScanContext`, a value snapshot that
remains safe after the backing queue model is deleted, allowing upload,
analysis, and completed results to transition within one pushed destination.

A live-to-queue transition uses `queuedPresentationScanId` only as an exact-ID
lookup key. The view model fetches and snapshots that matching durable row; it
must never bind the first pending scan, retain a live SwiftData model across the
sheet boundary, or allow scan A's delayed fetch to replace scan B. During that
exact same-scan handoff, the view model continues presenting the engine's
in-memory carousel until the completed result replaces it. This prevents the
durable media snapshot from remounting the visible capture mid-analysis. The
analyzing pill likewise receives the engine's ephemeral contextual phrase deck,
with its current phrase first and every unseen phrase before any repeat; queue
state changes do not restart that rotation. Ordinary queued and historical
presentations still use durable media and queue-aware copy.

Queued completion polling is cancellation-aware. The poller checks task
cancellation, its generation, and the exact queued scan before every promotion
attempt; cancellation of the 350 ms delay exits immediately. Dismissing or
replacing the destination therefore cannot let a sleeping poller resume and
mutate a newer presentation.

`InsightContentView` resolves the carousel overlay independently through
`isCarouselAnalysisActive(for:)`. An exact visual owner remains active across
non-attention pending, uploading, staged, and inferencing queue snapshots;
ordinary queued presentations activate it only for inferencing, and terminal or
attention-required states remain still. The shell continues supplying the same
canonical scan ID and engine media, so the carousel's selected controller, focus
state, and animation session survive the `.analyzing` to `.queued` content
switch. Once the exact queued snapshot is bound, the toolbar exposes deletion by
fading its already-mounted trailing placeholder rather than rebuilding toolbar
structure.

Durable foreground retirement and local presentation ownership are distinct: a
connectivity callback may release provider ownership while the still-current
sheet remains authorized to become queued. Source and protected transport tests
enforce that split; hosted exact-SHA and physical-device acceptance remain
release-gated by the
[live scan connectivity handoff incident](../../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).

Explore uses the embedded mode when a user taps a completed Field-trip goal in
either the catalog card or outing detail. This keeps the Insight view inside the
current Explore sheet and returns to the outing on back. Missing local records
must be handled before navigation; the Insight shell does not fetch Field-trip
evidence or reconstruct media from a remote URL.

Saved biological Insights load private scan contribution rows through
`InsightSheetViewModel`. Contribution rows use the card-specific
`InsightFieldTripOverviewDestination`, which carries only an outing template or
Event identifier and never a focused checklist item. Modal and non-Explore
Insights push Goals overview in their current navigation stack. Embedded Explore
Insights call the optional overview callback, which appends the detail above the
Insight on Explore's existing path so native Back returns to the scan. Capture
pills and milestone notifications keep their separate focused
`CaptureGoalDestination` behavior. Empty results, queued scans, unauthenticated
state, feature gating, and request failure are silent. A scan-specific
invalidation event reloads the open Insight after progress or identification
correction finishes.

## Scan milestones

The Insight lifecycle owns result VoiceOver and haptic presentation, but it does
not enqueue `New to Naturebook`. Foreground and background scan completion pass
the final saved scan ID and `SpeciesData` to the shared
`ScanMilestoneCoordinator`, which waits for Field trip progress and batches
standard outings, Seasonal Challenges, achievements, then the dictionary
milestone. Keeping this outside `.onAppear` prevents repeated Insight
presentations from duplicating scan-completion notifications.

## Feedback and nested presentation ownership

Insight binds compiler-checked `ToastPayload` values into
`merianSystemFeedback`; message strings are display copy and do not determine
severity or navigation. Optional action closures remain owned by the current
scan-bound view model and are cleared with the matching payload. Passive banners
are pass-through, and ordinary feedback waits while the milestone stack owns the
same alignment.

Candidate review, Confidence explanation, and Field Chat follow-up actions are
typed values resumed from the source sheet's real `onDismiss`. Every mutation or
route rechecks the stable scan ID plus the applicable engine/local presentation
generation. The shell must not mount a sibling sheet or use a fixed teardown
sleep to bridge these workflows.

Shell owns scan eligibility, readiness handoff, navigation, and the outer
presentation slot. The shared conversation sheet, endpoint adapter, and
subject-fenced state live under `Features/FieldChat`; the retained
`InsightChat...` names are compatibility names rather than Shell ownership.

`InsightContentView` enforces that rule with one resolved
`InsightContentPresentation` value. Safari, Community, Explore composer,
candidate review, Field Notes, and description share one item-based sheet host;
the gallery's full-screen binding is mutually exclusive with the same value.
Destination-specific state remains scan/generation fenced, but it never creates
another sibling modal host.

The outer `InsightSheetView` independently owns one `InsightShellPresentation`
host for paywall, Field-trip author, Field Chat, Explore onboarding, and
Explore. At most one follow-up waits while the current sheet tears down, and it
mounts only after the source sheet's real `onDismiss`. The queued value retains
scan ID and presentation generation, so a late or replaced request is rejected
before mounting. Source Boolean flags are adapters at this boundary, not
additional presentation owners.

Closing an analyzing Insight also calls
`InferenceEngine.dismissAnalyzingPresentation()`. That lifecycle boundary stops
and fences Vision, deterministic trait extraction, staged Foundation work, and
phrase cadence, then removes any contextual phrase/live-media exposure. It does
not cancel the durable Gemini request, upload, persistence, or queued result
recovery, so a completed result can still appear in Scans later.

## Focused verification

Tests mirror the final owners:

- `Shell/`: architecture, capabilities, lifecycle, records, typed presentations,
  toolbar snapshots, queued handoff, and Field-trip contributions;
- `Content/`: actions and name preferences, bounded tag transactions with
  ordered account-fenced cloud snapshots, queue operation state, phrase/rotation
  and retry presentation policy, plus architecture;
- `FieldNotes/`: edit policy, editor save/dictation state, injected persistence
  and feedback forwarding, local/public reconciliation, queued presentation
  identity, and architecture;
- `Media/`: availability, gallery, deduplication, and suppression; and
- `Sharing/`: Explore publication, Community requests, and presentation
  identity.

Run the generated-project, ownership, and routing guards whenever this folder
changes:

```bash
make xcodegen
make validate-ios-project
bash scripts/test-ios-project-source-membership.sh
make validate-ios-event-routing
make test-ios-event-routing
```

The focused suites do not replace the complete `merianTests` target. Manual
parity covers modal and embedded presentation, queued-to-completed promotion,
toolbar actions, Field Chat handoffs, Field-trip contribution routing, media and
gallery continuity, VoiceOver, large Dynamic Type, and light/dark appearance.

## Prepared history presentation

`InsightShellPresentation.identificationHistory` shares the existing modal slot
and binds observation identity plus scan generation. `InsightSheetView+History`
admits only a multiple-result action supplied through optional `historyAccess`;
normal `.live` access is nil. The Debug UI-test fixture is the only enabled
path. `InsightSheetViewModel+History` refreshes the parent from an acknowledged
Core projection, never preview content. Generation/dismissal and library events
close or revalidate the model. History services and interaction state belong to
[History](../History/README.md).

The optional prepared history reanalysis callback uses the existing nested sheet
host. `InsightSheetView+History` stages an exact source-qualified handoff;
`handleShellPresentationDismissed` consumes it once after UIKit dismissal.
Parent presentation teardown clears it. Revalidation precedes the injected
historical route request, whose root dismissal and account/session fencing stay
owned by `AppRouteCoordinator` and Capture. It never uses the legacy refinement
callback. Ordinary history access and protected Capture access remain disabled.

The prepared **Reanalysis status** menu uses a separate optional
`reanalysisStatusAccess` and `.reanalysisStatus(scanId:generation)` in this same
presentation slot. `InsightSheetView+ReanalysisStatus` admits its owner-scoped
read model independently of history's multiple-result condition. Root dismissal,
scan-generation changes, nested dismissal and library invalidation close or
revalidate its private state. The History area owns phase-only rows and bounded
paging; Shell never admits, retries or discards a request from this surface.
Ordinary access remains nil.

The optional `savedReanalysisAccess` supplies the existing single Reanalyze menu
action before the legacy Pro/refinement branch. Its lock presentation is
supplied separately from legacy Pro access. `InsightSheetView+SavedReanalysis`
captures the displayed baseline before awaiting, retains a token-qualified
waiter, and checks the exact scan/presentation generation before routing.
Dismissal, disappearance or generation changes cancel only that waiter;
QueueManager retains any shared enrollment. A protected failure shows an error
and never invokes legacy refinement. Ordinary access remains nil.

The final action rechecks settled review state as well as acknowledged revision:
a newly pending identification-review job invalidates routing even when the
revision has not advanced. `SavedIdentificationReanalysisTests` covers that
boundary and account, source, selection and deletion races.
`IdentificationHistoryUITests` also exercises a Debug-only protected-entry
failure on a single-result scan: one menu item, no History entry, visible
failure and the original Insight retained. The synthetic failure never enrolls,
routes or calls a provider.

The runtime-audit manifest registers the entry acceptance suite and failure UI
smoke. The Release archive seed denylist includes the Debug-only failure launch
argument. UI checks query native context-menu labels because the menu does not
retain custom SwiftUI accessibility identifiers.

Protected reanalysis also covers Field Chat, biological guidance, both candidate
modal owners, and the confidence explanation (including its nested candidates).
Shell supplies one `SavedReanalysisPreparation` through the content tree. The
actual tap synchronously prepares the exact displayed request before any child
dismisses; successive `onDismiss` callbacks carry that same revocable ticket.
They never load a newer baseline. The host checks local presentation and engine
presentation generations separately before preparation and after resolution.

A protected preparation failure returns an inert ticket, preventing legacy
fallback even if access changes during dismissal. Protected actions do not
dismiss the parent Insight before resolution. Nil capability preserves the
legacy entry behavior. Ordinary capabilities remain nil; these changes do not
enable rollout or change review/publication authority.

`InsightHistoryReanalysisAccesses` groups History, status and saved-result entry
as one optional, nil-default environment value. The App root supplies all three
from the same retained bundle as Capture. Every default Insight host resolves
this overlay at the view boundary, including library, collections, Explore and
profile hosts. Explicit `dependencies:` injection wins even when its accesses
are nil; ordinary `.live` is never mutated. The Insight ViewModel does not
consume these accesses. The immutable App qualification gate is false, so this
wiring constructs no live bundle and enables no UI or background work.

If any base access is already supplied, including a Debug fixture from `.live`,
the entire base group remains authoritative. The overlay cannot mix fixture and
prepared accesses.

## Prepared selected-identification review

`SelectedAnalysisReviewAccess` reuses the history Session and its injected
review owner. Opening this capability is a local, owner-fenced read: it neither
enrolls the observation nor sends a review. The App composition prepares it
alongside history, status and reanalysis; ordinary installation remains
disabled. The retained `SelectedAnalysisReviewHost` connects protected toolbar
confirmation, rejection and receipt-backed Undo to that prepared capability.
Nested legacy candidate and Confidence review controls are withheld for
protected observations.

`SelectedAnalysisReviewBaseline` freezes the observation, owner, selected
analysis and global revision into the toolbar snapshot only after the exact
record has loaded into the inference presentation. A rejected Auth-fenced load
cannot create that baseline. A same-scan metadata lookup or collection edit
preserves the already displayed baseline instead of adopting newer, unseen
authority. A protected initial presentation without a baseline deliberately
reloads the exact record; an ordinary unenrolled presentation retains its
existing hydration. Acknowledged history refresh similarly reloads the
reconciled parent projection.

Opening selected review requires the frozen selection and revision to match a
fresh local context, idle selection, and the exact cached immutable result and
review ticket. Account loss or deletion invalidates the session. Selection or
authority changes invalidate new admission while owner-bound receipt recovery
remains available. The host must use scope validity for receipt observation and
exact ticket freshness for a new tap; acknowledged parent refresh is the only
projection bridge. The capability holds no idle Auth lease and cannot substitute
the current selection for the displayed target.

The host binds outside view rendering to the displayed baseline, Shell
generation and model container. A separate binding token rejects delayed alerts
after even an identical baseline reopens. Exact request uncertainty survives
rerenders; Retry saving review reuses that request. Actual queue-pass exit
refreshes the receipt without polling or an idle Auth lease. Applied completion
refreshes only the reconciled parent, once; negative terminal receipts retire
the old scope and require a new presentation, even if its revision has not
changed. Account, container, route and disappearance invalidate the old
controls.

Fresh enrollment protection, including a staged intent or failed lookup, takes
precedence over every legacy action. Missing protected access cannot fall back.
Legacy candidate and Confidence callbacks recheck that protection after delayed
sheet dismissal and before mutations. Unenrolled scans retain their existing
review flow. `SelectedAnalysisReviewHostTests` verifies retry identity, delayed
binding tokens, receipt consumption, conflict lockout and scope loss; the
existing enrollment and architecture suites cover the underlying boundaries.

## Prepared protected Field Chat

`ProtectedInsightChatAccess` bridges the loaded selected baseline to local
immutable requests and the injected queue delivery owner.
`ProtectedInsightChatModel` shows saved questions and exact assistant receipts
without the mutable legacy thread. The final Send action retains
UUIDs/text/ticket and synchronously stages before queue handoff. A parent
`ProtectedInsightChatContinuation` retains a save-uncertain candidate across
sheet reopening; a changed ticket can only recover an already saved exact
request, never admit unseen authority. Retrying a save only persists and
refreshes; the separate saved-question action authorizes delivery.

`InsightSheetView+ProtectedChat` owns the independent token-qualified shell
presentation. Toolbar protection precedes legacy Pro, unavailable-cache and
cloud-readiness actions. Nil/stale protected access never falls back. Closing
only closes the presentation; the retained queue continues independently under
account/deletion fences. Account/container loss clears private UI state.

Saved pending work has an explicit same-intent send action. Held or expired
running work has explicit exact-claim recovery; unexpired running work cannot
enter replay. Terminal replies never send again. Queue task-exit generation
refreshes local status without polling or an idle lease. Receipt pages are
bounded and replace one another, and new questions still require transactional
admission. Exact server no-admission proofs now appear as “Question not sent,”
with no fabricated answer. Full-scope status disables new sends for the proved
stale ticket even when local selected-cache equality still passes. This bar
survives reopening and cannot be hidden by receipt paging. Explicit
identification refresh now uses a retained queue-owned read. The host
revalidates the exact model, local and engine generations, owner/container and
returned ticket before loading the acknowledged parent. It closes the stale chat
without reopening or sending; a later user tap opens against the newly displayed
identification. Runtime qualification remains outstanding.
`ProtectedInsightChatUITests` uses `-seedProtectedInsightChat` and the real
enrolled V2 seed/persistence to check empty-send disabling, exact saved question
and identity across reopening. Only the delivery boundary is synthetic; it
checks the durable owner, target, revisions and request before withholding
network execution. The launch seed is Debug-only and included in the Release
archive marker check. All ordinary access and activation gates remain disabled.

The Debug-only `-seedProtectedChatStale` scenario uses real request admission,
queue delivery, proof settlement, state synchronization and host projection;
only the authenticated response and state bytes are synthetic. Its UI test
verifies the proof survives reopening, fresh sending stays unavailable until
explicit refresh, the stale sheet closes, and a later opening has an empty
composer plus the original saved proof. This does not prove real provider,
network, device or production rollout behavior.
