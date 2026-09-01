# Explore Shell

The `Shell` directory acts as the root container and routing hub for the Explore
tab.

## Purpose

This area orchestrates the top-level navigation, layout chrome, and state
coordination for Explore. It manages transitions among exactly three bottom
items—Observations, Field trips, and Identify—plus root mode pickers, pushed
destinations, notifications, and search interfaces while product-area subviews
remain focused on their own domains.

The
[canonical Explore product contract](../../../../../../docs/rfcs/explore-page.md)
and
[root-navigation contract](../../../../../../docs/features-and-hardware/24-explore-bottom-menu.md)
remain authoritative for shipped behavior, copy, accessibility, and routing;
this README documents the iOS ownership boundary.

## Ownership boundary

- `Models/ExploreShellNavigationModels.swift` owns the three root tabs, Feed/Map
  mode, initial-route precedence, Capture-goal and embedded-Insight conversion
  policies, and the lightweight post-navigation request passed from the
  navigation host to the root.
- `Models/ExploreNotificationNavigationModels.swift` owns the typed destination,
  opaque open token, and preparation outcome used to authorize the handoff
  across notifications-sheet dismissal.
- `Services/ExploreShellDependencies.swift` is the only Shell layer that
  resolves the live app-event stream, app-level Scans-library route request, and
  container-owned haptic manager. Views receive only the selection,
  light-impact, and error-feedback actions they use.
- `ViewModels/ExploreNotificationNavigationCoordinator.swift` owns the
  latest-wins open session, asynchronous post preparation fencing, sanitized
  reply fallback mapping, token-checked destination and failure commits, and the
  one-time staged-to-pending dismiss handoff.
- `Views/ExploreView.swift` owns the shared `NavigationPath`, root selection,
  sheet items, Insight handoff state, playback coordinator, and injected
  dependencies. `Views/ExploreShellNavigationView.swift` registers typed
  destinations and owns route-local composition. The lifecycle, presentation,
  and event/feedback modifiers keep their original ordering and exact mount
  lifetimes.
- `Components/` owns the root segmented picker and notification button.

Shell views and components perform no networking and resolve no service
singletons. Root selection, `NavigationPath`, sheet occupancy, and playback
overlay lifetime remain view-local so animation and dismissal timing do not move
into an asynchronous state owner. Production Shell files remain below the
600-line review guard.

Field trips and standard Outings are released for every user through the
`.fieldTrips` entry in the central `FeatureFlags` registry. Events are also
public for every user and have no independent feature flag, allowlist, simulator
bypass, or debug override. Event entry points route directly through the same
typed Explore navigation boundary as standard outings.

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
`.community` tab is labeled **Identify** and owns `ExploreIdentifyMode.requests`
/ `.index`:

- Requests renders the 12-request/10-Activity dashboard and can push the
  complete **Identify requests** and **Identify activity** feeds.
- Index renders the existing Species Dictionary overview directly.

The bottom tab bar and root segmented picker are visible only while
`navigationPath` is empty. Complete Identify feeds, request detail, species
catalog/detail, and other pushed pages hide root chrome and rely on native Back
navigation.

Deep-link policy is explicit. `ExploreInitialTabPolicy` selects Identify for a
species or community-request destination. `ExploreInitialIdentifyModePolicy`
selects Index for species and Requests for community requests. Runtime request
notifications follow the same policy in
`openCommunityIdentificationRequest(_:)`. Preserve this selection-before-push
order when adding entry points.

An Insight shown from Explore must not change this navigation path while its
sheet is tearing down. `ExploreView` and `ExplorePostDetailView` retain a
pending Community request ID, dismiss their owned Insight route, and call
`openCommunityIdentificationRequest(_:)` only from the exact sheet `onDismiss`.
Do not replace this handoff with a fixed delay or an immediate path reset.

The inverse owned-post handoff has one dismissal owner too. When Explore is
itself hosted by Insight, post detail reports the local scan ID to
`ExploreView`; the shell invokes the parent callback and dismisses itself
exactly once. The enclosing Insight applies the staged scan from Explore's
`onDismiss`. Post detail must not dismiss the shell, and the parent must not
replace Insight while Explore is still tearing down.

Recent-activity navigation keeps only a typed destination across the
notifications-sheet boundary. Post destinations retain a lightweight post ID,
not an `ExplorePost`, and re-resolve from `ExploreFeedViewModel` after
`onDismiss`. Async post preparation is guarded by a latest-wins token so a newer
tap or manual dismissal invalidates late completion. Every prepared destination
or failure must commit with that same token before sheet dismissal or error
feedback; dismissal discards uncommitted staged state.

`Notifications/` owns decoded activity and row presentation, live catalog/read
and comment/reply adapters, generation-fenced catalog and reply-thread state,
and the notification-specific reply route/fallback. The Shell notification
coordinator owns the latest-open session, uncommitted staged destination,
token-checked success/failure commit, and one-time pending destination, while
`ExploreView` owns the shared `NavigationPath`; Feed owns the lightweight reply
target carried inside `ExplorePostRoute`. Post detail converts that target to
the Notifications-owned reply route immediately before presenting the thin reply
sheet.

Identify/Index is the sole Species Dictionary browsing surface. The Shell does
not own or register a separate taxonomy visualization route.

## Feed route ownership

The Shell wires Feed callbacks into the shared `NavigationPath`, but the Feed
owns its route values and screens. `Feed/Models/ExploreFeedRoutes.swift` owns
`ExplorePostRoute`, `ExplorePostDetailOrigin`, notification reply targets, and
`ExploreHashtagRoute`; `Feed/Views/ExploreFeedTabContent.swift` and
`ExploreHashtagPostsView.swift` own their rendering and feature-local state.
Keep new Feed presentation, filtering, post editing, and hashtag loading out of
`Views/ExploreView.swift`. The Shell should retain only cross-area selection,
destination conversion, dismissal handoffs, and navigation-stack coordination.

## Field trip milestone routing

`ExploreView` converts the source-agnostic `CaptureGoalDestination` passed by
Capture or the shared progress toast at this feature boundary. A standard
`.fieldTrip(templateId:checklistItemId:)` destination selects Outings, opens the
template, and focuses the credited goal. A `.fieldTripChallenge(challengeId:)`
destination selects Events and pushes Seasonal Challenge detail.
`ExploreFieldTripNavigationPolicy` owns that conversion. The unchanged
`FieldTripTemplateRoute`, `FieldTripPublicationRoute`,
`FieldTripChallengeRoute`, and `FieldTripChallengeEntryRoute` values live with
their product owner in `FieldTrips/Models/FieldTripRoutes.swift`; Core feedback
code sees only `CaptureGoalDestination`.

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
`ExploreShellNavigationView`. The shell fetches the matching device-local
`LocalScanRecord`, loads it through `InferenceEngine`, and appends
`ScanInsightRoute` to the existing Explore `NavigationPath`. The destination
renders `InsightSheetView` with `.embeddedInScansLibrary`, so the user gets the
normal Insight content plus a back arrow/back swipe inside the same Explore
sheet. Do not present another sheet for this route.

The Field trips API does not provide media URLs for this feature. If the local
record is unavailable, show the existing unavailable toast and do not append a
route. Catalog and detail callers both use the same callback so they cannot
diverge in ownership, loading, or failure behavior.

## Explore Video Coordination

`ExploreView` owns the scoped `ExploreVideoPlaybackCoordinator` for the entire
Explore presentation and injects it through the SwiftUI environment. The shell
is responsible for marking root-level overlays such as comments, notifications,
Insight sheets, and author profile sheets with
`.exploreVideoPresentedOverlayLifecycle(reason:)` on the presented content. That
content owns the token through `onDisappear`; a sheet binding becoming false
only starts teardown and must not resume video underneath the animation.

Keep this ownership centralized. Feed/detail subviews may add lifecycle tokens
for their own nested sheets, and UIKit presenters may hold explicit tokens, but
new Explore overlays should not use global `NotificationCenter` pause/resume
events. The coordinator's overlay depth is the source of truth that prevents a
nested sheet dismissal from resuming video while another sheet still covers it.

## Focused tests

Tests mirror Shell ownership under `MerianTests/Features/Explore/Shell/`:

- `ExploreShellNavigationPolicyTests` locks the three root items, deep-link mode
  selection, initial-route precedence, focused Outing conversion, Event
  selection, embedded-Insight destination conversion, and post comment targets.
- `ExploreNotificationNavigationCoordinatorTests` locks typed immediate
  destinations, Field-trip gating, reply fallback mapping, latest-selection
  fencing, outcome-commit fencing, dismissal invalidation, one-time destination
  consumption, and current-error delivery.

Run the focused matrix after changing Shell models, dependencies, navigation,
sheet lifecycle, or notification handoffs:

```bash
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/ExploreShellNavigationPolicyTests \
  -only-testing:merianTests/ExploreNotificationNavigationCoordinatorTests \
  -only-testing:merianTests/ActiveCaptureGoalStoreTests test
```

Manual parity must cover all three root items and segmented modes; species,
Community, post, hashtag, author, Field-trip, and completed-scan destinations;
initial deep links and capture goals; notification selection/dismissal races;
Insight-to-Community and owned-post dismissal handoffs; missing local scans;
root comments/notifications/Insight overlay playback; VoiceOver; large Dynamic
Type; Reduce Motion; and light/dark appearance.
