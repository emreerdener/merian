# Photos Share Import

Naturebook can receive one image from the iOS Photos share sheet and route it
into the normal visual-identification workflow. This is an app-owned document
import, not a Share Extension: selecting Naturebook opens the containing app,
the app copies the incoming file into its own durable inbox, and the Capture
workspace stages the copy through the same bounded preparation pipeline used by
`PhotosPicker`.

## Product Contract

- V1 supports one photo per share action. Naturebook is not required to appear
  when multiple Photos items are selected.
- The Photos original is never edited. Naturebook imports and processes its own
  copy.
- A required square crop is presented before submission.
- The existing scan quota, Pro entitlement, confirmation preference, inference,
  and offline-queue rules remain authoritative.
- The caller-scoped scan-admission preview runs before the durable copy is read
  or prepared, so a known denial reaches the paywall before crop work.
- No Share Extension, backend endpoint, database migration, App Group handoff,
  or new Photo Library permission is part of this feature.

The user-facing release-note wording is:

> Share a photo from Photos directly to Naturebook for identification.

## iOS Registration and URL Routing

`apps/ios/Merian/Configuration/Info.plist` registers one `CFBundleDocumentTypes`
entry:

| Key                                 | Value          | Reason                                                                 |
| ----------------------------------- | -------------- | ---------------------------------------------------------------------- |
| `LSItemContentTypes`                | `public.image` | Advertises support for image files.                                    |
| `CFBundleTypeRole`                  | `Viewer`       | Naturebook consumes the file without editing the source.               |
| `LSHandlerRank`                     | `Alternate`    | Naturebook is an optional handler, not the default image viewer.       |
| `LSSupportsOpeningDocumentsInPlace` | `false`        | The app owns an imported copy and never writes to the Photos original. |

`MerianApp.onOpenURL` preserves the existing routing precedence:

1. Google Sign-In receives the URL first.
2. Supported `naturebook://` and legacy `merian://` deep links are handled next.
3. File URLs are handed to the document-import store.
4. Remaining URLs continue to Supabase authentication.

The store acquires security-scoped access before querying the resolved `UTType`
or coordinating the copy. A conforming resource type is preferred; the filename
extension remains a fallback for provider URLs that expose only a generic type.
Non-file OAuth, Universal Link, and custom-scheme behavior remains unchanged.
Unsupported file URLs produce error feedback and are not forwarded to Supabase
as authentication callbacks.

## Durable Pending-Import Inbox

`ExternalImageImportStore` is an actor in
`apps/ios/Merian/Core/Data/Images/ExternalImageImportStore.swift`. Its default
inbox is the app's Application Support directory under `ExternalImageImports/`.
The store owns:

- a uniquely named copy of every accepted incoming image;
- an atomically written `pending-image-imports.json` recovery journal;
- FIFO recovery through `PendingExternalImageImport.receivedAt`; and
- tombstoned acknowledgement and cleanup after the capture workspace takes
  ownership.

The source URL may be temporary or security scoped. The store starts
security-scoped access before type validation, coordinates the read for file
providers and iCloud-backed items, copies through a temporary filename while
that access is active, and stops access immediately afterward. It never persists
the source URL, a Photos asset identifier, or a bookmark. The inbox is excluded
from device backups and accepts at most eight pending receipts.

Recovery reconciles disk and journal state on every read. Interrupted
`.incoming-*` copies are deleted, a completed UUID-named copy left by a process
termination is adopted into the journal, missing files are pruned, and unknown
files are removed. Acknowledgement first commits a filename tombstone, then
deletes the file; a deletion interrupted by suspension is retried on the next
reconciliation and cannot reappear as a pending import.

The durable copy allows an import to survive cold launch, app suspension, or
unfinished onboarding. Terminal intake feedback is journaled as well, so an
unsupported file or provider-copy failure received during onboarding is shown
once the Capture workspace exists. A pending file is retained while import is
temporarily blocked and is removed only after successful staging or a terminal
missing/unreadable-image failure. Once the image is staged, the normal staging
and crop lifecycle owns it; cancelling the required crop removes the staged item
and does not restore the inbox receipt.

## Capture Workspace Handoff

After a durable copy succeeds, `MerianApp` requests
`AppRoute.processExternalImageImports` with a `.durableExternalImport` source.
`CaptureWorkspaceViewModel` also checks the inbox when the workspace appears or
the scene becomes active, so a missed process-local request during cold launch
or onboarding does not lose the import.

An image handoff is an explicit launch intent. If the default-off **Open Explore
on launch** preference initialized the workspace with the generic Explore feed,
the confirmed import dismisses that presentation before staging the image and
presenting its crop. The handoff arms the same one-shot timeout-reset protection
used by external deep links so the foreground timeout cannot clear the newly
staged crop; the durable inbox remains the source of truth if the UI request is
missed.

The retry triggers are:

- the Capture workspace becoming available;
- the app returning to an active scene;
- the current staged-item count decreasing; and
- the configured staged-item limit increasing; and
- the RevenueCat Pro entitlement changing.

`CaptureWorkspaceViewModel.importPendingExternalImageIfPossible()` processes the
oldest pending receipt. It snapshots the normal gallery budget before expensive
work, then awaits `requestImageImportEntryAdmission` before reading metadata or
decoding the file. A known server denial leaves the receipt untouched and opens
the paywall with no staged image or crop. If Pro entitlement later changes, the
workspace dismisses the paywall and waits for its matching root-sheet
`onDismiss` before retrying the retained receipt. Admission remains blocked
while that paywall is mounted or dismissing, preventing crop from appearing
behind it. An allowed or offline queue-only route prepares the image through the
shared file-backed `PreparedStagedImageLoader`, checks capacity and quota again
after preparation, and commits exactly one item with `requiresCrop: true`.
Submission repeats the admission preview because the entry check is advisory and
reserves no quota.

After the required crop:

- default single-capture mode auto-submits when "Confirm scan submission" is
  disabled;
- confirmation-enabled mode leaves the cropped photo in the Active Scan toolbar
  until the user taps Identify;
- multi-capture mode retains the normal staged-media behavior; and
- online and offline submissions use the existing durable scan queue and
  `/identify-multimodal` contract.

## Metadata and Privacy

ImageIO extracts metadata from the durable original before
`MediaPreparationActor` downsamples and re-encodes the image. The extractor
accepts EXIF original/digitized/TIFF capture dates and a complete, valid GPS
latitude/longitude pair with hemisphere references.

Metadata combinations are intentionally additive:

| Embedded metadata                 | Result                                                                           |
| --------------------------------- | -------------------------------------------------------------------------------- |
| Capture date and GPS              | Use the existing historical reverse-geocode and WeatherKit path.                 |
| Capture date only                 | Preserve the date without adding coordinates, place, or weather.                 |
| GPS only                          | Preserve the coordinates without inventing a capture date or historical weather. |
| Neither, incomplete, or malformed | Import the image without historical context.                                     |

The staged image's historical context is snapshotted once and drives both the
immediate durable queue record and foreground inference. Gallery imports never
consult `EnvironmentContextManager.lastKnownLocation` or a camera prefetch. The
queue's visual-media manifest persists local-only gallery provenance and whether
an embedded capture date existed; those fields are not included in the edge
request's visual-media JSON. This lets offline replay keep a required internal
queue-ordering date while omitting `telemetry.timestamp` when the photo had no
embedded date.

When a user disables Location in Photos' share Options, the delivered file has
no usable GPS dictionary and Naturebook imports it without coordinates.
Receiving a shared image does not grant broad access to the user's Photo
Library. Naturebook reads only the file explicitly handed to it by iOS, and this
route adds no Photo Library permission prompt.

The `ExternalImageImport` telemetry event contains only `outcome` and the shared
`event_source = "ios_client"` property. Supported outcomes cover receipt,
staging, quota blocking, staging-capacity blocking, and coarse failure classes.
Telemetry must never include filenames, local paths, image bytes, EXIF values,
coordinates, capture dates, asset identifiers, scan IDs, or user IDs.

## Blocking and Failure Behavior

| State                                    | User experience                                                                      | Inbox ownership                             |
| ---------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------- |
| Local or server quota/entitlement denial | Present the existing paywall before metadata extraction, image preparation, or crop. | Retain and retry after entitlement changes. |
| Capture tray full                        | Show "Finish your current capture to import the shared photo."                       | Retain and retry after staged media clears. |
| Unsupported or unreadable image          | Trigger error haptics and show "Naturebook couldn’t import that photo."              | Remove as a terminal failure.               |
| Preparation succeeds                     | Present the required crop.                                                           | Remove after the staged item is committed.  |

Blocking feedback is de-duplicated per pending import so foreground and
entitlement retries do not repeatedly open the paywall or spam the capacity
toast.

## Verification

Automated coverage lives in:

- `apps/ios/MerianTests/Core/Data/ExternalImageImportStoreTests.swift` for URL
  routing precedence, security-scope ordering, durable copy/recovery,
  interrupted-copy reconciliation, acknowledgement, onboarding-safe failure
  feedback, real ImageIO fixtures, EXIF combinations, and current-location
  exclusion;
- `apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift` for durable
  gallery provenance and offline replay with and without an embedded date;
- `CaptureWorkspaceViewModelRefinementTests` for successful staging and cleanup,
  capacity retention/retry, local and server admission retention before crop,
  Pro entitlement retry, and terminal unreadable-image cleanup. Its
  launch-routing case also starts with generic Explore presented, injects a
  pending image and timeout event, and verifies the import wins, remains staged,
  and presents the crop; and
- `apps/ios/MerianTests/Core/Analytics/AppTelemetryTests.swift` for the
  privacy-safe telemetry property set.

Useful focused validation:

```bash
make xcodegen
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
jq empty apps/ios/Merian/Resources/Changelog/changelog.json
git diff --check
```

The Photos app row and security-scoped/iCloud handoff require a physical iPhone.
Before release, share one JPEG, HEIC, PNG, and iCloud-backed photo; confirm
Naturebook opens, the crop appears, included date/location is preserved,
excluded Location is absent, a known admission denial shows the paywall before
crop while retaining the receipt, capacity blocks retain the import, and both
online and offline submission complete. Also confirm Naturebook is not required
to appear for a multi-photo selection and that `Payload/Merian.app/PlugIns/`
contains no Photos Share Extension.
