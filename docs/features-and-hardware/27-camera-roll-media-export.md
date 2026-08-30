# Camera Roll and Captured-Media Export

Last reviewed: 2026-08-29.

Naturebook can write captured photos and videos to the user's iOS Photos
library. Automatic capture saves and explicit **Download** actions share the
same PhotoKit bridge, but intentionally follow different preference and source
quality rules.

This feature is implemented entirely in the iOS client. It does not change the
backend, database schema, upload contract, or the media-import surface.

## Product Contract

| Path              | Trigger                                                    | Honors `saveToCameraRoll` | Video source              | Location added by Naturebook              |
| ----------------- | ---------------------------------------------------------- | ------------------------: | ------------------------- | ----------------------------------------- |
| Automatic capture | Capture completes while **Save to camera roll** is enabled |                       Yes | Original camera recording | Resolved shutter location, when available |
| Single download   | **Download scan** in Insight                               |                        No | Retained playback clip    | No                                        |
| Batch download    | **Download** for selected scans in the Scan Library        |                        No | Retained playback clips   | No                                        |

The persisted setting remains `UserDefaultsKeys.saveToCameraRoll`. It defaults
to `false`. Turning it off prevents both automatic photo and automatic video
writes without changing Naturebook's normal local persistence or upload flow.

An explicit Download is a direct user request and therefore works regardless of
the automatic-save setting. It still requires add-only Photos authorization.

## Photos Permission

All writes request `PHAccessLevel.addOnly`. Naturebook does not request broad
read access merely to save media. The Settings toggle presents the existing
permission explainer before the system prompt and becomes enabled only after
add-only access is authorized.

The add-purpose string is declared by `NSPhotoLibraryAddUsageDescription` in
`apps/ios/Merian/Configuration/Info.plist` and describes both photos and videos.
Photo import remains a separate read/write permission path.

Permission outcomes follow these rules:

- `.authorized` and `.limited` may proceed;
- `.notDetermined` requests add-only authorization;
- `.denied` and `.restricted` return a failed save without deleting retained
  Naturebook media; and
- a denied automatic save does not block video preparation, staging, or scan
  submission.

## Shared PhotoKit Write Bridge

`PhotoLibraryManager` routes writes through a media-aware helper. The
`PhotoLibraryMediaKind` value maps directly to the corresponding
`PHAssetResourceType`:

| Media kind | PhotoKit resource | Input behavior                                                                      |
| ---------- | ----------------- | ----------------------------------------------------------------------------------- |
| `.photo`   | `.photo`          | Accepts resident `Data` or a file URL; removes inherited GPS metadata before import |
| `.video`   | `.video`          | Uses the source file URL unchanged; does not decode or load the clip into memory    |

The helper creates a `PHAssetCreationRequest`, adds the resource, assigns an
optional `request.location`, and awaits
`PHPhotoLibrary.shared().performChanges`. A caller may release or delete a
source video only after that await completes.

The implementation follows PhotoKit's file-backed resource API:
[Apple: `PHAssetCreationRequest.addResource(with:fileURL:options:)`](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource%28with%3Afileurl%3Aoptions%3A%29).

### Automatic and Manual Interfaces

Automatic methods obey the setting:

```swift
saveImageToLibrary(imageData:location:)
saveVideoToLibrary(fileURL:location:)
```

Manual methods represent explicit downloads and bypass the setting:

```swift
saveImageManual(imageData:)
saveImageManual(fileURL:)
saveVideoManual(fileURL:)
```

Every method continues to use add-only Photos access.

## Photo Privacy and Location Behavior

Photo writes preserve the established privacy boundary. Before PhotoKit sees a
photo resource, ImageIO removes the source GPS dictionary with
`kCGImageMetadataShouldExcludeGPS` semantics. File-backed photos are rewritten
to a temporary scrubbed file so a large image is not round-tripped through
resident `Data`.

For an automatic camera capture, Naturebook separately assigns the resolved
shutter location to the new Photos asset through
`PHAssetCreationRequest.location`. This keeps location assignment controlled by
the capture pipeline rather than trusting inherited image metadata. The current
location request and `lastKnownLocation` fallback are unchanged.

Manual downloads do not attach location from `LocalScanRecord` or other scan
telemetry. Video files remain byte-for-byte unmodified by the PhotoKit bridge,
so any metadata already contained in a retained or downloaded clip is not
scrubbed or rewritten.

Camera-roll writes are owner-controlled local exports. Public Explore,
geoprivacy, and Darwin Core projections remain separate boundaries.

## Automatic Video Source Lifetime

Automatic saving deliberately imports the original camera recording, not the
network-optimized playback export. Saving begins as soon as recording and
shutter-location resolution finish, while frame sampling, audio extraction, and
playback-clip preparation continue concurrently.

```text
original recording completes
        |-- PhotoKit imports original .video ------------------|
        |-- sample frames -> extract audio -> prepare playback |
                                                            await both
                                                                |
                                      delete original only when a
                                      separate playback clip exists
```

The capture task retains the original file URL and the PhotoKit task handle.
Normal completion, cancellation, timeout, and preparation failure all await the
PhotoKit task before removing the original. This prevents compression cleanup
from invalidating a file while PhotoKit is importing it.

After a prepared clip crosses into `StagedCapture`, Scan finalizes that
recording generation and removes its cancel affordance before awaiting the
PhotoKit task. The local capture task continues to own the original URL and save
handle until PhotoKit returns. This prevents a user action from cancelling media
that is already staged without shortening the original source lifetime.

If playback preparation falls back to the original recording, that file becomes
the retained playback clip and is not deleted by the successful capture path.

## Single and Batch Downloads

`InsightMediaExportManager` converts UI- and SwiftData-bound records into a
`Sendable` `SaveMediaPayload` before work crosses into `ExportProcessingActor`.
The payload keeps media classes explicit:

```swift
localImageURLs
approvedRemotePhotoURLs
localVideoURLs
approvedRemoteVideoURLs
```

Single and batch Download actions may save:

- a live photo buffer;
- local captured-photo files;
- local retained playback-video files;
- approved remote captured photos and videos; and
- the existing approved reference photo associated with a scan.

Audio recordings, descriptions, sampled video inference frames, and video poster
thumbnails are not exported as separate user captures.

### Local URL Resolution

The media resolver accepts:

- absolute sandbox paths;
- `file://` URLs; and
- relative filenames resolved under `URL.documentsDirectory`.

Values with a non-file URL scheme are never interpreted as local paths.

### Approved Remote Media

Remote download is restricted to HTTPS URLs whose exact normalized host is
`media.merian.app`. Subdomains, suffix lookalikes, and external reference hosts
are skipped. This preserves the existing rule that Wikipedia, GBIF, and other
third-party reference URLs are not fetched as arbitrary export resources.

`URLSession.download` writes each approved response to a temporary file. The
actor passes that file URL directly to `PhotoLibraryManager`, awaits the
PhotoKit transaction, and removes the download file in `defer` on success, HTTP
failure, or PhotoKit failure. Remote videos are never materialized as `Data`.

## Results and User Feedback

`MediaSaveResult` records attempted and saved counts independently:

```swift
photosAttempted
photosSaved
videosAttempted
videosSaved
```

Feedback is derived from the successful photo/video counts:

- photo-only: `Saved 1 photo to your camera roll.`
- video-only: `Saved 2 videos to your camera roll.`
- mixed: `Saved 1 photo and 1 video to your camera roll.`
- partial: append `Some items couldn't be saved.`
- zero saved: show `No photos or videos could be saved` with an error haptic.

The Insight action uses an alert; batch library downloads use the existing
toast. Both clear their loading state after completion.

## Ownership and Cleanup

| File                                                 | Owner before save               | Cleanup rule                                                                                             |
| ---------------------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Original camera video                                | Capture task                    | Await automatic PhotoKit import before deleting; retain when it is the playback fallback                 |
| Unaccepted generated WAV or compressed playback clip | `CaptureScanTemporaryFileLease` | Delete on cancellation, timeout, validation failure, supersession, or release without staging acceptance |
| Retained playback video                              | Scan staging/persistence        | Never delete as part of a manual Photos export                                                           |
| Approved remote download                             | Export actor                    | Delete after the awaited PhotoKit write returns                                                          |
| Scrubbed temporary photo                             | `PhotoLibraryManager`           | Delete after the awaited PhotoKit write returns                                                          |

PhotoKit failure never grants an export path permission to delete a retained
playback clip or persisted local photo.

## Failure Behavior

| Condition                           | Result                                                             |
| ----------------------------------- | ------------------------------------------------------------------ |
| Automatic setting disabled          | Skip the write without requesting Photos access                    |
| Add-only permission denied          | Record failure; preserve Naturebook media                          |
| Missing local file                  | Record failure and continue remaining items                        |
| Unapproved remote host              | Skip the URL                                                       |
| Remote non-2xx response             | Record failure and remove the temporary download                   |
| Download cancellation/network error | Record failure and continue or return normally                     |
| PhotoKit import failure             | Record failure; remove only export-owned temporary files           |
| Video preparation failure           | Await any automatic PhotoKit import before original-source cleanup |

## Automated Verification

Focused coverage lives in:

- `PhotoLibraryManagerTests.swift` for default-off automatic photo/video
  behavior, `.photo`/`.video` resource selection, source-video retention, and
  image GPS scrubbing;
- `CaptureScanTemporaryFileLeaseTests.swift` and `DetachedWorkTests.swift` for
  unaccepted-artifact cleanup, explicit ownership transfer, and propagation of
  parent cancellation into detached media work;
- `InsightMediaExportManagerTests.swift` for local/approved remote image/video
  payloads, unapproved-host filtering, and mixed/partial result copy; and
- `services/supabase/scripts/documentation_contract_test.ts` for maintained
  documentation links and current media-export entry-point names.

Run the focused suites with a valid simulator identifier:

```bash
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj \
  -destination 'id=<SIMULATOR_ID>' \
  -only-testing:merianTests/PhotoLibraryManagerTests \
  -only-testing:merianTests/CaptureScanTemporaryFileLeaseTests \
  -only-testing:merianTests/DetachedWorkTests \
  -only-testing:merianTests/InsightMediaExportManagerTests test

deno test --config services/supabase/functions/deno.json --frozen \
  --allow-read=. \
  services/supabase/scripts/documentation_contract_test.ts
```

## Physical-iPhone Release Checklist

PhotoKit writes and recorded-video audio require physical-device confirmation.
Before release, verify:

1. With **Save to camera roll** off, capture a photo and a video and confirm
   neither appears in Photos.
2. Turn the setting on through the add-only permission explainer and confirm
   full-resolution camera photos and original-quality videos appear in Photos.
3. Play an automatically saved video with sound and inspect its duration,
   orientation, and location.
4. Download a retained video from Insight with the automatic setting off and
   confirm the playback representation and audio are saved.
5. Download video-only and mixed-media scans, then batch-download local and
   cloud-backed selections.
6. Deny Photos access and confirm automatic capture preparation still succeeds,
   manual Download reports zero saved, and retained media remains playable.
7. Cancel video staging, force playback compression failure, and exercise each
   preparation timeout; confirm the original file remains available until the
   PhotoKit transaction finishes.
8. Confirm approved cloud downloads leave no export-owned temporary files and
   unapproved remote hosts are skipped.
9. Regression-test automatic photo location, photo GPS scrubbing, manual photo
   export, and reference-photo export.

## Out of Scope

- Importing videos from Photos.
- Permanently retaining every original camera recording inside Naturebook.
- Replacing the upload-bounded retained playback clip with the original.
- Backend, database, R2, moderation, or upload-contract changes.
