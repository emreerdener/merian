# Explore Shell

The `Shell` directory acts as the root container and routing hub for the Explore tab.

## Purpose
This area orchestrates the top-level navigation, layout chrome, and state coordination for the Explore feature. It manages the transitions between Observations, Identify, Field Trips, Dictionary, pushed detail routes, notifications, and search interfaces while keeping the sub-components focused on their own domain logic.

Field Trips is currently release-gated by `FieldTripsAvailability`: only the
allowlisted tester email and simulator builds may expose its tab or supporting
surfaces. New Field Trips entry points must use the same shared rule rather than
adding local debug checks.

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
