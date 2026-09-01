# Core UI

The `UI` directory contains the foundational visual components and design system
for the app.

## Purpose

This area houses reusable view modifiers, generic controls (e.g., primary action
buttons, custom toggles), typography extensions, and complex visual treatments
like glassmorphism shaders. Code placed here ensures visual consistency across
all feature modules and prevents duplication of fundamental UI elements.

## Capture control layout

`Components/CaptureControlBar.swift` exposes `CaptureControlBarLayout` as the
fixed chrome contract shared with `CaptureWorkspaceView`: an 80 pt primary
control, a 124 pt bottom inset, and a 204 pt reserved height. The workspace
publishes that fixed reservation without measuring the rendered bar with a
preference key. Full-screen Camera and Audio overlays use the separate fixed
`fullScreenOverlayClearance` value of 250 pt, preserving the position used
before child measurement was removed. The full-screen pager reports a zero
bottom safe-area inset, so its geometry must not be used to derive this
clearance. The shared capture row center-aligns its 80 pt primary control with
the 50 pt secondary controls in Camera, Audio, and Describe. Describe's
UIKit-hosted editor uses the 204 pt `describeContentBottomClearance`
reservation, matching the row's actual reserved height. The editor's flexible
interior consumes the remaining viewport height, and its own 24 pt bottom
padding separates the rounded field from the fixed row instead of leaving blank
page space. Camera crop composition keeps its separately documented framing
margin.

Do not reintroduce child-size-to-parent-state feedback for this fixed chrome. If
the control dimensions change, update the constants and verify Camera-, Audio-,
and Description-first cold launches with strict AttributeGraph cycle logging.
`testCameraHintPreservesClearanceAboveShutter` also verifies the real rendered
hint and shutter frames retain at least 8 pt of separation.
`testDescribeFirstLaunchRendersAndOpensPrompts` verifies both the Describe
control-row centerline and 8...32 pt of rendered clearance below the editor. It
also requires 8...32 pt between the `CaptureModeToggle` and Describe question
navigation, catching both overlap and duplicate top-safe-area padding. The
Describe table-of-contents control exposes the accessibility label **Show
prompts** and stable UI-test identifier `DescribePrompts`.

## Capture mode selector

`Components/MediaModeToggle.swift` owns Capture's fixed, icon-only mode
selector. It bridges one per-instance `UISegmentedControl` into SwiftUI rather
than composing a custom thumb or changing the global UIKit appearance proxy. The
control uses a bounded 200 by 56 pt frame rather than expanding across the
workspace. Its compact equal-width segments keep the icon centers close while
giving its 24 pt symbols at least 21 pt of approximate horizontal padding. It
retains at least 24 pt side margins on supported phone widths, and every segment
still exceeds the 44 pt minimum touch width. Describe reserves an 82 pt content
band for the selector and its required visual gap. `UIAction` segments use
`viewfinder`, `waveform`, and `text.bubble`; their retained titles and symbol
accessibility labels expose **Scan**, **Record**, and **Describe** to VoiceOver
and UI automation while UIKit draws only the symbols.

Construct every action with its normal and selected image before installing it.
UIKit returns immutable action snapshots from a segmented control on iOS 18, so
never mutate an action obtained from `actionForSegment(at:)`. Native selection
updates `selectedSegmentIndex`, then refreshes each installed original-rendering
image through `setImage(_:forSegmentAt:)` according to the actual selected index
and appearance. An order change remains the only path that removes and rebuilds
the segments.

The selected segment receives a local adaptive near-white tint: 82% opacity in
dark appearance, 96% in light appearance, and full white under Increased
Contrast. On iOS 26, the entire selector track uses a regular interactive Liquid
Glass capsule instead of an opacity-reduced material layer, while UIKit owns the
native selected thumb and segment interaction. Earlier supported systems use an
`ultraThinMaterial` capsule behind their native segmented-control presentation.
The selected symbol's installed normal and selected images are both solid black
against that light thumb, preventing UIKit from falling back to an inactive
white image. Inactive symbols are solid white in dark appearance and black in
light appearance. The images use original rendering so UIKit cannot apply one
template tint to both states. Liquid Glass and the fallback material remain
system-owned, so Reduce Transparency continues through the platform behavior.

`CaptureWorkspaceView` owns the shared selection state. Selector actions and
settled pager swipes each emit one `HapticManager` selection pulse, while the
guarded programmatic synchronization path emits none. The shared manager keeps
the user's Haptics preference and Expedition mode suppression authoritative.
Keep the `CaptureModeToggle` automation identifier and never restore an app-wide
`UISegmentedControl.appearance()` mutation.

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

`Models/ComplimentaryScanDisplayState.swift` is the presentation-only value
shared by the Settings plan card and the Insight model-tier badge. It describes
available or exhausted complimentary Pro display state without owning
entitlement lookup, quota admission, persistence, or RevenueCat behavior.
Production callers derive it from their established entitlement owner; the
Settings DEBUG gallery may inject a deterministic override for visual QA.

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

`Components/CaptureFlashButton.swift` is the presentation-only flash control
used by the shared Capture control bar. The Capture owner supplies feedback and
the `CameraManager` mutation through its action closure.

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

`Feedback/AchievementToastPresenter.swift` retains its legacy filename for
project continuity but defines the generic `MilestoneToastPresenter`,
`FieldTripMilestonePayload`, and `ScanMilestoneCoordinator`. The coordinator is
the per-scan business boundary; the presenter is only a FIFO visual queue. The
coordinator receives `AppEventSending` from `AppDIContainer` and never publishes
by resolving a bus through `AppDIContainer.shared`, preserving isolated preview
and test event graphs. Foreground and background completion both key
coordination by final saved scan ID and enqueue standard outings, Seasonal
Challenges, achievements, then `New to Naturebook` after the progress attempt
finishes.

`MilestoneToastBanner` preserves the shared 3.5-second timeout, haptics,
swipe/close dismissal, queue transition, and VoiceOver announcement. Field trip
payloads use the completed goal artwork, goal-complete title, and outing name in
the same compact layout as other milestones, and publish their typed
capture-goal destination when tapped. Other views must not show a second plain
progress message in response to the same refresh event.
