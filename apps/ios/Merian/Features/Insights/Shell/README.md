# Insight Shell

The `Shell` directory acts as the root container and primary structural layout
for the Insight sheet.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the
assembly of the various insight components (`Media`, `Content`,
`IdentificationReview`, `Toolbars`) into a single cohesive scrollable view. It
handles the lifecycle and presentation state of the sheet without embedding deep
domain logic.

## Presentation Modes

`InsightPresentationStyle.sheet` is the ordinary modal presentation.
`embeddedInScansLibrary` hosts the same Insight content as a pushed destination
inside an existing navigation stack and owns its back arrow/back-swipe behavior.
`ScanInsightRoute` carries only the stable scan ID; the presenting shell must
resolve and load the caller's local scan before pushing it.

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

Closing an analyzing Insight also calls
`InferenceEngine.dismissAnalyzingPresentation()`. That lifecycle boundary stops
and fences Vision, deterministic trait extraction, future Foundation work, and
phrase cadence, then removes any contextual phrase/live-media exposure. It does
not cancel the durable Gemini request, upload, persistence, or queued result
recovery, so a completed result can still appear in Scans later.
