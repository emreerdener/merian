# Core UI

The `UI` directory contains the foundational visual components and design system
for the app.

## Purpose

This area houses reusable view modifiers, generic controls (e.g., primary action
buttons, custom toggles), typography extensions, and complex visual treatments
like glassmorphism shaders. Code placed here ensures visual consistency across
all feature modules and prevents duplication of fundamental UI elements.

## Shared loading presentation

`Components/Loading/GlowPulsingSkeletonView.swift` owns the reusable rounded
loading surface used by Explore, Field Trips, Insights, Profile, Scans, and
Species Dictionary. It preserves the standard and raised-grid treatments and
disables its repeating pulse when Reduce Motion is enabled. Callers own loading
state, geometry, copy, task lifetime, and replacement content; the Core view
owns only the mounted visual treatment. The unreferenced `ShimmerModifier` and
`View.shimmering()` API were retired rather than carried into this package.

## System share presentation

`Services/ShareSheetPresenter.swift` is the single main-actor UIKit bridge for
presenting caller-prepared activity items. It retains topmost-controller
traversal, unavailable-root dismissal, main-actor completion delivery, and
centered iPad popover anchoring. The presenter owns the actor hop from UIKit's
completion handler; feature callbacks may restore their playback or overlay
state directly. Feature owners continue to prepare share payloads and own
overlay, playback, export, analytics, and task state. Do not move payload
construction or feature lifecycle policy into the presenter, and do not add a
second `UIApplication`-resolving share helper under Utilities.

## Capture ownership boundary

Core UI owns only visual primitives reused across product areas. Capture's mode
selector, navigation bar, staged-media toolbar, flash button, and complete
control row live under `Features/Capture`; their routes, badges, platform
effects, task lifecycles, and presentation policies are feature semantics.
Capture may compose reusable Core primitives such as `ImageCropperView` and
`CircularMaterialControlModifier` without transferring feature-chrome ownership
into Core. `FloatingNavigationMenu` is Capture-only layout and therefore lives
beside `MainTabBar` under `Features/Capture/Shell/Components/Navigation`.

## Shared audio spectrogram

`Components/AudioSpectrogramView.swift` is the presentation-only raster surface
shared by Capture Record and Insight audio playback. It receives prepared
`SpectrogramColumn` values plus a display layout and contains no audio engine,
DSP, seeking, lifecycle, or network state. Palette and bitmap construction stay
in `Core/Media/AudioSpectrogramRenderer.swift`; Record retains its review
gesture and playhead timing.

## Shared Goal Progress

`Components/GoalProgressRing.swift` renders the compact circular
`completedCount/targetCount` treatment shared by active Field-trip profile
cards, outing level headers, and persistent Insight contribution rows. Feature
callers own their accessibility label/value and frame; the primitive owns
clamping, track/progress drawing, and the centered count text. Keep it
domain-neutral so future goal providers can reuse it without importing Field
trip models.

## Published scan grids

`Layout/PublishedScanGridStyle.swift` owns the three-column spacing and
outer-corner policy shared by the current-user Profile grid, Explore Author
Profile, and Species Dictionary Community sightings. The primitive determines
only reusable grid geometry and clipping. Each feature continues to own its post
source, media rendering, callbacks, accessibility copy, pagination, and
empty/loading states.

## Shared display values

`Components/ModelTierBadge.swift` renders an optional prepared
`ModelTierBadgePresentation` and delegates upgrade handling to its caller. It
does not resolve RevenueCat or entitlement singletons and does not own paywall
presentation. Insight derives live presentation in `BiologicalView`; Settings
provides deterministic preview values.

## Shared image editing

`Components/ImageCropperView.swift` owns the square crop interaction shared by
Capture staging and Profile avatar editing. It receives crop, cancel, delete,
and confirmation-feedback actions from the feature caller; it does not resolve
camera, haptic, persistence, or network services. Each feature retains its own
input value: Capture owns source context and resumable geometry, while Profile
owns its bounded avatar-crop preview. Pixel cropping and encoding remain in
`Core/Media`.

## Shared name selection

`Components/NamePickerSheet.swift` owns the reusable navigation-list treatment
for choosing one display name from a caller-provided set. It renders selection
rows and the active-name checkmark but owns no species repository, persistence,
route, feedback, or feature state. Insight Content and Explore Feed retain those
effects in their own feature owners.

## Shared media carousel presentation

`Components/MediaCarousel/` owns the domain-neutral native pager, fullscreen
gallery, audio playback page, and reusable video chrome used by Insights,
Capture, Field Trips, and Species Dictionary. `NativePageCarouselPage` contains
only stable page identity, a controller-reuse key that defaults to the page ID,
and rendered SwiftUI content. A stable ID/reuse-key pair updates the mounted
controller's root view without discarding its state. A changed ordered page
sequence or reuse key invalidates `UIPageViewController`'s cached data source
before the selected controller is reinstalled, preventing a stale neighbor from
surviving a feature-owned source-family change. `NativePageCarousel` and its
coordinator otherwise own eager mounting and selection synchronization;
`ZoomPageViewController` owns pinch, pan, and snap-back behavior.
`MediaGalleryPresentation` and `MediaGalleryItem` provide the normalized
cross-feature gallery input. The same directory owns shared pagination dots and
the iOS 26 top scroll-edge treatment. Feature owners remain responsible for
media ordering, source and attribution policy, availability state, navigation,
and their reuse-key projection.

Audio playback keeps player, pending replacement, boost request, seek, and
observer state private to its mounted page. `AudioBoostRequestState` gives each
toggle generation ownership so an older completion cannot clear or publish over
a newer on/off/on request. Shared side effects arrive through
`Core/Media/MediaPlaybackDependencies`; Core UI contains no feature telemetry
owner or live-service lookup.

## Shared cards and feedback

`Components/Cards` owns the domain-neutral card modifier, key/value row,
`MerianCardHeader`, and scientific-name styling used by Insights, Explore,
Species Dictionary, and Field Trips. `Feedback/ToastBanner.swift` and
`Feedback/ToxicityBanner.swift` likewise contain render-only cross-feature
presentation. Hazard classification remains with the caller; the toxicity banner
requires an explicit hazard type and does not read inference state.

## Shared local and remote image presentation

`Components/AsyncLocalImageView.swift` owns the local-path/remote-fallback image
surface shared by Insights, Explore, Field Trips, and Species Dictionary. It
retains task-identity cancellation, online retry identity, archived and
unavailable presentation, content-mode layout, and success/failure callbacks.
`Services/AsyncLocalImageDependencies.swift` is the only UI-layer owner that
resolves the live `LocalImageLoader`; the view accepts its loader closure
through a defaulted dependency value so tests and future hosts do not resolve
the actor directly. Feature callers continue to own source selection,
attribution, availability state, and navigation.

## Shared scan and empty-state presentation

`Components/ScanThumbnail.swift` owns cross-feature scan-thumbnail rendering for
Scans, Explore Field Trips, and Profile.
`Models/ScanThumbnailPresentation.swift` projects `LocalScanRecord` media into
visual, audio, reference-fallback, and terminal placeholder state. The view
receives online availability and optional reference-recovery actions from its
caller. `Services/ScanThumbnailLoader.swift` owns the injected live-loader
adapter and audio-to-visual fallback sequence; the view does not resolve those
loaders directly. Every shared-loader suspension is cancellation-fenced before a
result, fallback load, failure, or reference-recovery action can reach a reused
tile. The task identity includes source paths, loading policy, target pixel
size, placeholder kind, and relevant network availability.

Cancellation is represented by the loader returning no result, not by a visual
failure or no-source result. `ScanThumbnail` therefore leaves the replacement
task responsible for presentation state and never converts an obsolete request
into failure copy or a reference-recovery callback. Keep both the service-level
post-suspension checks and the final main-actor check when changing the loading
sequence.

`Components/EmptyStateView.swift` owns the generic title, message, symbol, and
layout treatment used by Scans, Explore, and Species Dictionary. Feature owners
continue to supply their own copy and decide when an empty state is visible.

Reference-thumbnail lookup and persistence are not UI responsibilities.
`Core/Data/Images/ScanThumbnailBackfillCandidate.swift` and
`ScanThumbnailBackfillActor.swift` own those Core image-pipeline boundaries,
while Scans Shell and Map services decide when to schedule them.

## System and milestone feedback

`ToastBanner` and the compact Scans snackbar share an adaptive inverse-glass
surface. Light mode uses strongly tinted dark glass with light semantic content;
dark mode uses strongly tinted light glass with dark semantic content. When
Reduce Transparency is enabled, the surface becomes opaque. Toast callers own
their content and placement, but should use the shared surface instead of
introducing feature-local material, borders, or color-scheme overrides.

`MerianSystemFeedbackModifier` mounts ordinary feedback in an alignment-scoped
overlay. Hit testing is enabled only when a `ToastPayload` action descriptor and
the matching view-owned handler are both present; passive or incompletely wired
feedback is entirely pass-through. The identity-keyed three-second task returns
on cancellation and verifies the current payload UUID before teardown, so an old
timer, close action, or outgoing transition cannot dismiss its replacement.
Animation remains inside the overlay and never wraps the underlying feature
tree.

Queued milestone notifications render as a collapsed FIFO stack. The active
toast remains the only interactive and accessible surface; up to two scaled,
downward-offset backplates indicate pending items. Dismissing or opening the
front toast reveals the next item, and VoiceOver announces the full pending
count without exposing the decorative layers as separate elements.

Milestone feedback is split by responsibility under `Feedback/`:

- `Models` owns immutable toast payloads, queue items, outcomes, and session
  tokens.
- `Policies` owns account/scan normalization, payload deduplication, Field trip
  receipt mapping, credited-progress display fallback, first-Field-trip
  achievement projection/merging, and **New to Naturebook** eligibility.
- `Presentation` owns the bounded FIFO presenter and nested-host registry.
- `Coordination` owns session control plus foreground/background scan completion
  sequencing, retry lifetime, and event publication.
- `Services` owns the clock and the only live adapters for account identity,
  Field trip networking, SwiftData-backed achievement calculation, offline
  acknowledgement, achievement caching, feature availability, and notification
  eligibility.

The retired `AchievementToastPresenter.swift` aggregate must not return.
Compatibility aliases preserve the established `AchievementToastPresenter` and
`AchievementToastItem` type names while their generic implementations live in
`Presentation/MilestoneToastPresenter.swift`. The coordinator remains the
per-scan business boundary; the presenter remains only a FIFO visual queue.
`AppDIContainer` explicitly composes `.live` scan dependencies and injects its
producer-only `AppEventSending` capability. The coordinator therefore resolves
no singleton, endpoint, offline queue, feature flag, or gamification manager
directly, preserving isolated preview and test graphs. Foreground and background
completion both key coordination by final saved scan ID and enqueue standard
outings, Seasonal Challenges, achievements, then `New to Naturebook` after the
progress attempt finishes.

`MilestoneToastBanner` preserves the shared 3.5-second timeout, haptics,
swipe/close dismissal, queue transition, and VoiceOver announcement. Its haptic
actions arrive through `MilestoneToastFeedbackDependencies`, which the app root
composes from its `HapticManager`; the banner and stack do not resolve the
process singleton. Field trip payloads use the completed goal artwork,
goal-complete title, and outing name in the same compact layout as other
milestones, and publish their typed capture-goal destination when tapped. Other
views must not show a second plain progress message in response to the same
refresh event.

Focused tests mirror these ownership boundaries: presenter, achievement policy,
scan policy, coordinator, and architecture coverage live in separate Core UI
suites. Coordinator subjects must be created through
`MilestoneFeedbackTestFixtures.coordinator`, whose default dependency graph is
fully isolated from authentication, offline sync, achievement cache, and
gamification process state. Only the presenter and achievement-policy
compatibility suites serialize access to the process-global gamification store.

## Core UI integration audit

Core UI is an actual cross-feature presentation package, not a holding area for
one-off controls. The integration audit moved declarations to the narrowest
owner without changing their rendering or interaction contracts:

- Capture Shell owns `FloatingNavigationMenu`.
- Explore Shared owns `FlowLayout`, which is reused by Feed and Field Trips.
- Insights Content owns `InsightCardEntranceModifier`; its hardware motion gate
  is supplied by `InsightContentDependencies` while Reduce Motion remains a view
  environment decision.
- Insights Identification Review owns `SlideToConfirm` and supplies its haptic
  actions through `IdentificationReviewFeedbackDependencies`.
- Profile User Profile owns `FadingScrollView`, and Profile Settings Plan owns
  `ComplimentaryScanDisplayState`.
- Core Notifications owns the cross-feature post-identification permission
  sheet. Capture and Settings inject their existing authorization action, so the
  shared view contains no notification-manager or app-container lookup.

`CoreUIArchitectureTests` prevents those retired Core paths from returning,
requires every production Core UI Swift file to remain at or below 600 lines,
rejects direct live-process resolution outside `Services`, and pins every
current lookup to its explicit image-loading, share-presentation, or milestone
adapter owner. It also freezes the skeleton and presenter declaration owners,
the retired Utilities paths, removal of the unused shimmer API, and the share
presenter's bounded UIKit contract. The near-limit `AudioPlaybackCarouselPage`
remains cohesive because its player, observer, replacement, boost, seek, and
teardown state must share one private mounted-view lifetime. The architecture
test explicitly requires every `@State` declaration and lifecycle helper to
remain private; do not split that state merely to reduce the line count by
widening it to module scope.

## Safe collection access

`Utilities/Array+Safe.swift` owns only the bounds-checked array subscript shared
by reusable Core UI and feature presentation. It performs no normalization,
deduplication, persistence, or feature policy. Species common-name comparison
lives in `Features/SpeciesReference/Models`.

`SafeArrayAccessTests` covers valid, negative, and upper-bound indices. The
Utilities-wide architecture suite freezes this member's exact Core UI owner and
prevents the removed generic deduplication helpers from returning.

## Recovered image refresh

`Modifiers/ImageRecoveryReloadModifier.swift` observes canonical scan-media
recovery changes for retained image views. Include its bound revision in the
loading task identity and check cancellation before publishing an image. Scan
thumbnails, full-size local images, Profile scans, Explore hero images, and the
post composer share this behavior so stronger evidence cannot leave an obsolete
timestamp guess visible. The observer follows view-task lifetime and buffers
only the latest change signal. New retained-image consumers of recovered scan
URLs must use the same modifier and cancellation check; changing the loader's
cache key alone cannot replace an image already held in view state. Explore hero
preloads carry no revision, so a nonzero recovery revision requires reacquiring
the image through the loader. The image loader separately versions cache and
coalescing keys; details are in the
[image pipeline](../../../../../docs/system-architecture/03-image-pipeline.md).
