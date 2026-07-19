# Explore Shell

The `Shell` directory acts as the root container and routing hub for the Explore tab.

## Purpose
This area orchestrates the top-level navigation, layout chrome, and state coordination for the Explore feature. It manages the transitions between Observations, Identify, Field trips, Dictionary, pushed detail routes, notifications, and search interfaces while keeping the sub-components focused on their own domain logic.

Field trips and standard Outings are released for every user through the shared
`FieldTripsAvailability` rule. Events remain staged behind
`FieldTripEventsAvailability` for the allowlisted tester email and simulator
builds. New Event entry points must use that shared rule for UI, loading, and
routing rather than adding local debug checks. This is a client-build switch,
not a remote flag; DEBUG startup logs `TODO(field-trip-events-release)` until the
canonical checklist in `docs/features-and-hardware/25-field-trips.md` is
completed.

## Fresh-launch entry

Explore remains a sheet over the Capture workspace. When the default-off
`AppSettings.opensExploreOnLaunch` preference is enabled and onboarding is
complete, a new process may present the generic feed immediately. This launch
preference never selects a post or another pushed destination and is not
reevaluated on foreground returns.

The generic feed is the lowest-priority launch route. Photos/Files imports
dismiss it in favor of staging and crop, while deep links and tapped
notifications replace it with their requested post, community request, scan, or
library route. `CameraSheetRouter` marks `hasSeenExploreNewChip` when Explore
appears, including this automatic presentation.

## Field trip milestone routing

`ExploreView` converts the source-agnostic `CaptureGoalDestination` passed by
Capture or the shared progress toast at this feature boundary. A standard
`.fieldTrip(templateId:checklistItemId:)` destination selects Outings, opens the
template, and focuses the credited goal. A
`.fieldTripChallenge(challengeId:)` destination selects Events and pushes
Seasonal Challenge detail only while Events are enabled. Do not expose `FieldTripTemplateRoute` or
`FieldTripChallengeRoute` to Core feedback code.

`fieldTripProgressUpdated` and `fieldTripChallengeProgressUpdated` continue to
refresh affected lists/details only. They must not produce a local plain toast;
the global `MilestoneToastPresenter` already owns the user-facing notification.

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
