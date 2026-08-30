# Capture Shell

The `Shell` directory acts as the root container for the entire Capture feature.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the
transitions between the different capture modes (`Scan`, `Record`, `Describe`).
It acts as the routing layer, keeping the individual capture modes isolated and
focused entirely on their specific hardware/input logic.

The horizontal mode pager uses a `LazyHStack`, so startup does not
unconditionally construct every off-screen page. The configured first mode is
selected during workspace initialization, and camera-session startup remains
gated on visual mode. Keep page sizing and `scrollTargetLayout()` on the lazy
stack when changing pager behavior.

## Ownership

The Shell is organized by responsibility rather than as a pair of aggregate
files:

- `Models/` owns value-only media, goal, and presentation policy. These
  declarations do not resolve live state or platform actions; share-state and
  account-seed lookups enter through injected closures.
- `Services/` is the only Shell owner that constructs live networking, remote
  media-download, connection-prewarm, share/account lookup, keyboard platform,
  and haptic adapters. `CaptureWorkspaceKeyboardService` owns the raw UIKit
  keyboard publishers, dismissal action, and software-keyboard visibility check;
  Views, Components, and Modifiers do not access `NotificationCenter.default`.
  The root view model receives live dependencies through the narrow
  closure-based `CaptureWorkspaceDependencies` value; it does not construct a
  network client or URL session.
- `ViewModels/` owns capture state and orchestration. Responsibility-specific
  extensions cover routing, imports, staging, refinement, and lifecycle. The
  `CaptureWorkspaceOperationState` contains private mutable tasks, route
  handoffs, import coalescing, timeout fences, and ordered crop requests so the
  underlying storage is not widened to the module. Its external-import task owns
  the retry loop, keeping the final retry check and task-handle release in one
  MainActor turn so an overlapping request cannot be stranded at completion. A
  sheet deferral still stops that iteration until the exact dismissal callback;
  if dismissal wins the final handoff race, its resume request becomes the next
  iteration before the handle is released.
- `Modifiers/` composes root routing, lifecycle observation, presentation,
  binding adapters, and external-import retry triggers. The mounted
  orchestration modifier delivers the keyboard service's publishers on the main
  queue before consuming them through SwiftUI `.onReceive`, while presentation
  bindings retain keyboard animation timing. Modifiers may consume app-injected
  environment state, but they do not resolve endpoint, client, URL-session, or
  haptic singletons.
- `Views/` and `Components/` retain UI-only pager selection, scroll/focus state,
  goal expansion, presentation bindings, and exact dismissal timing. They send
  user intents to the view model and contain no direct networking.

Tests mirror this boundary under `apps/ios/MerianTests/Features/Capture/Shell/`.
The architecture suite enforces the live-service and deterministic Models
boundaries, required ownership directories, and a 600-line ceiling for every
production Swift file in this folder. Presentation-policy and operation-state
suites exercise the extracted deterministic behavior, the dependencies suite
locks injected feedback/prewarm and account lookup behavior, and the existing
`CaptureWorkspaceViewModelRefinementTests` selector remains stable across the
responsibility-specific test files.

Cross-area declarations do not remain in Shell merely because the root supplies
them. `Capture/Shared/Utilities` owns the composing-center environment contract
used by Shell and Record, while `Core/Media` owns the immutable
`SendableCGImage` concurrency wrapper used by Capture and Insights. The
architecture suite also prevents Shell Models from importing SwiftUI or UIKit.

`MediaModeToggle` remains fixed above that pager and uses one native
`UISegmentedControl`. Its bounded 200 by 56 pt frame uses compact tab-bar-like
proportions, displays 24 pt symbols, and leaves at least 24 pt side margins on
supported phone widths. Its equal segments display `viewfinder`, `waveform`, and
`text.bubble`; the action titles and symbol accessibility labels retain the
accessible names **Scan**, **Record**, and **Describe**. The selected thumb uses
a per-instance adaptive near-white tint, reaching full white under Increased
Contrast. Its symbol is black, while inactive symbols use white in dark
appearance and black in light appearance. On iOS 26, the full selector track
uses a regular interactive Liquid Glass capsule; earlier systems use an
`ultraThinMaterial` capsule fallback. UIKit continues to own the selected thumb,
segment interaction, and selected-state semantics. Normal and selected images
are attached before each action is installed, and `setImage(_:forSegmentAt:)`
refreshes the installed normal images from the actual selected index so UIKit
cannot show a white active icon. Do not mutate the immutable action snapshots
returned by the control on iOS 18. The existing SwiftUI binding keeps taps,
horizontal paging, configured order, and camera-session ownership synchronized.
Successful selector changes and settled pager swipes each emit one selection
pulse through `HapticManager`, preserving the user's Haptics setting and
Expedition mode suppression without vibrating during programmatic page sync. Do
not replace the control with custom capsules or restore app-wide
`UISegmentedControl.appearance()` changes. This is the complete mode-selection
surface, not a trigger for a separate filter or pop-up menu.

Describe keeps its vertical scrolling behind a UIKit `UIScrollView` hosting
boundary. Its prompt/dictation lifecycle observer and questions sheet are owned
by `CaptureWorkspaceView`, outside the horizontal pager. Capture chrome derives
its clearance from fixed `CaptureControlBarLayout` geometry instead of feeding a
measured child height back into parent layout. Camera and Audio use the fixed
250 pt full-screen overlay clearance because the full-bleed pager reports a zero
bottom safe-area inset. The primary and secondary capture controls share one
vertical centerline across every mode. Describe reserves the row's matching 204
pt height at the bottom of its UIKit-hosted content. Its flexible rounded editor
fills the space above the row and retains a 24 pt visual gap. At the top, the
hosted page uses an 82 pt selector band without adding another safe-area inset;
UIKit automatic content-inset adjustment is disabled. Together these boundaries
prevent the nested scroll, sheet, and preference feedback that previously formed
a startup AttributeGraph cycle when Description was the configured first mode.

Automatic single-capture submission owns its chrome transition explicitly.
Camera, video, and crop-confirmed commits set
`isAutomaticStagedSubmissionPending` in the same MainActor mutation that adds
the eligible staged media. While that ownership is active,
`shouldPresentActiveScanToolbar` keeps the ordinary `MainTabBar` mounted and
prevents the manual **Identify** tray from flashing before the asynchronous
admission task begins. Successful submission clears the staged buffer; a failed
admission attempt releases automatic ownership while retaining the media, so the
Active Scan toolbar intentionally returns as the user's retry path.

Image imports also cross admission before expensive or user-visible import work.
`PhotoLibraryButton` and the staged toolbar's add-photo action await
`requestImageImportEntryAdmission` before presenting the system picker, and a
pending external Photos/Files receipt runs the same check before metadata
extraction, image preparation, or required crop. Known quota/entitlement denial
therefore opens the paywall with no staged image or crop sheet; the durable
external-import receipt remains available for retry. This preview is read-only,
so crop confirmation and submission still perform the normal admission recheck
to catch a concurrent account/quota change. Once an import is allowed,
`shouldSuppressCaptureChromeForCrop` owns the visual handoff from the staged
commit through the required crop's dismissal. Both the capture row and bottom
navigation/Identify tray remain hidden while that fence is active.
`CropSheetModifier` is the only full-screen presentation owner; the workspace
does not add a transition canvas or input-blocking overlay during the handoff.
This keeps background/foreground scene changes from stranding a cover above the
app.

## Fresh-launch presentation

The Capture workspace remains the application root. When the default-off
`AppSettings.opensExploreOnLaunch` preference is enabled and onboarding is
complete, `MerianApp` creates `CaptureWorkspaceView` with `.explore` as its
initial root sheet. The preference is sampled once per process; scene activation
and foreground returns do not reevaluate it.

An initially presented Explore sheet must not start the camera underneath it.
After dismissal, the workspace restores the user's configured Scan, Record, or
Describe mode and starts only the hardware that mode requires.

Generic launch Explore is the lowest-priority route. Photos/Files image imports
dismiss it before staging and crop. Explore-post, community-request, scan, and
Scans-library routes replace it with their requested destination. External
routes arm the one-shot foreground-timeout suppression so the timeout reset
cannot erase the user intent that launched or reactivated the app.

All routed root destinations share `CameraSheetRouter`'s single item-based
sheet. Feature-local editors still use the presentation style appropriate to
their workflow: staged description and questions are sheets; staged video and
crop are covers; the feedback survey is a sheet. Each contributes to one
`isFeaturePresentationOccupied` fence. A global route claimed during any of
those workflows records `deferred(.presentationOccupied)` and resumes only from
the feature presentation's exact `onDismiss`. Routed-sheet interactive teardown
is fenced separately by `dismissingPresentation`. Do not substitute an elapsed
sleep for either callback.

The workspace is also the base visual-feedback host. It binds typed
`ToastPayload` state to `merianSystemFeedback`; passive toasts do not block the
viewfinder, and the modifier serializes ordinary feedback with the shared
milestone stack. Nested Explore, Insight, Scans, or Settings hosts temporarily
take exclusive milestone rendering ownership and restore this workspace host on
dismissal without restarting the item lifetime or effects.

## Active capture goal

`CaptureWorkspaceView` owns the compact active-outing target indicator because
it is fixed capture chrome alongside or beneath `MediaModeToggle`, not part of
the camera preview. It reads app-injected `ActiveCaptureGoalStore` state and
appears only when Field trips are enabled, the on-by-default
`AppSettings.showsCaptureGoalProgress` preference is enabled, visual Scan is
selected, a real unfinished target or validated introduction exists, the staging
tray is empty, refinement is inactive, and video is not recording. Turning the
setting off hides the entire capsule without deleting cached context or changing
outing progress. Loading with no cache renders nothing and never blocks camera
startup or capture.

Capture consumes only the generic `CaptureGoalContextSnapshot` read model, whose
active `CaptureGoal` values and optional `CaptureGoalIntroduction` remain
distinct. The first provider, `FieldTripCaptureGoalProvider`, owns conversion
from Field trip API DTOs, including exact artwork selection and the typed
`CaptureGoalDestination`. Adding another source must happen through that
provider/destination boundary; the camera must not import the source's network
models or reproduce its eligibility and ranking rules.

The accepted long-term boundary, second-source integration path, cache-version
rules, and alternatives are documented in
`docs/rfcs/active-capture-goal-context.md`.

With active targets, the indicator starts as a 50 by 50 pt artwork circle on the
same vertical centerline as `MediaModeToggle`, to its right while the selector
remains centered on screen. It matches the secondary capture-control diameter,
uses 42 pt artwork, and remains above the 44 pt minimum touch target. It keeps
the established 32 pt trailing workspace margin when space permits and
compresses that margin only enough to preserve an 8 pt gap on narrow phones. It
shows exact bundled goal artwork when mapped, otherwise a neutral binoculars
symbol. Tapping the artwork moves and expands the same glass surface to the full
goal row beneath the selector; its leading control returns to 56 pt with 36 pt
artwork. The centered `Goal: {target}` label and outing title then sit between
equal 56 pt artwork and up-chevron slots. Tapping the expanded artwork or
trailing chevron collapses the surface back onto the selector row, while tapping
the centered text region opens the outing.

Expansion is local to the current visual-Scan visit. It survives goal changes,
root sheets, foreground transitions, and temporary staging, refinement, or
recording suppression. Leaving visual Scan, switching or signing out of an
account, or disabling **Field trip goals** resets the next presentation to the
artwork-only circle. A horizontally dominant swipe on either size moves through
every unfinished target across active standard outings and wraps in both
directions. Opening uses the shared light sheet haptic; expansion, collapse, and
selection use selection feedback. All respect the global haptics and Expedition
mode settings. Reduced Motion makes the size change immediate. In compact form,
VoiceOver still announces the goal, outing, progress, expansion action, and
adjustable previous/next actions; in expanded form, the artwork and trailing
chevron expose Collapse while the centered region exposes Open and the
adjustable actions.

New and migrated accounts normally receive active Backyard Safari Level 1 goals
from the server. After a complete successful empty context, such as after Reset,
the provider looks up the accessible unstarted `backyard_safari` template by
slug. It then supplies the non-selectable **Start an outing** / **Backyard
Safari · 2 goals** introduction through the same collapsed artwork and expanded
title-and-chevron treatment. Its artwork cross-fades between Bird and Dog every
three seconds in either size and stays static under Reduce Motion. The rotation
keeps only its currently visible asset mounted between transitions, resets when
refreshed artwork changes, and uses the neutral binoculars fallback if a named
bundled asset cannot be resolved; the live camera's glass redraws therefore
never depend on a transparent sibling remaining renderable. A started,
completed, locked, missing, or empty template produces no introduction. The
introduction has no goal swipe or adjustable action. Its expanded content opens
outing detail without starting it, while its artwork toggles size.

The capsule is untinted interactive native Liquid Glass on iOS 26 and later.
Earlier supported versions use a neutral material fallback, and semantic
foreground styles preserve adaptive contrast without reintroducing a branded
fill.

`ActiveCaptureGoalStore` preserves the last successful generic payload,
introduction, and selected goal in a versioned cache per Supabase account.
Capture force-refreshes after relevant progress or routing invalidation events.
First appearance, account restoration/change, foreground return, and visual-mode
return all use the five-minute freshness path. Overlapping startup lifecycle
callbacks share the in-flight provider fetch instead of scheduling a duplicate
follow-up. Failures keep cached state without placing an error over the
viewfinder.

For a camera-only still submission, the selected standard-outing destination is
converted to an optional `FieldTripPreferredGoal` containing only the owned
`userFieldTripId` and checklist `itemId`. Selection is captured before the
staging tray hides the capsule and is carried through foreground or queued
completion. Gallery imports, Describe, Record, refinement, video, mixed media,
hidden goal UI, and missing selections submit no preference. The preference is
only a validated tie-breaker inside that outing; the server still determines
eligibility, may reject stale or unauthorized hints, and independently chooses
one goal for every other active outing or joined Event.

Tapping the pill calls `CaptureWorkspaceViewModel.openCaptureGoal`, then
`CameraSheetRouter` passes one typed destination to `ExploreView`. Explore owns
converting the Field trip destination into its optional focused checklist-item
route, selecting Field trips, opening the outing, expanding and highlighting the
matching Tips card, or highlighting the Goals tile when guide content is absent.
Introduction destinations use the existing authenticated `template_detail` slug
lookup and open the unstarted outing without focus. The complete data, privacy,
interaction, and deployment contract lives in
`docs/features-and-hardware/25-field-trips.md`.

The shared milestone banner reuses the same routing boundary. A Field trip
progress tap requests `AppRoute.captureGoal`; `AppRouteCoordinator` serializes
the request with any active root presentation, and `CaptureWorkspaceViewModel`
clears conflicting Explore destinations before opening the Explore sheet.
`.fieldTrip(templateId:checklistItemId:)` selects Outings and focuses the
credited goal, while `.fieldTripChallenge(challengeId:)` selects Events and
opens Seasonal Challenge detail. The refresh events emitted after progress
remain data invalidations only and must not create another Capture or Explore
toast.

The indicator emits privacy-safe `shown`, `opened`, `next`, `previous`,
`zero_state_shown`, and `zero_state_opened` telemetry through `AppTelemetry`.
Events include only the coarse source kind; goal IDs, prompts, outing
IDs/titles, progress, and account identity are excluded.

## External image imports

Naturebook's Merian iOS target declares `public.image` as an alternate document
type so a single photo shared from iOS Photos can open the main app. `MerianApp`
copies the incoming file into `ExternalImageImportStore` before submitting the
typed `processExternalImageImports` route to the capture workspace. The durable,
backup-excluded inbox allows the import and terminal intake feedback to survive
a cold launch or unfinished onboarding without retaining access to the
Photos-owned URL. Security scope begins before type validation, provider reads
are coordinated, and recovery reconciles interrupted copies and acknowledgement
tombstones.

`CaptureWorkspaceViewModel` consumes pending imports through the same
file-backed preparation path used by `PhotosPicker`. External imports preserve
embedded capture date and location when present, enforce the normal quota and
staging-capacity rules, require the gallery crop flow, and use the standard
online or offline scan submission pipeline. The same immutable historical
snapshot drives the immediate queue and foreground inference; gallery imports
never fall back to the device's current location or invent a missing embedded
capture date. Unsupported or unreadable images are removed from the inbox and
surface the standard capture feedback toast.

Quota-blocked receipts remain pending while the existing paywall is presented.
When Pro entitlement changes, the workspace dismisses that paywall, waits for
the matching root-sheet `onDismiss`, and only then retries admission. A direct
retry while the paywall is mounted or dismissing remains blocked, so crop can
never appear behind the paywall. A full capture tray keeps the receipt and shows
"Finish your current capture to import the shared photo." The workspace also
retries after staged media clears or the scene becomes active. Receipt
acknowledgement happens only after one staged image is committed or a decode
failure becomes terminal.

V1 intentionally supports one photo per Photos share action. It does not add a
Share Extension or promise availability for multi-photo selections.

The canonical routing, privacy, telemetry, and device-QA contract is
`docs/features-and-hardware/26-photos-share-import.md`.
