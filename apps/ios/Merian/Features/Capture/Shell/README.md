# Capture Shell

The `Shell` directory acts as the root container for the entire Capture feature.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the transitions between the different capture modes (`Scan`, `Record`, `Describe`). It acts as the routing layer, keeping the individual capture modes isolated and focused entirely on their specific hardware/input logic.

The horizontal mode pager uses a `LazyHStack`, so startup does not
unconditionally construct every off-screen page. The configured first mode is
selected during workspace initialization, and camera-session startup remains
gated on visual mode. Keep page sizing and `scrollTargetLayout()` on the lazy
stack when changing pager behavior.

Describe keeps its vertical scrolling behind a UIKit `UIScrollView` hosting
boundary. Its prompt/dictation lifecycle observer and questions sheet are owned
by `CaptureWorkspaceView`, outside the horizontal pager. Capture chrome derives
its clearance from fixed `CaptureControlBarLayout` geometry instead of feeding
a measured child height back into parent layout. Camera and Audio use the fixed
250 pt full-screen overlay clearance because the full-bleed pager reports a zero
bottom safe-area inset. The primary and secondary capture controls share one
vertical centerline across every mode. Describe reserves the row's matching
204 pt height at the bottom of its UIKit-hosted content. Its flexible rounded
editor fills the space above the row and retains a 24 pt visual gap. At the top,
the hosted page uses a 60 pt selector
band without adding another safe-area inset; UIKit automatic content-inset
adjustment is disabled. Together these boundaries prevent
the nested scroll, sheet, and preference feedback that previously formed a
startup AttributeGraph cycle when Description was the configured first mode.

## Fresh-launch presentation

The Capture workspace remains the application root. When the default-off
`AppSettings.opensExploreOnLaunch` preference is enabled and onboarding is
complete, `MerianApp` creates `CaptureWorkspaceView` with `.explore` as its
initial root sheet. The preference is sampled once per process; scene
activation and foreground returns do not reevaluate it.

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

## Active capture goal

`CaptureWorkspaceView` owns the compact active-outing target indicator because
it is fixed capture chrome beneath `MediaModeToggle`, not part of the camera
preview. It reads app-injected `ActiveCaptureGoalStore` state and appears only
when Field trips are enabled, the on-by-default
`AppSettings.showsCaptureGoalProgress` preference is enabled, visual Scan is
selected, a real unfinished target or validated introduction exists, the staging
tray is empty, refinement is inactive, and video is not recording. Turning the setting off hides the
entire capsule without deleting cached context or changing outing progress.
Loading with no cache renders nothing and never blocks camera startup or capture.

Capture consumes only the generic `CaptureGoalContextSnapshot` read model, whose
active `CaptureGoal` values and optional `CaptureGoalIntroduction` remain distinct.
The first provider,
`FieldTripCaptureGoalProvider`, owns conversion from Field trip API DTOs,
including exact artwork selection and the typed `CaptureGoalDestination`.
Adding another source must happen through that provider/destination boundary;
the camera must not import the source's network models or reproduce its
eligibility and ranking rules.

The accepted long-term boundary, second-source integration path, cache-version
rules, and alternatives are documented in
`docs/rfcs/active-capture-goal-context.md`.

With active targets, the pill shows exact bundled objective artwork when mapped, otherwise a neutral
binoculars symbol. A centered `Goal: {target}` label and the outing title sit
between equal-width artwork and progress slots; the trailing circular
ring shows `completed/target` and replaces the disclosure caret. The capsule
matches the visual width of `MediaModeToggle`. A horizontally dominant swipe
moves through every unfinished target across active standard outings and wraps
in both directions. Tapping uses the shared light sheet-opening haptic, while
selection changes use selection feedback. Both respect the global haptics and
Expedition mode settings. Reduced Motion and VoiceOver adjustable actions remain
supported.

New and migrated accounts normally receive active Backyard Safari Level 1 goals
from the server. After a complete successful empty context, such as after Reset,
the provider looks up the accessible unstarted `backyard_safari` template by
slug. It then supplies the non-selectable
**Start an outing** / **Backyard Safari · 2 goals** introduction with a `0/2`
ring. Its leading artwork cross-fades between Bird and Dog every three seconds
and stays static under Reduce Motion. The rotation keeps only its currently
visible asset mounted between transitions, resets when refreshed artwork
changes, and uses the neutral binoculars fallback if a named bundled asset
cannot be resolved; the live camera's glass redraws therefore never depend on
a transparent sibling remaining renderable. A started, completed, locked,
missing, or empty template produces no introduction. The introduction has no
swipe or adjustable action and opens outing detail without starting it.

The capsule is untinted interactive native Liquid Glass on iOS 26 and later.
Earlier supported versions use a neutral material fallback, and semantic
foreground styles preserve adaptive contrast without reintroducing a branded
fill.

`ActiveCaptureGoalStore` preserves the last successful generic payload,
introduction, and selected goal in a versioned cache per Supabase account. Capture force-refreshes
after relevant progress or routing invalidation events. First appearance,
account restoration/change, foreground return, and visual-mode return all use
the five-minute freshness path. Overlapping startup lifecycle callbacks share
the in-flight provider fetch instead of scheduling a duplicate follow-up.
Failures keep cached state without placing an error over the viewfinder.

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
route, selecting Field trips, opening the outing, expanding and highlighting
the matching Tips card, or highlighting the Goals tile when guide content
is absent. Introduction destinations use the existing authenticated
`template_detail` slug lookup and open the unstarted outing without focus. The complete data, privacy, interaction, and deployment contract
lives in `docs/features-and-hardware/25-field-trips.md`.

The shared milestone banner reuses the same routing boundary. A Field trip
progress tap requests `AppRoute.captureGoal`; `AppRouteCoordinator` serializes
the request with any active root presentation, and
`CaptureWorkspaceViewModel` clears conflicting Explore destinations before
opening the Explore sheet. `.fieldTrip(templateId:checklistItemId:)` selects
Outings and focuses the credited goal, while
`.fieldTripChallenge(challengeId:)` selects Events and opens Seasonal Challenge
detail. The refresh events emitted after progress remain data invalidations
only and must not create another Capture or Explore toast.

The indicator emits privacy-safe `shown`, `opened`, `next`, `previous`,
`zero_state_shown`, and `zero_state_opened`
telemetry through `AppTelemetry`. Events include only the coarse source kind;
goal IDs, prompts, outing IDs/titles, progress, and account identity are
excluded.

## External image imports

Naturebook's Merian iOS target declares `public.image` as an alternate document
type so a single photo shared from iOS Photos can open the main app. `MerianApp`
copies the incoming file into `ExternalImageImportStore` before submitting the
typed `processExternalImageImports` route to the capture workspace.
The durable, backup-excluded inbox allows the import and terminal intake
feedback to survive a cold launch or unfinished onboarding without retaining
access to the Photos-owned URL. Security scope begins before type validation,
provider reads are coordinated, and recovery reconciles interrupted copies and
acknowledgement tombstones.

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
A full capture tray keeps the receipt and shows "Finish your current capture to
import the shared photo." The workspace retries after staged media clears, the
scene becomes active, or Pro entitlement changes. Receipt acknowledgement
happens only after one staged image is committed or a decode failure becomes
terminal.

V1 intentionally supports one photo per Photos share action. It does not add a
Share Extension or promise availability for multi-photo selections.

The canonical routing, privacy, telemetry, and device-QA contract is
`docs/features-and-hardware/26-photos-share-import.md`.
