# Image Pipeline

This document traces the full journey of an image from physical shutter press to
on-screen render, identifying the OOM risk at each step and the mechanism that
mitigates it.

---

## Capture → Disk

### 1. AVFoundation Buffer (`CameraManager`)

`CameraManager` receives raw `CMSampleBuffer` frames from the AVFoundation
`captureOutput` delegate on a dedicated
`DispatchQueue(label: "camera.session")`.

- **OOM risk**: Decoding a full 12–48 MP `CMSampleBuffer` without throttling
  instantly spikes RAM and triggers JetSam.
- **Mitigation**: An atomic
  `nonisolated(unsafe) private var activeInferencePaused` boolean short-circuits
  the entire `captureOutput` pipeline when the viewfinder AI is halted. No
  histogram allocation occurs for a paused session. Additionally,
  `defer { CVPixelBufferUnlockBaseAddress }` is unconditionally applied to
  prevent AVFoundation buffer leaks.

### 2. Dual-Path Preparation (`MediaPreparationActor` + `ImageDownsampler`)

Every capture produces **two independent downsampled images** from the same raw
source buffer. The two paths serve different purposes and are sized accordingly.

| Path          | Constant                                           | Size                                                      | Destination                                                                                                 |
| ------------- | -------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Inference** | `MerianConfig.inferenceImageMaxSize(isProActive:)` | **768 px** (Flash/free) or **1024 px** (Pro) longest edge | Base64-encoded and sent to Gemini; discarded after encoding (scan durability is owned by the offline queue) |
| **Display**   | `MerianConfig.displayImageMaxSize`                 | 2048 px longest edge                                      | Written to disk by `FileIOActor`; read by the insight sheet carousel and scan library                       |

For file-backed still images, `MediaPreparationActor` is the policy boundary.
Gallery imports, refinement staging, and avatar crop previews send only file
URLs into the actor. The actor owns the two bounded `ImageDownsampler` passes,
WebP/JPEG encoding, non-empty checks, and `MediaPreparationMetrics` assertions
for byte count and pixel dimensions. Callers receive only bounded inference
bytes, bounded display bytes, and a sendable preview `CGImage`; they do not
receive the original file bytes or a full-resolution `UIImage`.

After downsampling, a **composing-zone-aware square crop** is applied to both
payloads before WebP encoding. The crop geometry is calculated from the
on-screen UI layout: `CaptureWorkspaceView` measures the vertical center of the
composing zone (the open area between the mode toggle at the top and the capture
button row plus a 16 pt framing margin at the bottom) using the existing
full-screen `GeometryReader` and stores it as
`CaptureWorkspaceViewModel.composingZoneVerticalCenter` (a fraction of screen
height, e.g. ~0.42 on iPhone 15 Pro). This calculation is fixed geometry rather
than a child-height preference; if `CaptureControlBarLayout` changes, review the
crop margin at the same time.
`ImageCropProcessor.squareCrop(_:verticalCenterFraction:)` then crops each
downsampled `CGImage` to the largest centered square, biasing the crop center to
that fraction rather than 0.5 (geometric center). This aligns what Gemini
analyzes with where the user actually framed their subject, rather than the dead
center of the sensor image — a meaningful correction on tall-screen iPhones
where the bottom chrome (shutter row + tab bar) occupies significantly more
vertical space than the top chrome (mode toggle).

Three staging buffers are populated in `CaptureWorkspaceViewModel` after each
capture or gallery pick (consolidated into
`StagedCapture.images: [StagedImage]`):

- `StagedImage.compressedData` — tier-conditional inference payloads: 768 px
  (Flash/free) or 1024 px (Pro), square-cropped WebP `Data`
- `StagedImage.displayData` — 2048 px display payloads (square-cropped WebP
  `Data`, same geometry)
- `StagedImage.uiImage` — in-memory `UIImage` thumbnails for the Active Scan
  Toolbar. The camera path wraps the already-decoded `CGImage` directly; the
  gallery path reconstructs the image once during the final main-actor commit
  from the prepared inference payload.
- `StagedImage.focusRegion` — optional transient top-left-normalized objectness
  saliency bounds from Vision. It is a tentative attention hint for queue and
  inference context, not proof of the intended primary subject and not
  completed-scan storage.

### Automatic focus metadata

`ImageFocusRegionDetector` runs `VNGenerateObjectnessBasedSaliencyImageRequest`
revision 2 off the main actor against a 512 px derivative of the final inference
image. The request has a 300 ms deadline. Selection uses a 0.50 confidence
floor, center proximity only as a near-confidence tie-break, 12%
subject-relative padding, a 3–70% accepted area range, and ambiguity rejection
for spatially separate near-confidence candidates. Failure, timeout, a broad
scene, or no clear subject produces `nil`; no synthetic fallback rectangle is
created.

An accepted region has passed the client confidence, ambiguity, area, and
geometry checks only. It has not been semantically verified as the user's
primary subject. The Edge prompt therefore tells Gemini to treat the region as
tentative and verify it against the complete image's relative area, centrality,
focus, and framing.

Camera preparation overlaps detection with display-payload preparation. Gallery
imports are detected after bounded preparation and then recalculated from the
confirmed square-crop bytes; required-crop auto-submit waits for that
recalculation. Historical reanalysis uses the same file-backed prepared-image
seam. The accepted region is attached to `IdentifyVisualMediaItem` and
`ActiveScanMedia.focusRegionsBySourceIndex`, ensuring the Insight overlay and AI
request use the same rectangle. Gemini still receives the entire post-crop
image, so focus metadata adds context without another crop, image part, storage
object, or image-token charge.

### Foreground local-analysis derivative

For a foreground visual scan, `InferenceEngine` passes only the first inference
image and the first visual item's accepted focus region to
`LocalVisualAnalysisImageBuilder`. The builder downsamples that square image to
at most 512 px, then crops the derivative to the already-padded top-left focus
rectangle when one exists. An absent or invalid region keeps the full bounded
square. Vision and the future on-device Foundation Models provider reuse this
single derivative. The current `AppleImageVisualTraitExtractor` also samples it
at 32×32 pixels to derive five bounded dominant-color, saturation-distribution,
lighting-distribution, light-contrast, and surface-detail cues; no additional
capture is decoded for local analysis. User-facing wording describes the visible
result rather than the extractor's numeric buckets.

This derivative is ephemeral and independent of the remote image pipeline. It
does not replace, crop, reorder, or add a part to the images sent to Gemini, and
it is released on result arrival, dismissal, scan replacement, queue handoff,
Auth transition, failure, or application deactivation. It is never written to
disk, analytics, or logs. Its classifications and rendered trait strings are
also never persisted, logged, or attached to telemetry.

Only an exact active visual presentation owner can associate the original
in-memory carousel media with a queue handoff. Prepared visual work carries
generic copy without media, and audio/Describe work is typed nonvisual. A stale
scan or attempt cannot rebrand either phrases or media. Dismissal and Auth
invalidate the association immediately even though durable upload, Gemini,
persistence, and result recovery continue.

During still-image inference, `AnalyzingMediaOverlay` maps the normalized square
image bounds through the carousel's aspect-fill transform, dims only the
exterior by 22%, and draws four detached white corner brackets. The brackets
resolve with a 200 ms entrance. While analysis remains active, dragging inside
the frame translates it, while dragging any corner bracket resizes width and
height independently. Resizing stays within the visible carousel and stops at a
64 pt minimum on each axis. Each bracket vertex has a 64 pt circular touch
target, sized so the targets stay distinct from the frame's draggable center.
The existing haptic policy distinguishes the gestures: whole-frame movement
begins with a selection tick, corner resizing begins with a firmer light impact,
and a selection tick marks an edge or minimum-size constraint. The dimming
cutout and illumination band follow every interaction, and the band continues
sweeping during and after the gesture. Translation and resizing are transient
presentation state only: they do not rewrite `NormalizedImageFocusRegion`,
queued metadata, or the already-dispatched AI request, whose original Vision
coordinates remain the model hint. Reduce Motion holds the illumination band at
the region's midpoint. Queued Insight caches use the focus-aware
`QueuedScanContext.activeScanMedia`, and interaction state is keyed by scan ID
plus the canonical still-image source index. User-adjusted geometry is stored in
normalized carousel coordinates by the stable Insight view model rather than a
mounted overlay. It therefore survives queue refreshes, overlay remounts, and
the queued-to-foreground or completed-result media handoffs while remaining
isolated from another scan or still image. The carousel follows the analyzing
presentation policy across a same-scan owner handoff, preventing a transient
engine flag from hiding the focus treatment. Exact active visual handoffs keep
the overlay through pending, uploading, staged, and inferencing; an ordinary
queued scan activates it only while inferencing, and failed, external-import,
attention-required, and completed states remain still. Its last confirmed
canonical scan ID also bridges the brief nil-owner window before the next owner
publishes that same ID. If no region exists, the still image has no focus
geometry and falls back to the original full-image scan animation. The
full-image and isolated-region sweeps are mutually exclusive. Video keeps its
existing laser animation, while audio and description keep their existing
sweeps.

The analysis clock belongs to `ImagesCarousel`, above the conditional
`AnalyzingMediaOverlay`. `AnalyzingMediaAnimationSession.startedAt` drives a
time-derived `TimelineView` sweep, so overlay recomposition and the
foreground-to-queue content switch cannot restart the phase. Only a different
canonical scan ID or a later false-to-true analysis transition resets the clock;
Reduce Motion holds the phase at its midpoint. The same session also owns a
continuity token that is exposed only through Debug UI automation and never in
Release accessibility.

An online live-to-queue presentation keeps `InferenceEngine.activeMedia` for the
exact scan instead of immediately replacing its live image data with the newly
persisted queue paths. This prevents a save-state update from remounting the
carousel mid-analysis. The canonical scan ID, page identity, selected index, and
existing `ZoomPageViewController` therefore remain stable while ownership
changes. Offline queued navigation and ordinary historical queued scans still
resolve their media from `QueuedScanContext`; completed result publication
remains the terminal source handoff.

The camera shutter path explicitly separates orchestration from ImageIO work.
`executeCapture()` snapshots location, composing-zone center, and Pro tier on
the main actor, then calls `DetachedWork.value(category: .imagePreparation)` to
downsample, crop, and encode the 12MP buffer. The detached worker returns
bounded inference/display bytes plus a `SendableCGImage` preview wrapper. No
`CGImageSourceCreateThumbnailAtIndex` or `CGImageDestinationFinalize` work is
allowed to inherit the view model's `@MainActor` executor.

The gallery picker now uses a bounded snapshot pipeline.
`CaptureWorkspaceViewModel+Imports.handlePhotoPickerSelection` snapshots the
staged-image budget (`availableSlots`) and paywall gate once on `@MainActor`,
clears `selectedPhotoItems`, and then performs all file-backed preparation
through `MediaPreparationActor`. Historical GPS/weather metadata is converted
into a `HistoricalEnvironmentContextSnapshot: Sendable` before leaving the main
actor, and the detached task returns only `PreparedStagedImage` values (`Data` +
sendable metadata + budget metrics). A single main-actor commit then appends the
final `StagedImage` array entries. For user-selected photo-library imports, that
commit passes `requiresCrop: true`; the view model tracks the staged image IDs
in `requiredGalleryCropImageIds` and presents the square crop editor before any
analysis submission can start. Because SwiftUI mounts the full-screen cover
after observing that state, `shouldSuppressCaptureChromeForCrop` hides both
bottom capture-chrome layers from the required-ID commit through crop dismissal.
The bottom layers are hidden without adding a workspace-level transition canvas;
`CropSheetModifier`'s `fullScreenCover` is the sole full-screen owner. This
keeps the staged **Identify** tray out of the handoff without leaving an
input-blocking overlay behind after a background/foreground transition. This
preserves Swift 6 isolation rules while removing repeated `MainActor.run` hops
during gallery imports.

Photos share-sheet files join the same preparation seam through a separate
durability boundary. `MerianApp.onOpenURL` validates that the incoming file's
resolved `UTType` conforms to `public.image`, then `ExternalImageImportStore`
copies it into an Application Support inbox while security-scoped access is
active. The inbox manifest survives cold launch and onboarding. Before
preparation strips source metadata, `ImportedImageMetadataExtractor` reads EXIF
capture date and a complete signed GPS pair. Date plus GPS uses the existing
historical WeatherKit/reverse-geocode path; date-only and coordinate-only files
preserve only the available values. If Photos share Options excludes Location,
the delivered file contains no usable GPS pair and no coordinates are added.

`CaptureWorkspaceViewModel.importPendingExternalImageIfPossible()` applies the
normal gallery quota and capacity checks before and after asynchronous
preparation, calls the shared file-backed `PreparedStagedImageLoader`, and
commits one image with `requiresCrop: true`. Quota- or capacity-blocked files
remain in the inbox and retry when entitlement or staging state changes.
Successful staging or terminal decode failure acknowledges and removes the
durable receipt. From the crop onward, confirmation preferences, live inference,
and offline queuing are identical to an in-app gallery pick.

The refinement path now shares that same actor-backed prepared-image staging
helper instead of issuing an eager `Data(contentsOf:)` copy of the stored scan
image. `startRefinementScan(from:)` builds a `PreparedStagedImageRequest`, sends
it through the injected async `PreparedStagedImageLoader`, and then commits the
result on the main actor without `requiresCrop`. In production the loader
delegates to `MediaPreparationActor.prepareStillImage(fileURL:isPro:)`, so both
the tier-sized inference payload and the 2048 px display payload pass the same
dimension/byte-budget contract as gallery imports. Tests stub the same seam to
verify request routing and staging state transitions without UI automation,
while `MediaPreparationActorTests` pins the production budgets directly.
Refinement staging must never retain the original full-size file bytes in
`StagedImage.displayData`.

Image-import admission happens before this preparation pipeline starts.
`PhotoLibraryButton` and the staged toolbar's add-photo action await
`requestImageImportEntryAdmission` before presenting the native picker, while
the durable external-import path awaits it before metadata extraction or ImageIO
decoding. The prospective count plus existing staging/refinement state determine
the RPC's Flash-eligibility boolean. A known denial opens the paywall without
allocating image buffers, staging media, or presenting crop; external receipts
remain durable. Submission intentionally rechecks because this entry preview is
advisory and non-reserving.

`PreparedStagedImage` now also carries a sendable preview `CGImage`, so
`commitPreparedStagedImages` can build the toolbar thumbnail from an
already-decoded image instead of calling `UIImage(data:)` on the main actor
during the final commit step.

Using the already-decoded `CGImage` directly for camera captures eliminates a
WebP round-trip decode step (encode to `Data` → decode back to `UIImage`). The
`stagedCapture.images.count` change is what the
`onChange(of: viewModel.stagedCapture.images.count)` observer in
`CaptureWorkspaceView` watches to auto-trigger staged submission. The camera,
video, and crop-confirmed commit paths first call
`beginAutomaticStagedSubmissionIfEligible()` in the same MainActor mutation that
adds or finalizes the media. That helper preserves the confirmation,
multi-capture, refinement, audio, describe, and pending-gallery-crop guards and
sets `isAutomaticStagedSubmissionPending` only for the eligible single-capture
path. The observer consumes that explicit ownership instead of inferring intent
one render later. `shouldPresentActiveScanToolbar` suppresses the manual
**Identify** tray while ownership is pending, preventing a staged-control flash;
if admission fails, the attempt releases ownership but retains the staged media
so the toolbar becomes the explicit retry path.

`CameraManager.photoOutput(_:didFinishProcessingPhoto:)` wraps
`AVCapturePhoto.fileDataRepresentation()` in an `autoreleasepool`, releasing
AVFoundation intermediates immediately after the continuation resumes.

After caller-scoped admission returns and the staged-input snapshot is
revalidated, `CaptureWorkspaceViewModel.submitStagedCapture(...)` calls
`enqueueCapture` synchronously before optional context or provider work and
waits for the SwiftData row, media files, and eligible foreground inference UUID
to become durable (see
[Offline Sync Pipeline → Scan Submission & Immediate Durability](../backend-and-data/01-offline-sync-pipeline.md)).
For an online live scan, that queue row is temporarily excluded from background
upload so the same image bytes do not compete with the inline inference request
for uplink bandwidth. `MerianRequestUploadDelegate` releases the queue only when
the inline JSON body finishes sending for that exact generation; a
generation-fenced two-second fail-safe, request failure, connectivity loss, or
app backgrounding releases it earlier when needed. Relaunch also clears the
in-memory suppression naturally, so an app termination cannot strand the durable
job. Visual live analysis starts only after queue acceptance and carries the
persisted generation through provider dispatch, local save, UI publication, and
cleanup. If the queue rejects the write, the UI reports the failure and any
unowned source video/audio files are deleted.

Capture Submission's actor-backed grace service races only the shutter-pinned
environment-context snapshot against 150 ms. That value bounds the optional
context wait, not total tap-to-dispatch time; existing telemetry preparation,
including optional LiDAR/Vision size estimation, runs after the race. A late
winner is committed to the durable queue before
`CaptureSubmissionDeferredContextService` calls `/update-scan-context`. That
service performs at most one remote retry after 500 ms and never invokes
inference. Endpoint, transport, and task cancellation are terminal and never
start that retry. Submission ViewModels receive these narrow Services through
`CaptureSubmissionDependencies` and do not call endpoints directly. Captured
context work is cancelled when queue acceptance fails or a queue-only, offline,
superseded, or unavailable-owner branch will not dispatch foreground inference.
Only a task that times out while an accepted foreground attempt still owns the
scan remains active for late enrichment. It retains the injected service and the
bounded primary inference image needed for optional telemetry, not the workspace
view model or full display-image collection. A primary gallery image cancels an
irrelevant live-device lookup and uses its embedded historical context instead.

After the upload handoff, recovery media may stage in parallel with Gemini, but
the live request retains foreground inference ownership. Staged replay skips
that scan until foreground success deletes the queue or failure/backgrounding
releases ownership. This prevents the durability path from creating a duplicate
primary model call.

The successful path then passes both image `Data` arrays to
`InferenceEngine.analyze(imageDatas:displayDatas:)`. Inside the engine,
`imageDatas` is base64-encoded for the AI call and discarded after encoding —
there is no retained inference buffer; durability is fully owned by the offline
queue. `displayDatas.first` is assigned to `activeImageData: Data?` and wrapped
into `activeMedia` as a single-frame preview used by the insight sheet carousel
during the inference window. The full `displayDatas` array is forwarded to
`InferenceProcessingActor.parseAndSave(displayDatas:)` and written to disk via
`FileIOActor.writeTemporaryImages`; once saved, the persisted user timeline is
rebuilt into `activeMedia` and the carousel switches from the live preview to
on-disk `MediaItem.image` entries. The parsed and persisted `speciesData` is
committed immediately; awards and Field trips follow asynchronously and
therefore cannot delay the first result render. The AI never receives the larger
display-image payload.

**Empty-payload guard (both paths)**: The camera shutter path's
`CaptureScanStillMediaPreparer` rejects an absent or empty encoded inference
payload before `CaptureWorkspaceViewModel+PhotoCapture` can append a
`StagedImage`. Video frame preparation applies the same rule. The gallery and
refinement path relies on `MediaPreparationActor` to reject empty encoded
inference or display payloads before returning `PreparedStillImage`. If WebP/
JPEG encoding fails for any reason (e.g., low-memory
`CGImageDestinationCreateWithData` failure), the item is skipped entirely rather
than appending `Data()`. Sending an empty base64 string
(`Data().base64EncodedString() == ""`) causes Gemini to reject the request with
an opaque AI processing error; the guard prevents this at the source.

`InferenceEngine.analyze` adds a second-layer filter: after `encodeBase64`, any
empty strings are removed from `base64Strings`. If all strings are empty after
filtering, the scan is refunded immediately without a network call. The Edge
Function (`identify/index.ts`) applies a third-layer check: each element of
`imageBase64s` is validated non-empty before being forwarded to Gemini,
returning a clear `400 Bad Request` instead of an opaque AI error.

**Cancel handler**: `ActiveScanToolbar`'s cancel action clears all staging
buffers in `CaptureWorkspaceViewModel` via
`clearStagedCaptureAndCropState(discardStagedMediaFiles: true)` and resets
`InferenceEngine` via `cancelActiveRequest()`, which nils `activeImageData` and
clears `activeMedia`. This clears `StagedCapture`, pending required gallery crop
IDs, `imageToCrop`, and `editingCropIndex` together, and deletes temporary
staged playback video/audio files through the file actor. Submit paths use
reference-only clearing after queue acceptance so durable queue/live persistence
retains media ownership.

**Video-preparation cancellation boundary**: sampled-frame, playback-export, and
companion-WAV work observe parent cancellation through `DetachedWork` and
explicit stage checks. Newly created WAV and compressed-playback files stay in
temporary leases until the prepared result is accepted for staging. A failed,
cancelled, timed-out, superseded, or otherwise unconsumed result therefore
deletes its files even when an AVFoundation operation completes after the
timeout winner. Accepted paths transfer to the staged-media cleanup contract
above. Once staging commits, Scan finalizes the recording generation and hides
its cancel UI before awaiting the optional Camera Roll write; PhotoKit still
retains the original recording until that write finishes.

**Why tier-conditional inference resolution (768 px / 1024 px)?** Gemini Vision
tokenizes images by tiling them into 768×768 blocks: a 768 px square image
occupies one tile (~258 input tokens), while a 1024 px square image occupies
four tiles (~1032 input tokens). Free/Flash tier uses 768 px — a ~75%
vision-token reduction with negligible accuracy impact for common-species
macro-feature identification (bark texture, wing pattern, leaf shape). Pro tier
uses 1024 px to preserve the fine morphological detail (feather barbs, gill
spacing, lichen areolae) that subspecies and cultivar discrimination requires.
Both payloads are well below the 5 MB guard (~100–250 KB base64 for 768 px;
~200–500 KB for 1024 px). `MerianConfig.inferenceImageMaxSize(isProActive:)` is
the single source of truth—Scan's injected entitlement action is evaluated by
`CaptureWorkspaceViewModel+PhotoCapture` and carried in the still-preparation
request before encoding. The gallery picker path evaluates the same live owner
in `CaptureWorkspaceViewModel+Imports.swift`.

**Why 2048 px for display?** Covers the full-width pixel density of all current
iOS devices without upscaling (iPhone Pro Max at 3× = 1290 px native; iPad Pro
at 2× = 2048 px native). Stored as WebP, display-quality files are free from the
blocking artifacts associated with lossy JPEG compression at lower resolutions.
Files average ~300–700 KB vs ~100–250 KB at inference quality.

**Why two `CGImageSourceCreateThumbnailAtIndex` calls instead of one?** Both
operate on the compressed source bytes (JPEG / HEIC) without ever expanding the
full 12 MP raster. The cost is two lightweight thumbnail decodes from the same
buffer — negligible compared to the AVFoundation capture itself.

**Manual crop export path**:
`ImageCropProcessor.generateCrop(image:displaySize:scale:currentScale:offset:currentOffset:maxPixelSize:)`
handles the manual crop tool (`ImageCropperView`). The `maxPixelSize` parameter
defaults to `1024`. Tier-appropriate sizing is preserved automatically: the
image passed into `ImageCropperView` is sourced from
`stagedCapture.images[index].original`, which was already downsampled to the
tier-correct size (768 px or 1024 px) during capture or gallery pick. Because
`kCGImageDestinationImageMaxPixelSize` is a _maximum cap_ — never an upscale
target — a free-tier 768 px source image passes through the 1024 px cap
unchanged. No explicit tier lookup is needed at the crop boundary. Compression
quality uses `MerianConfig.imageCompressionQuality` throughout (previously
hardcoded at 0.7, now consistent with the capture path).

When the user confirms a crop, `CropSheetModifier` updates both the inference
and display payloads to keep them in sync:

1. **Inference payload** (`stagedCapture.images[i].compressedData`):
   `generateCrop` is called on the already-tier-sized inference source. The 1024
   px cap is harmless for 768 px free-tier inputs — they are not upscaled.
2. **Display payload** (`StagedImage.displayData`): `generateCrop` is called
   again on the 2048 px WebP source (decoded off the main thread) with
   `maxPixelSize: nil` (no cap). The same `scale`, `offset`, and `displaySize`
   parameters are passed, so the crop geometry is pixel-accurately equivalent.
   The result (~1536 px at 1× zoom from a 2048 px source) replaces the original
   auto-cropped 2048 px file.

Without this sync, the scan library would show the original auto-crop while
Gemini analyzed the user's manually-adjusted crop — a visual mismatch in
multi-capture mode. `CropSheetModifier` updates staged images through
`StagedImage.replacing(...)`, which preserves the original `id` and `addedAt`
timestamp while replacing bytes and crop metadata. That timestamp is part of the
mixed-media timeline contract; resetting it during a crop would reorder images
relative to audio, video, or description items before inference. For required
photo-library crops, `CropSheetModifier` waits for the display-data crop task to
finish before calling `completeRequiredGalleryCrop(for:)`; if the 2048 px
display crop fails, it falls back to the confirmed inference crop bytes rather
than leaving the original display payload in place. Only after the final
required gallery crop is complete can the default single-image flow auto-submit.
`ImageCropperView` places its close/delete controls in a native
`NavigationStack` toolbar using `.topBarLeading` and `.topBarTrailing`. UIKit
therefore owns the status-bar, Dynamic Island, rotation, and window-size safe
area instead of trusting a full-screen cover's `GeometryProxy`, which can report
a zero top inset while its content still begins at the physical screen edge.

**Implementation**: Uses `CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceCreateThumbnailFromImageAlways: true` and
`kCGImageSourceShouldCache: false`. This instructs ImageIO to decode only a
scaled thumbnail directly from the compressed source, never loading the full
pixel buffer into RAM.

**Image encoding (WebP with JPEG fallback)**: After downsampling, both the
inference and display payloads are encoded as lossy WebP via
`CGImageDestinationCreateWithData` with `UTType.webP` and
`kCGImageDestinationLossyCompressionQuality` set to
`MerianConfig.imageCompressionQuality`. If `CGImageDestinationCreateWithData`
returns nil for WebP (e.g., the iOS Simulator's host-macOS ImageIO stack does
not support WebP writing on all platforms), the encoding automatically falls
back to JPEG using the same quality setting. The actual format used is detected
from the first image's magic bytes (`FF D8 FF` → `"image/jpeg"`, otherwise
`"image/webp"`) in `InferenceEngine.analyze` and forwarded to the Edge
Function's `mimeType` field so Gemini receives the correct MIME label. The
`CGImageDestination` API writes directly from the `CGImage` without an
intermediate `UIImage`, reducing peak allocation by one full decoded-pixel
buffer per encode. The toolbar thumbnail (`StagedImage.uiImage`) is separately
created via `UIImage(cgImage:)` — a zero-copy reference wrap over the
already-decoded `CGImage` — rather than by re-decoding the encoded bytes.

**Profile avatar encoding**: `ProfileAvatarImagePreparer` reuses the same
bounded ImageIO primitives for user-selected profile pictures. It downsamples
from the PhotosPicker file URL, applies a centered square crop, encodes WebP
with JPEG fallback, and returns a small `PreparedProfileAvatar` payload. The
Profile tab uploads that payload to R2 staging and calls `/update-public-avatar`
to promote it to `avatars/{userId}/...`. Avatar images are public profile media,
not scan media, so scan purge and moderation rollback paths must never delete
that prefix.

The avatar picker preview itself uses
`MediaPreparationActor.preparePreviewImage(fileURL:maxSize:)` from the temporary
PhotosPicker file URL before presenting the crop sheet, then wraps the returned
`CGImage` in `UIImage` on `@MainActor`. Do not use `UIImage(contentsOfFile:)`
for avatar selection; it decodes the full original raster and can OOM on
high-megapixel library assets before the bounded avatar encoder runs.

**`autoreleasepool`**: Both display and inference downsample calls — and the
`CGImageDestination` WebP encoding that follows each — are wrapped in
`autoreleasepool` so intermediate CoreGraphics allocations are released
immediately. Furthermore, all standalone `UIImage(data:)` inflations have been
officially deprecated across the codebase in favor of bounds-checked
`ImageDownsampler` extractions to prevent unbounded 48 MP uncompressed byte
payloads from instantly destroying active JetSam RAM limits.

**Alpha channel stripping**: Camera-captured frames decoded via
`CGImageSourceCreateThumbnailAtIndex` inherit the `AlphaPremulLast` pixel format
from the sensor buffer, even when the image is fully opaque. JPEG and WebP
encoders emit an "is trying to save an opaque image with 'AlphaPremulLast'"
warning when they encounter this format, and some encoding paths silently
degrade quality. `ImageDownsampler` calls a private `stripAlpha(from:)` method
on the downsampled `CGImage` before encoding. The method composites the image
into a new `CGContext` with `CGImageAlphaInfo.noneSkipLast`, producing an
RGB-only `CGImage` without any library dependency. The compositing context is
created at the image's native dimensions, so no extra scaling occurs. Only
images that actually carry an alpha channel go through the compositing path —
images already declared `.none`, `.noneSkipLast`, or `.noneSkipFirst` are
returned unchanged.

**`imageCompressionQuality` (0.85)**: Raised from 0.80 to preserve fine
morphological detail (feather barbs, insect wing venation, leaf margins) that
influences AI identification accuracy. File size increase is ~10–15%, well
within the 5 MB payload limit. All WebP encoding paths use
`MerianConfig.imageCompressionQuality` as a single source of truth — inference
payload, display payload, and manual crop tool all apply the same quality
setting.

**Static `enum` methods**: `ImageDownsampler` is declared as
`public enum ImageDownsampler` (not an `actor`). Both `downsample(url:maxSize:)`
and `downsample(data:maxSize:)` are `public static func`, making them
synchronous and callable without `await` from any concurrency context. Using
`enum` eliminates the actor executor overhead that existed when these methods
were `nonisolated` instance methods on an `actor` — an `actor` with exclusively
`nonisolated` members allocated a dispatch executor that was never used. All
call sites use `ImageDownsampler.downsample(...)` directly with no `.shared`
singleton reference.

**Optional full-resolution Photos export**: When the default-off
`saveToCameraRoll` setting is enabled, the full-resolution camera buffer is
handed to `PhotoLibraryManager` before identification downsampling. The manager
removes inherited GPS metadata from the encoded photo and assigns the resolved
shutter location through `PHAssetCreationRequest.location`. When a photo save
originates from a file URL rather than already-loaded `Data`, GPS stripping
streams through `CGImageSourceCreateWithURL` into a temporary scrubbed file.
This avoids reading the full asset into RAM just to remove EXIF coordinates.
Automatic video and later retained-clip Downloads follow the separate
[Camera Roll and Captured-Media Export contract](../features-and-hardware/27-camera-roll-media-export.md).

### 3. Write to Documents Directory (`FileIOActor`)

`FileIOActor.shared` (`Core/Data/Database/FileIOActor.swift`) is a Swift `actor`
that handles all disk I/O off both the Main Actor and the SwiftData actor
thread.

```swift
// Writes [Data] → [filename] in URL.documentsDirectory atomically
FileIOActor.shared.writeTemporaryImages(imageDatas: [Data]) -> [String]

// Deletes by filename (skips http:// paths — those are cloud-owned)
FileIOActor.shared.deleteImages(at: [String])
```

- **OOM risk**: Writing large arrays of image `Data` on the main thread blocks
  the UI and spikes memory.
- **Mitigation**: By running on its own isolated actor, `FileIOActor` guarantees
  that disk writes never contend with SwiftData saves
  (`BackgroundDatabaseActor`) or UI rendering.
- **Path format**: Only the filename (e.g. `"uuid_scan.webp"`) is stored in
  SwiftData — never the full absolute sandbox path. This prevents broken image
  renders caused by iOS randomizing container UUIDs on reboots and app updates.

---

## Disk → Display

### 4. Load Request (`LocalImageLoader`)

`LocalImageLoader.shared` (`Core/Data/Images/LocalImageLoader.swift`) is a Swift
`actor` that serves as the single entry point for all image loads — both local
and remote.

```swift
// Core UI ScanThumbnailLoader adapter — small decode for grid cells
await LocalImageLoader.shared.loadImage(
    fromPath: record.localImagePath,
    fallbackUrl: record.referenceImageUrl,
    maxDimension: 600   // default; ScansGrid passes a computed cell-pixel value
)

// Core UI live adapter behind AsyncLocalImageView — display-quality decode
await LocalImageLoader.shared.loadImage(
    fromPath: record.localImagePath,
    fallbackUrl: record.referenceImageUrl,
    maxDimension: Int(MerianConfig.displayImageMaxSize)  // 2048
)
```

These are service-adapter calls, not view-owned lookups. `ScanThumbnail`
receives its loader sequence through `Core/UI/Services/ScanThumbnailLoader`,
while `AsyncLocalImageView` receives the second closure through
`Core/UI/Services/AsyncLocalImageDependencies.live`. The components retain only
load identity, cancellation, retry, fallback, and rendering state.

**Resolution order:**

| Step | Check                             | Action                                                          |
| ---- | --------------------------------- | --------------------------------------------------------------- |
| 1    | RAM cache hit (`ImageCache`)      | Return immediately                                              |
| 2    | Duplicate in-flight request       | Coalesce — await the existing `Task`                            |
| 3    | `imagePath` starts with `http://` | Download via `LocalImageLoader.mediaSession`, downsample, cache |
| 4    | `imagePath` is a local filename   | Resolve to `documentsDirectory`, downsample, cache              |
| 5    | Local file missing                | Try `fallbackUrl` (supports comma-separated list)               |

**External reference URL policy:** Third-party reference imagery passes through
`ExternalReferenceImagePolicy` before it can become a cache key or network
request. The current exact rule rejects every URL whose normalized host is
`inaturalist-open-data.s3.amazonaws.com` and whose path starts with
`/photos/605615444/`; resized filenames, queries, and fragments cannot bypass
the match. User-captured local media, Merian R2 media, unrelated iNaturalist
photos, and other GBIF results are unaffected.

The policy is applied at both normalization and loading boundaries:

- comma-separated reference URL lists retain permitted values in their original
  order;
- a historical `SimilarSpeciesEntry.referenceImageUrl` containing the denied
  media decodes as `nil`, allowing normal live fallback without clearing the
  lookalike cache;
- `LocalImageLoader` sanitizes a remote primary path and every fallback before
  cache lookup, then rejects a denied URL again immediately before download;
- `SimilarSpeciesImageFetcher` filters candidates before concurrent downloads
  and sorts successful results by their original candidate index afterward.

The last rule is important: task completion order must never decide which image
becomes the card thumbnail. If the first candidate is denied or fails, the next
successful permitted candidate wins. If none load, existing callers render their
leaf/reference-unavailable placeholder.

**Current-scan/reference ownership policy:** The external denylist answers
whether a remote asset is permitted at all; the separate
`ReferenceImageDeduplicationPolicy` answers whether an otherwise permitted
reference is already owned by the scan being displayed. Explore passes the post
hero, canonical media URLs, and media thumbnails as exclusions. Insight passes
its image/video item paths plus persisted/queued thumbnails and cover path.
Naturebook media identity is the normalized host and encoded object path, so
signed, resized, or fragmented variants do not repeat the same storage object.
External media keeps strict full-URL identity. Filtering precedes page counts
and inline/fullscreen page construction, preserves reference ordering, and
converts an all-duplicate loaded set into the normal empty state.

This boundary is intentionally exact-scan only. It does not remove every image
by the same author and does not perform perceptual matching across separately
uploaded objects.

Both local and downloaded files enter the same decode boundary.
`AsyncPermitPool` admits at most four images, suspends additional tasks without
tying up an OS thread, removes cancelled waiters safely, and dispatches admitted
synchronous ImageIO work to `app.merian.image-decode` at explicit user-initiated
QoS. The permit is released only after decoding and RAM-cache insertion
complete.

**Dynamic GBIF Hydration** When a species is scanned for the first time globally
(Cache Miss), primary Wikipedia/GBIF species resolution may run inside the
required multimodal finalization boundary so the durable scan row can reference
a server species row. That work does not mutate the already validated model
response, so the initial result may still omit `reference_image_url`. The iOS
client (`InferenceEngine`) follows with `/enrich-scan`; once it receives
`gbif_taxon_key`, it may query `api.gbif.org/v1/occurrence/search` to hydrate
the legacy comma-separated `fallbackUrl` with 3–4 high-quality field
observations from networks such as iNaturalist. The shared dictionary upsert
path also normalizes those URLs into `species_reference_images`. Public Species
Dictionary and Explore detail readers prefer normalized rows and fall back to
the legacy cache. On Cache Hits, stored URLs are returned immediately. Group
tags and candidate-species enrichment remain optional background work and are
not part of the owner-row durability guarantee.

Insight hydration applies subject eligibility before any of those reference
paths. Live and historical Human aliases—including malformed `Homo sapien`—and
biological rows without resolved taxonomy skip enrichment/reference hydration;
stale candidates, lookalikes, GBIF keys, and reference URLs are not restored to
their active presentation. User-captured media remains available, and no
decision is inferred from model reasoning.

**Non-visual scan thumbnail repair** Audio-only, describe-only, and other
non-image biological scans now use a dedicated thumbnail policy instead of
falling straight into `ArchivedVisualsView`.
`LocalScanRecord.scanThumbnailPresentation` classifies tiles into three buckets:

- **Archived**: a real visual asset was expected and is missing, or the scan was
  intentionally locally archived.
- **Pending reference**: the scan has no stored visual media but represents a
  valid biological species, so the UI shows a non-visual placeholder while the
  library attempts to hydrate `referenceImageUrl`.
- **Unavailable reference**: the scan is non-visual but the identification is
  terminally non-resolvable for imagery (`Unknown Subject` /
  `Taxonomy Unavailable`), so the UI shows a non-visual terminal placeholder
  instead of implying an archived photo.

`ScansThumbnailPipeline` now prepares and schedules a bounded
`ScanThumbnailBackfillActor` pass over biological scans that lack both local
image media and `referenceImageUrl`. The same Shell service owns leading image
and audio prefetch plus online owner-media cloud repair, so `ScansSheetView`
does not resolve shared loaders or actors. The actor still checks the legacy
`species_dictionary.reference_image_url` cache directly for compatibility, then
falls back to Wikipedia / GBIF public APIs, persists any recovered URL back to
`LocalScanRecord.referenceImageUrl`, and prewarms `LocalImageLoader` so the grid
tile flips from placeholder to image without requiring a full sheet reopen.
`ScanThumbnailBackfillCandidate` lives beside the actor under
`Core/Data/Images`, so the Core recovery pipeline no longer depends on a
feature-owned SwiftUI file.

The owner-only Scan Map opts into the same pipeline only when a rendered map
thumbnail has no usable captured bitmap and no saved reference URL. Its shared
map store deduplicates scan IDs, revalidates each current record in a private
SwiftData actor, and submits bounded batches to `ScanThumbnailBackfillActor`.
After an actual durable URL change, the store refreshes the interactive map
snapshot so waypoints, the selected preview, and **Your scans** rows all receive
the fallback. Corrected identifications fence stale writes and discard the old
GBIF key; unresolved, human, domestic-cat, and domestic-dog scans remain
ineligible. The lookup never receives a scan coordinate, and an offline
thumbnail waits for connectivity instead of starting a public reference request.

`Core/UI/Components/ScanThumbnail.swift` takes online availability as an
explicit input instead of resolving `OfflineQueueManager` internally. Ordinary
owners pass the observed queue value directly. The private map resolves it
before its MapKit annotation builder and passes the scalar into each waypoint,
because hosted annotation content is not guaranteed to retain required
observable-environment objects while zoom changes swap dots for thumbnails.
Reconnection changes the input and therefore the thumbnail retry identity
without coupling image rendering to the queue manager. The renderer also
receives spectrogram and visual loading through `ScanThumbnailLoader`; only its
live dependency adapter resolves `AudioSpectrogramThumbnailLoader` and
`LocalImageLoader`. Shared loader work may continue filling the cache after a
cell task is cancelled, but the loader checks the caller's cancellation before
starting a visual fallback or returning a result. The main-actor renderer checks
again before publishing state or requesting reference recovery, so a reused tile
cannot admit an obsolete image. Its typed task identity also restarts for
changes to the requested pixel size or audio/reference loading policy, not only
path and connectivity changes.

The Core-owned `ScanThumbnail` keeps spectrogram rendering as its default for
non-library consumers. `ScansGrid` opts into `prefersReferenceForAudio` and
`showsAudioBadge`, so only the primary Scans library replaces an audio-only
spectrogram tile with the hydrated reference photo and bottom-trailing waveform
badge. The persisted audio path is unchanged and the Insight media carousel
continues to open on the spectrogram/playback surface. Collections,
Achievements, and other `ScanThumbnail` callers retain their existing policy.
While the Scans library is resolving an audio reference image, the tile uses the
same neutral raised-grid loading skeleton as visual media rather than showing
the internal `Reference pending` state.

- **Thundering herd prevention**: The
  `activeTasks: [String: Task<UIImage?, Never>]` dictionary ensures that 50
  cells requesting the same image key in a single scroll frame all await one
  download, not 50 parallel downloads. The inner fetch task is explicitly
  spawned using `Task.detached(priority: .userInitiated) { ... }` rather than a
  standard `Task`. This severs the concurrency context and prevents **Task
  Cancellation Poisoning**: if the SwiftUI view that originally initiated the
  fetch scrolls off-screen and its `.task` modifier cancels, the detached
  background load continues uninterrupted. This guarantees the image
  successfully enters the RAM cache and subsequent coalesced callers receive the
  image rather than a poisoned `nil` result.
- **Bounded remote session**: `LocalImageLoader.mediaSession` uses
  `httpMaximumConnectionsPerHost = 4`, `httpShouldSetCookies = false`,
  `requestCachePolicy = .reloadIgnoringLocalCacheData`, and `urlCache = nil`.
  This keeps remote thumbnail fetch pressure aligned with the four-slot
  asynchronous decode pool and avoids filling the shared URL cache with one-off
  media responses. Permit waiters suspend rather than blocking an OS thread,
  while admitted ImageIO work uses an explicitly QoS-tagged decode queue.
- **OOM risk during scroll**: Loading full-resolution images for every visible
  grid cell would exhaust RAM on large libraries.
- **Adaptive `maxDimension`**: `ScansGrid` computes the actual cell pixel size
  from screen width, column count, and display scale —
  `Int((screenWidth - spacing) / columns * scale)` — and passes it to
  `ScanThumbnail` as `maxDimension`. On a 3-column iPhone 15 at 3× scale this is
  roughly 390px, versus the previous hardcoded 1024px. `LocalImageLoader`
  threads `maxDimension` through to both local and remote load paths. Remote
  fallback downloads previously capped at a hardcoded 500px now use the same
  caller-provided value.
- **Retry-safe remote fallback**: `ScanThumbnail` now performs a short bounded
  retry loop for remote-only fallback loads, so a transient Wikipedia / GBIF /
  CDN miss no longer strands the tile permanently in the archived state while
  the sheet remains open.
- **`maxDimension` by caller**:
  - `ScanThumbnail`: `600` default (ScansGrid overrides with a computed
    cell-pixel size).
  - `AsyncLocalImageView` (cross-feature Core UI renderer; the Insight carousel
    requests display-sized media): `Int(MerianConfig.displayImageMaxSize)`
    = 2048. The 2048 px files are stored on disk; decoding them at full
    resolution ensures crisp display on Pro Max (1290 px native width) and iPad
    Pro (2048 px native width). Previously defaulted to 1024, producing visibly
    soft full-screen images on large devices.

### Display lifetime and feedback isolation

Image/video carousel state remains owned by the mounted media surface. Inline
and fullscreen video retain one `MediaPlaybackObservation`, which removes KVO,
AVPlayerItem notification, and periodic-time tokens from the exact old player
before a replacement is observed. Its callbacks retain neither SwiftUI views nor
image payloads and must pass a player/item generation check before changing
lightweight playback state. A late callback therefore cannot remount or redraw
the new page with state from its predecessor.

Cross-module `AppEvent` and `AppRoute` envelopes carry only identifiers and
small scalar metadata; they never retain `UIImage`, decoded frames, scan
collections, or carousel destinations. Toasts and progress indicators likewise
mount as alignment-scoped, pass-through overlays. Heavy image state remains in
the bounded loader/cache or its durable store, preventing ephemeral feedback
from invalidating a full media tree. See
[Event and Presentation Routing](10-event-and-presentation-routing.md).

### 5. RAM Cache (`ImageCache`)

`ImageCache.shared` (`Core/Data/Images/ImageCache.swift`) wraps
`NSCache<NSString, UIImage>`.

```swift
cache.countLimit = 100                    // hard entry cap
cache.totalCostLimit = 30 * 1024 * 1024  // 30 MB byte cap
```

Every `set(_:forKey:)` call computes the pixel-area cost
(`width × height × 4 bytes`) and passes it to `setObject(_:forKey:cost:)`. This
gives `NSCache` an accurate memory footprint so it can evict the largest images
first rather than treating a 4K thumbnail the same as a 64×64 icon.

- **Automatic eviction**: `NSCache` evicts entries under system memory pressure
  without any manual intervention. With `totalCostLimit` set, eviction is
  triggered by _actual byte usage_ rather than just entry count.
- **No strong references**: Images in `NSCache` do not prevent deallocation, so
  they are released when iOS signals a memory warning.
- **Dimension-aware Cache Keys**: `LocalImageLoader` appends the requested
  `maxDimension` to the underlying file path or URL to form the cache key (e.g.,
  `filename.webp_600`). This isolates payloads by size, preventing memory
  collisions where a low-resolution grid thumbnail (600px) could erroneously
  fulfill a subsequent high-resolution display request (2048px) for the same
  underlying file.

---

## Historical / Remote Images (Rehydration)

Supabase Postgres stores scan rows, Explore snapshots, and the URLs that connect
them to media. Cloudflare R2 stores the image bytes. A surviving
`image_storage_urls` or `explore_post_media.url` value is only a reference; it
does not prove that the R2 object still exists and cannot reconstruct deleted
bytes.

When a user reinstalls the app or signs in on a new device,
`LocalScanRecord.localImagePath` can contain a Cloudflare R2 URL rather than a
local filename. `LocalImageLoader` handles this transparently. For an eligible
durable Naturebook URL, it first checks the local recovery resolver, then
downloads from R2 if no surviving local file is known. Network media is
downsampled to the caller-provided `maxDimension`, cached in RAM, and decoded
away from the main actor. Legacy records that already contain local filenames
continue to load directly from Documents.

### Local scan-media recovery

`LocalScanMediaRecoveryResolver` reconnects a durable
`public_uploads/free|pro/{owner}/...` URL to a surviving image in the app's
Documents directory. It refuses unrelated hosts, avatars, non-image files,
unsafe filenames, query/fragment identity drift, and path traversal. Recovery
evidence is evaluated in this order:

1. the public basename and the current `{scanId}_{localFilename}` promotion
   convention;
2. scan-ID and media-order alignment against read-only databases preserved under
   `Library/Application Support/store-rescue/`; and
3. high-confidence timestamp groups only for current scans absent from the
   rescue index.

Timestamp groups require one `_scan` image plus contiguous `_additional_N`
images written in the same second, an exact media-count match, a write timestamp
from zero to 60 seconds before the scan row, at least a three-second lead over
the next candidate, and one-to-one file use across the complete matching pass. A
direct filename or rescue-store match always wins. Nearest-time matching without
these constraints is not permitted.

The registry is process-local and is rebuilt at startup, during historical sync,
and before Scan Library thumbnail prefetch. It does not rewrite cloud metadata
by itself. Its first responsibility is to render a strongly matched surviving
local file instead of a missing remote object.

### Cloud repair from a recovered local file

When the device is online, Scan Library collects only remote URLs that resolve
to surviving local files and sends them to `CloudScanImageRepairActor`. The
actor:

1. asks authenticated `/repair-scan-image` to inspect the owned source;
2. stops when the source is healthy or no longer referenced;
3. uploads an eligible local file to a newly signed owner-scoped staging key
   only when the source is confirmed missing; and
4. asks the same endpoint to promote the object and atomically replace the exact
   URL in scan, normalized-media, captured-media, and Explore snapshot metadata.

The server derives ownership from the JWT, verifies both object states, and
rolls back a newly promoted object if metadata repair fails. Client failures
pause the in-memory queue for 15 minutes rather than spinning. Local rendering
is therefore possible before cloud repair completes; a visible image on one
device is not proof that the R2 object or Explore snapshot has been restored.

See the
[July 2026 account-scoped R2 image-loss incident report](../incidents/2026-07-account-scoped-r2-image-loss.md)
for current recovery coverage and unresolved limits.

### Published Explore media-health projection

Remote rendering failure is not storage-loss authority. Explore uses a
server-owned, direct-origin lifecycle:

1. active post media is leased in bounded batches every five minutes;
2. a signed R2-origin `HEAD` checks the primary key and any distinct auxiliary
   thumbnail;
3. one primary `404` becomes `suspected_missing`;
4. a second primary `404` at least five minutes later becomes `missing`;
5. public media JSON omits confirmed-missing primaries and confirmed-missing
   auxiliary thumbnails;
6. post health becomes `degraded` while any primary remains, or `quarantined`
   when none remains; and
7. a later healthy origin check or successful atomic repair restores projection
   automatically.

Timeouts, `5xx`, auth/credential errors, malformed URLs, CDN responses, and
client image-loader errors only schedule retry. A thumbnail is auxiliary: its
confirmed `404` removes the poster but cannot hide a playable video/audio
primary. An image whose thumbnail and primary are the same URL follows primary
health.

Quarantine is not a file move and does not use the temporary R2 `quarantine/`
prefix. It is reversible Postgres projection state independent from author
unpublish and moderation. The post, likes, comments, reports, and health
evidence remain. Reference artwork is never substituted for missing observation
evidence.

The Scan Library owner banner consumes `/get-explore-media-incidents` through
`ScansShellViewModel`'s injected endpoint dependency; Library rendering receives
only prepared incident state. The canonical response is `{"data":[...]}`;
corrected clients also accept only the exact legacy direct array during
deployment convergence. Rapid queue-event refreshes are coalesced within five
seconds with one trailing refresh for a trigger received in flight. Canceled
drivers cannot project their response, and account replacement preserves the
trailing refresh while rejecting the old owner's result. The expected
authenticated owner is revalidated before projection, malformed successes fail
closed, and refresh failure preserves the last in-memory alert state. Reviewing
a linked local scan can activate the strongly matched device repair above. A
repair updates the exact scan and Explore references and resets health in one
transaction. Repeated origin checks alone cannot recreate bytes if no
recoverable copy exists.

See
[Explore Media Health and Quarantine](../backend-and-data/12-explore-media-health-and-quarantine.md)
for the full state, communication, security, monitoring, and rollout contract.

---

## Upload Path (Offline Queue)

For captures that go into the offline queue, images are written to disk by
`FileIOActor.writeTemporaryImages` before the `OfflineQueuedScan` SwiftData
record is inserted. During upload, `OfflineQueueManager` copies each image to a
temp file in `URL.cachesDirectory` (naming convention:
`<scanId>_<index>_temp_upload.webp`) and hands the path to
`URLSession.uploadTask(with:fromFile:)`. The `Content-Type: image/webp` header
is applied to the `URLRequest` before the upload task is created. The OS
background session owns the byte transmission from that point. On upload
completion, the temp staging file is deleted unconditionally regardless of
success or failure.

Although this document focuses on images, the V48 offline queue is
media-agnostic. `capturedMediaJSON` remains the user-facing timeline across
images, video, audio, and descriptions; image/video/audio upload work is
scheduled through `OfflineJobRecord` and retried with persisted
`OfflineQueuedScan.queue*` metadata. Video captures keep sampled frames in
`OfflineQueuedScan.inferenceImagePaths` for AI replay while the playable `.mp4`
plus thumbnail stay in the captured-media timeline. Playback videos are prepared
as network-optimized 720p exports with source/export bytes, duration,
compression ratio, source choice, and fallback status logged for production
tuning; the 12 MB server cap remains the hard acceptance gate. Description-only
scans have no media upload phase and enter the same staged/inference job flow
directly. Queue diagnostics export only job and event metadata, never private
media paths or raw media bytes.

The same file-backed rule now applies to explore-media restore.
`MerianNetworkClient.restoreExploreMediaObjectKeys` validates each restorable
local image/video path, derives MIME type from the file extension or file
header, and uploads via `upload(for:fromFile:)` with bounded concurrency. The
restore path must never materialize every media file into `Data` just to
populate `httpBody`.

**Offline queue image quality**: The offline queue stores inference-quality
images only (768 px for Flash/free, 1024 px for Pro — whichever was applied at
capture time). When an offline scan is reprocessed,
`InferenceProcessingActor.parseAndSave` receives `displayDatas = []` and falls
back to writing the inference-quality files to disk. This bounded representation
is an intentional queue-memory trade-off. A full-resolution Photos copy exists
only when the user had the default-off **Save to camera roll** preference
enabled; it must not be assumed as a durability prerequisite. Live captures and
gallery picks both produce display-quality on-disk files during the normal
foreground path.

**Auth-state race condition (cold background relaunch)**: `generate-upload-urls`
is authoritative for the owner segment of every staged key. Current background
upload task descriptions persist that exact server-issued key alongside the
scan, media slot, and generation. Completion therefore does not query a lazily
initialized auth session or fall back to a device identity. Older in-flight
tasks remain compatible by recovering and validating the key from the original
signed URL path. Before inference, the callback verifies that the completed key
belongs to the queued capture's canonical media set; a malformed or mismatched
destination is retained as a user-attention failure rather than submitted.

---

## Component Responsibilities Summary

| Component                   | Location                                  | Responsibility                                                                                                                                                            |
| --------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ImageDownsampler`          | `Core/Utilities/`                         | CGImageSource thumbnail decoding; `public enum` with `static func` — no actor overhead; autoreleasepool                                                                   |
| `ExternalImageImportStore`  | `Core/Data/Images/`                       | Durable Application Support inbox for security-scoped Photos document imports; manifest recovery, acknowledgement, and pre-preparation EXIF extraction                    |
| `MediaPreparationActor`     | `Core/Data/Images/`                       | File-backed still-image preparation; owns inference/display encoding and budget metrics                                                                                   |
| `FileIOActor`               | `Core/Data/Database/`                     | Disk reads/writes; isolated from Main and SwiftData actors                                                                                                                |
| `LocalImageLoader`          | `Core/Data/Images/`                       | Load orchestration; exact external-reference URL policy; scan-media recovery registry/rescue/timestamp matching; RAM cache hits; request coalescing; local/remote routing |
| `MediaPlaybackObservation`  | `Core/Media/`                             | Exact AVPlayer KVO/notification/time-token ownership and generation-fenced replacement callbacks                                                                          |
| `CloudScanImageRepairActor` | `Core/Data/Images/LocalImageLoader.swift` | Serial owner-authenticated inspection, staging upload, and cloud-reference repair for strongly matched surviving local images                                             |
| `ImageCache`                | `Core/Data/Images/`                       | NSCache-backed RAM store; auto-evicts under memory pressure; 100-entry cap                                                                                                |
| `ArchiveManager`            | `Core/Data/Images/`                       | `@MainActor` coordinator for generated dataset archive ZIP downloads                                                                                                      |
