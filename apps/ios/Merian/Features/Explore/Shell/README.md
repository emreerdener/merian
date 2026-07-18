# Explore Shell

The `Shell` directory acts as the root container and routing hub for the Explore tab.

## Purpose
This area orchestrates the top-level navigation, layout chrome, and state coordination for the Explore feature. It manages the transitions between Observations, Identify, Field trips, Dictionary, pushed detail routes, notifications, and search interfaces while keeping the sub-components focused on their own domain logic.

The Field trips feature is currently release-gated by `FieldTripsAvailability`: only the
allowlisted tester email and simulator builds may expose its tab or supporting
surfaces. New Field trips entry points must use the same shared rule rather than
adding local debug checks.

## Completed Field-trip Scan Navigation

Completed standard-outing goal tiles pass their private `completedScanId` to
`ExploreView`. The shell fetches the matching device-local `LocalScanRecord`,
loads it through `InferenceEngine`, and appends `ScanInsightRoute` to the
existing Explore `NavigationPath`. The destination renders `InsightSheetView`
with `.embeddedInScansLibrary`, so the user gets the normal Insight content plus
a back arrow/back swipe inside the same Explore sheet. Do not present another
sheet for this route.

The Field trips API does not provide media URLs for this feature. If the local
record is unavailable, show the existing unavailable toast and do not append a
route. Catalog and detail callers both use the same callback so they cannot
diverge in ownership, loading, or failure behavior.

## Explore Video Coordination

`ExploreView` owns the scoped `ExploreVideoPlaybackCoordinator` for the entire
Explore presentation and injects it through the SwiftUI environment. The shell
is responsible for marking root-level overlays such as comments, notifications,
Insight sheets, and author profile sheets with
`.exploreVideoOverlayLifecycle(isPresented:reason:)`.

Keep this ownership centralized. Feed/detail subviews may add lifecycle tokens
for their own nested sheets, and UIKit presenters may hold explicit tokens, but
new Explore overlays should not use global `NotificationCenter` pause/resume
events. The coordinator's overlay depth is the source of truth that prevents a
nested sheet dismissal from resuming video while another sheet still covers it.
