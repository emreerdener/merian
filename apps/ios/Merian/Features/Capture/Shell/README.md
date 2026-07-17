# Capture Shell

The `Shell` directory acts as the root container for the entire Capture feature.

## Purpose

Following the Merian architecture guidelines, the `Shell` orchestrates the transitions between the different capture modes (`Scan`, `Record`, `Describe`). It acts as the routing layer, keeping the individual capture modes isolated and focused entirely on their specific hardware/input logic.

## Active capture goal

`CaptureWorkspaceView` owns the compact active-outing target indicator because
it is fixed capture chrome beneath `MediaModeToggle`, not part of the camera
preview. It reads app-injected `ActiveCaptureGoalStore` state and appears only
when Field Trips are enabled, visual Scan is selected, a real unfinished target
exists, the staging tray is empty, refinement is inactive, and video is not
recording. Loading with no cache renders nothing and never blocks camera startup
or capture.

Capture consumes only the generic `CaptureGoal` read model. The first provider,
`FieldTripCaptureGoalProvider`, owns conversion from Field Trip API DTOs,
including exact artwork selection and the typed `CaptureGoalDestination`.
Adding another source must happen through that provider/destination boundary;
the camera must not import the source's network models or reproduce its
eligibility and ranking rules.

The accepted long-term boundary, second-source integration path, cache-version
rules, and alternatives are documented in
`docs/rfcs/active-capture-goal-context.md`.

The pill shows exact bundled objective artwork when mapped, otherwise a neutral
binoculars symbol, plus the objective prompt and
`Outing title · completed/target complete`. A horizontally dominant swipe moves
through every unfinished target across active standard outings and wraps in both
directions. Selection changes support haptics, Reduced Motion, and VoiceOver
adjustable actions.

`ActiveCaptureGoalStore` preserves the last successful generic payload and
selected goal in a versioned cache per Supabase account. Capture force-refreshes
on first appearance and
relevant invalidation events, and refreshes after five stale minutes on
foreground/visual-mode return. Failures keep cached state without placing an
error over the viewfinder.

Tapping the pill calls `CaptureWorkspaceViewModel.openCaptureGoal`, then
`CameraSheetRouter` passes one typed destination to `ExploreView`. Explore owns
converting the Field Trip destination into its optional focused checklist-item
route, selecting Field Trips, opening the outing, expanding and highlighting
the matching Tips card, or highlighting the Objectives tile when guide content
is absent. The complete data, privacy, interaction, and deployment contract
lives in `docs/features-and-hardware/25-field-trips.md`.

The indicator emits privacy-safe `shown`, `opened`, `next`, and `previous`
telemetry through `AppTelemetry`. Events include only the coarse source kind;
goal IDs, prompts, outing IDs/titles, progress, and account identity are
excluded.

## External image imports

Merian declares `public.image` as an alternate document type so a single photo
shared from iOS Photos can open the main app. `MerianApp` copies the incoming
file into `ExternalImageImportStore` before notifying the capture workspace.
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
