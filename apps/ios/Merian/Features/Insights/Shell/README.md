# Insight Shell

The `Shell` directory acts as the root container and primary structural layout
for the Insight sheet.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the
assembly of the various insight components (`Media`, `Content`,
`IdentificationReview`, `Toolbars`) into a single cohesive scrollable view. It
handles the lifecycle and presentation state of the sheet without embedding deep
domain logic.

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
call site while focused tests inject deterministic closures.

Tests mirror these owners under `MerianTests/Features/Insights/Shell`, with
presentation-specific suites retained under `Content`, `FieldNotes`, `Media`,
and `Sharing`. `InsightShellArchitectureTests` enforces the folder shape,
deterministic Models boundary, live-resolution boundary, absence of direct
network clients in views/view models, removal of the former source and test
aggregates, and the 600-line ceiling.

## Presentation Modes

`InsightPresentationStyle.sheet` is the ordinary modal presentation.
`embeddedInScansLibrary` hosts the same Insight content as a pushed destination
inside an existing navigation stack and owns its back arrow/back-swipe behavior.
`ScanInsightRoute` carries only the stable scan ID. Route tap handlers must not
load `InferenceEngine` before mounting a sheet or navigation destination.
`LocalScanInsightLoader` commits that presentation first, performs one
fetch-limited local-record lookup, and then hydrates the engine before it
constructs `InsightSheetView`. A record deleted during the handoff renders
**Scan unavailable** instead of stale Insight content. The sheet's normal record
binding recognizes that exact already-loaded scan and does not cancel and
restart its hydration.

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
`InsightContentPresentation` value. Safari, report, Community, Explore composer,
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
and fences Vision, deterministic trait extraction, future Foundation work, and
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
- `FieldNotes/`: local/cloud and presentation-identity state;
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
