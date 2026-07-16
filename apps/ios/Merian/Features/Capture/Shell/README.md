# Capture Shell

The `Shell` directory acts as the root container for the entire Capture feature.

## Purpose
Following the Merian architecture guidelines, the `Shell` orchestrates the transitions between the different capture modes (`Scan`, `Record`, `Describe`). It acts as the routing layer, keeping the individual capture modes isolated and focused entirely on their specific hardware/input logic.

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
