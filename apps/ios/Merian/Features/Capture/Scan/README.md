# Capture Scan

`Capture/Scan` owns the visual Capture modality: camera preview presentation,
focus and zoom interaction, photo/video capture actions, bounded media
preparation, and the staged-media commit boundary. It does not own the
`AVCaptureSession` or device configuration; Core Hardware remains the hardware
authority through `CameraSessionController`, the observable `CameraManager`
facade, and `CameraVideoRecordingService`. Core Hardware's
`CameraPhotoCaptureCoordinator` and `CameraVideoRecordingCoordinator` remain the
still-photo and video-request lifetime owners, respectively.

## Ownership

- `Models/` contains platform-neutral still/video preparation requests, prepared
  results, playback metadata, and deterministic frame-sampling policy.
- `Services/` contains the narrow live camera, context, Photo Library, media,
  entitlement, and semantic-feedback adapters. Still preparation, video frame
  and playback preparation, WAV extraction, and temporary-artifact leases have
  separate owners.
- `ViewModels/` contains photo/video actions, semantic zoom feedback, and the
  generation-fenced still, pre-recording, recording, and progress task owner.
  Replaced or cancelled work cannot commit stale progress or media, cancel a
  replacement capture, or surface obsolete failure feedback.
- `Debug/` contains the interactive simulator replay menu, bounded local-file
  preparer and workspace staging extension. Every declaration is compiled only
  with `DEBUG && targetEnvironment(simulator)`. It shares production media
  preparers and staged-video conversion, then retains manual Identify ownership.
- `Views/`, `Components/`, and `Modifiers/` own viewfinder presentation,
  view-local focus/zoom timing, the system photo picker, and camera gestures.
  They contain no networking or global service resolution. The preview receives
  the same environment-injected `CameraManager` facade that exposes the session
  and owns observable zoom/lens-transition state; `CameraSessionController`
  retains the underlying session and device-control ownership.

`CaptureWorkspaceDependencies.scan` injects the live adapters from the existing
workspace container. Do not add a Scan singleton, a broad service protocol, or
direct service lookup in a view.

## Media lifecycle

Still capture performs bounded inference and display downsampling, applies the
same composing-zone-aware square crop to both outputs, derives a tentative focus
region, and commits one typed `StagedImage`. Short Pro video capture keeps the
original recording alive while three bounded child operations concurrently
sample five deterministic frames, prepare a playback clip, and extract companion
WAV audio. Completion waits for all required results rather than adding each
stage's latency. Temporary audio/compressed artifacts remain leased until
staging accepts them, so failed, cancelled, timed-out, superseded, and
unconsumed preparation results delete their files. `DetachedWork` propagates
parent cancellation into the bounded workers; synchronous ImageIO/AVFoundation
work observes cancellation at the explicit stage boundaries.

The companion-audio extractor leaves appended sample buffers valid for the
asynchronous asset writer. If that writer emits WAVE_EXTENSIBLE, the shared
`InferenceAudioPreparer` normalizes it to standard mono 44.1 kHz Int16 PCM WAV
before staging. Both the intermediate export and canonical sidecar remain leased
through conversion; only the validated canonical result transfers to staging.
The existing inference byte limit and strict WAV checks remain in force.

Debug simulator replay accepts fixed `Documents/IdentificationReplay/audio.wav`
and `video.mp4` inputs into an empty workspace. It preserves the source,
enforces recorder duration/byte limits, requires all five video frames and
companion WAV when audio is present, and transfers only prepared copies to
normal staging. Cancellation, stale account/session ownership and failed
preparation clean unaccepted copies; no replay action calls admission, queues a
scan or submits inference. The ordinary Identify action retains those
responsibilities. See the
[app measurement guide](../../../../../../docs/development-guides/21-identification-app-measurement.md#controlled-audio-and-video-replay-in-the-simulator)
for sample preparation, activation and measurement limits.

**Stage comparison slot** validates a copy against the frozen assignment's
complete WAV hash and length, requires canonical mono 44.1 kHz Int16 PCM, and
retains those exact bytes through staging. Re-encoding an already canonical WAV
can add Core Audio container padding and invalidate its assignment. Ordinary
audio replay continues to use the production transcoder. The comparison copy
retains the same duration, cancellation, source-preservation and staging
ownership checks; later request serialization independently checks its bytes.

The separate **Stage audio with fixed context** action attaches
`audio-minimal-v1` to one staged audio item. It clears stale context prefetch,
requires that item to remain the sole staged input through admission, and keeps
Identify manual. The profile's lifetime follows the item and foreground
telemetry; clearing/removing the item cannot change later ordinary captures.
Submission owns context suppression and Network owns the fixed existing-field
projection. Background recovery is excluded from controlled comparison because
the Debug profile is not persisted.

When recording ends, the countdown and stop icon immediately give way to a busy
shutter while preparation continues. The capture generation remains active, the
cancel action remains available, and new capture, library, and flash actions are
blocked. Ordinary lifecycle interruption preserves the already-recorded clip's
preparation; explicit cancellation still discards it. Shutter-to-recording and
total preparation timings are logged separately from playback export timing.
Recording failures display a recording-specific retry message; only failures
after a recording file is returned use the staging-failure message. Both paths
clear capture UI state and permit another attempt without staging partial media.

Once a prepared video is committed to `StagedCapture`, its recording generation
and cancel UI finish before the optional Camera Roll save completes. The save
still retains the original recording until its PhotoKit write returns, while a
late cancel action cannot discard media that has already crossed the staging
boundary.

Shell interrupts visual work when the scene becomes inactive, the user leaves
Scan, a root or feature presentation takes ownership, the workspace disappears,
or capture state is cleared. A still shutter or pre-recording admission request
is cancelled and generation-fenced, so a non-cooperative late response cannot
newly save, prepare, stage, or auto-submit media. A video that has already begun
recording retains the established graceful-stop path and may stage its partial
clip; only work that has not reached recording is discarded.

The original-recording and PhotoKit lifetime contract is documented in
[`27-camera-roll-media-export.md`](../../../../../../docs/features-and-hardware/27-camera-roll-media-export.md).

Generic crop encoding lives in `Core/Media/ImageCropProcessor.swift` because
Capture and Profile both consume it, and `Core/UI` owns the shared
`ImageCropperView`. The presentation-only `CaptureFlashButton` lives beside its
complete control row under Capture Shell, which owns the injected camera
mutation and feedback. Capture's source and crop metadata remain in
`Capture/Shared/Models/IdentifiableImage.swift`; Profile owns a separate avatar
crop value. Feature callers inject crop/zoom/flash feedback actions; shared
components do not resolve the haptic or camera service.

In-app `PhotosPicker` selection lives with Scan controls. A photo received from
the iOS Photos share sheet enters through Capture Shell and
`ExternalImageImportStore`; both paths converge on bounded preparation and the
Staging-owned required-crop flow. See
[`26-photos-share-import.md`](../../../../../../docs/features-and-hardware/26-photos-share-import.md).

## Adjacent boundaries

The idle active-goal indicator belongs to `Capture/Shell`, which owns fixed
mode-level chrome and Explore routing. Scan does not fetch goal DTOs, award
progress, or change Field-trip semantics. See
[Capture Shell](../Shell/README.md) and
[`25-field-trips.md`](../../../../../../docs/features-and-hardware/25-field-trips.md).

The [Capture Shared](../Shared/README.md) `ImageFocusRegionDetector` runs after
still encoding on a bounded derivative with its existing deadline and acceptance
policy. The region remains transient tentative metadata and never replaces the
full inference image.

## Verification

`MerianTests/Features/Capture/Scan` mirrors this owner. The focused suites cover
frame-sampling and playback presentation, still/pre-recording/recording/progress
generation fences, lifecycle overlap rejection, temporary-file lease transfer/
cleanup, detached-work cancellation propagation, semantic dependency routing,
and architecture constraints. The architecture guard keeps every production Scan
Swift file at or below 600 lines, requires the ownership folders, rejects the
removed aggregate `Capture.swift`, forbids global service resolution, including
direct `CameraManager.shared` lookup, and keeps Models independent of UI
frameworks.

`CaptureScanVideoAudioExtractorTests` creates synthetic MP4 clips with mono and
stereo AAC tracks and checks canonical WAV format, audible samples, duration,
queue eligibility, source preservation, no-audio behavior, and lease cleanup.

`CaptureDebugReplayPreparerTests` covers canonical audio, duration/size bounds,
linked sources/inboxes, complete video evidence, fallback playback ownership and
late cancellation cleanup. Comparison cases verify full-file equality through
request serialization, altered/noncanonical input rejection and cancellation
cleanup using synthetic WAVs. `CaptureWorkspaceDebugReplayTests`, under the
`CaptureWorkspaceViewModelRefinementTests` selector, covers manual Identify,
interruption/replacement fencing and account changes without provider calls. It
also verifies fixed-profile admission snapshots, mixed-input rejection, queue
context omission, reset isolation, and staged foreground audio reaching the
normal request service and intercepted HTTP serialization without live or
deferred context calls. `InferencePayloadBuilderTests` freezes the fixed field
projection and strips accidental enrichment from a profiled request.

The canonical hardware and media contracts remain in
[`01-camera-and-hardware.md`](../../../../../../docs/features-and-hardware/01-camera-and-hardware.md)
and
[`03-image-pipeline.md`](../../../../../../docs/system-architecture/03-image-pipeline.md).
