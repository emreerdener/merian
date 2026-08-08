# Explore Shell

The `Shell` directory acts as the root container and routing hub for the Explore tab.

## Purpose

This area orchestrates the top-level navigation, layout chrome, and state
coordination for Explore. It manages transitions among exactly three bottom
items—Observations, Field trips, and Identify—plus root mode pickers, pushed
detail/feed routes, notifications, and search interfaces while product-area
subviews remain focused on their own domains.

Field trips and standard Outings are released for every user through the
`.fieldTrips` entry in the central `FeatureFlags` registry. Events are also
public for every user and have no independent feature flag, allowlist,
simulator bypass, or debug override. Event entry points route directly through
the same typed Explore navigation boundary as standard outings.

## Fresh-launch entry

Explore remains a sheet over the Capture workspace. When the default-off
`AppSettings.opensExploreOnLaunch` preference is enabled and onboarding is
complete, a new process may present the generic feed immediately. This launch
preference never selects a post or another pushed destination and is not
reevaluated on foreground returns.

The generic feed is the lowest-priority launch route. Photos/Files imports
dismiss it in favor of staging and crop, while deep links and tapped
notifications replace it with their requested post, community request, scan, or
library route.

## Root navigation and Identify routing

`ExploreTab` contains `.feed`, `.fieldTrips`, and `.community` only. The
`.community` tab is labeled **Identify** and owns
`ExploreIdentifyMode.requests` / `.index`:

- Requests renders the 12-request/10-Activity dashboard and can push the
  complete **Identify requests** and **Identify activity** feeds.
- Index renders the existing Species Dictionary overview directly.

The bottom tab bar and root segmented picker are visible only while
`navigationPath` is empty. Complete Identify feeds, request detail, species
catalog/detail, and other pushed pages hide root chrome and rely on native Back
navigation.

Deep-link policy is explicit. `ExploreInitialTabPolicy` selects Identify for a
species or community-request destination.
`ExploreInitialIdentifyModePolicy` selects Index for species and Requests for
community requests. Runtime request notifications follow the same policy in
`openCommunityIdentificationRequest(_:)`. Preserve this selection-before-push
order when adding entry points.

The taxonomy Tree/galaxy map remains implemented behind the default-off
`.speciesDictionaryTree` flag but is disconnected from root MVP navigation.

## Field trip milestone routing

`ExploreView` converts the source-agnostic `CaptureGoalDestination` passed by
Capture or the shared progress toast at this feature boundary. A standard
`.fieldTrip(templateId:checklistItemId:)` destination selects Outings, opens the
template, and focuses the credited goal. A
`.fieldTripChallenge(challengeId:)` destination selects Events and pushes
Seasonal Challenge detail. Do not expose `FieldTripTemplateRoute` or
`FieldTripChallengeRoute` to Core feedback code.

`fieldTripProgressInvalidated(templateIds:)` and
`fieldTripChallengeProgressInvalidated(challengeIds:)` continue to refresh
affected durable lists/details only. They must not produce a local plain toast;
the bounded `MilestoneToastPresenter` already owns the ephemeral user-facing
notification.

The persistent Insight contribution card uses the same destination conversion.
When an Insight is already pushed inside Explore, its optional open-goal
callback appends the standard outing or Event destination to this navigation
stack. A root Insight instead requests `AppRoute.captureGoal`; the root route
coordinator dismisses the occupied presentation before `CameraSheetRouter`
presents Explore. The card must not create a second Explore sheet around an
embedded Insight.

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
