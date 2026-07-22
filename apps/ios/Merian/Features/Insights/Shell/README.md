# Insight Shell

The `Shell` directory acts as the root container and primary structural layout for the Insight sheet.

## Purpose
Following the Merian architecture guidelines, the `Shell` orchestrates the assembly of the various insight components (`Media`, `Content`, `IdentificationReview`, `Toolbars`) into a single cohesive scrollable view. It handles the lifecycle and presentation state of the sheet without embedding deep domain logic.

## Presentation Modes

`InsightPresentationStyle.sheet` is the ordinary modal presentation.
`embeddedInScansLibrary` hosts the same Insight content as a pushed destination
inside an existing navigation stack and owns its back arrow/back-swipe behavior.
`ScanInsightRoute` carries only the stable scan ID; the presenting shell must
resolve and load the caller's local scan before pushing it.

Explore uses the embedded mode when a user taps a completed Field-trip goal in
either the catalog card or outing detail. This keeps the Insight view inside the
current Explore sheet and returns to the outing on back. Missing local records
must be handled before navigation; the Insight shell does not fetch Field-trip
evidence or reconstruct media from a remote URL.

Saved biological Insights load private scan contribution rows through
`InsightSheetViewModel`. Contribution rows use the card-specific
`InsightFieldTripOverviewDestination`, which carries only an outing template or
Event identifier and never a focused checklist item. Modal and non-Explore
Insights push Goals overview in their current navigation stack. Embedded
Explore Insights call the optional overview callback, which appends the detail
above the Insight on Explore's existing path so native Back returns to the
scan. Capture pills and milestone notifications keep their separate focused
`CaptureGoalDestination` behavior. Empty results, queued scans,
unauthenticated state, feature gating, and request failure are silent. A
scan-specific invalidation event reloads the open Insight after progress or
identification correction finishes.

## Scan milestones

The Insight lifecycle owns result VoiceOver and haptic presentation, but it does
not enqueue `New to Naturebook`. Foreground and background scan completion pass
the final saved scan ID and `SpeciesData` to the shared
`ScanMilestoneCoordinator`, which waits for Field trip progress and batches
standard outings, Seasonal Challenges, achievements, then the dictionary
milestone. Keeping this outside `.onAppear` prevents repeated Insight
presentations from duplicating scan-completion notifications.
