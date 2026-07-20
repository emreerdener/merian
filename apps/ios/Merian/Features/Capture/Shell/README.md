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
by `CaptureWorkspaceView`, outside the horizontal pager. The capture bar also
publishes the fixed `CaptureControlBarLayout.reservedHeight` instead of feeding a
measured child height back into parent layout. Together these boundaries prevent
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
Describe mode and starts only the hardware that mode requires. Explore's
appearance also sets `AppSettings.hasSeenExploreNewChip` so an automatically
opened feed does not leave the one-time **New** chip behind.

Generic launch Explore is the lowest-priority route. Photos/Files image imports
dismiss it before staging and crop. Explore-post, community-request, scan, and
Scans-library routes replace it with their requested destination. External
routes arm the one-shot foreground-timeout suppression so the timeout reset
cannot erase the user intent that launched or reactivated the app.

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

After a complete successful empty context, the provider looks up the accessible
unstarted `backyard_safari` template by slug. It then supplies the non-selectable
**Start an outing** / **Backyard Safari · 4 goals** introduction with a `0/4`
ring. Its leading artwork cross-fades through the first-level goals every three
seconds and stays static under Reduce Motion. A started, completed, locked,
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

Tapping the pill calls `CaptureWorkspaceViewModel.openCaptureGoal`, then
`CameraSheetRouter` passes one typed destination to `ExploreView`. Explore owns
converting the Field trip destination into its optional focused checklist-item
route, selecting Field trips, opening the outing, expanding and highlighting
the matching Tips card, or highlighting the Goals tile when guide content
is absent. Introduction destinations use the existing authenticated
`template_detail` slug lookup and open the unstarted outing without focus. The complete data, privacy, interaction, and deployment contract
lives in `docs/features-and-hardware/25-field-trips.md`.

The shared milestone banner reuses the same routing boundary. A Field trip
progress tap publishes `requestOpenCaptureGoal`; `CaptureWorkspaceViewModel`
clears conflicting Explore destinations and opens the Explore sheet with the
typed route. `.fieldTrip(templateId:checklistItemId:)` selects Outings and
focuses the credited goal, while `.fieldTripChallenge(challengeId:)` selects
Events and opens Seasonal Challenge detail. The refresh events emitted after
progress remain data invalidations only and must not create another Capture or
Explore toast.

The indicator emits privacy-safe `shown`, `opened`, `next`, `previous`,
`zero_state_shown`, and `zero_state_opened`
telemetry through `AppTelemetry`. Events include only the coarse source kind;
goal IDs, prompts, outing IDs/titles, progress, and account identity are
excluded.

## External image imports

Naturebook's Merian iOS target declares `public.image` as an alternate document
type so a single photo shared from iOS Photos can open the main app. `MerianApp`
copies the incoming file into `ExternalImageImportStore` before notifying the
capture workspace.
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
