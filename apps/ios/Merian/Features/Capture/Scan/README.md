# Capture Scan

`Capture/Scan` owns the visual Capture modality: camera preview presentation,
focus and zoom interaction, photo/video capture actions, bounded media
preparation, and the staged-media commit boundary. It does not own the
`AVCaptureSession` or device configuration; `CameraManager` remains the hardware
authority.

## Ownership

- `Models/` contains platform-neutral still/video preparation requests, prepared
  results, playback metadata, and deterministic frame-sampling policy.
- `Services/` contains the narrow live camera, context, Photo Library, media,
  entitlement, and semantic-feedback adapters. Still preparation, video frame
  and playback preparation, WAV extraction, and temporary-artifact leases have
  separate owners.
- `ViewModels/` contains photo/video actions, semantic zoom feedback, and the
  generation-fenced recording/progress task owner. Replaced or cancelled video
  work cannot commit stale progress or media, cancel a replacement recording, or
  surface obsolete failure feedback.
- `Views/`, `Components/`, and `Modifiers/` own viewfinder presentation,
  view-local focus/zoom timing, the system photo picker, and camera gestures.
  They contain no networking or global service resolution.

`CaptureWorkspaceDependencies.scan` injects the live adapters from the existing
workspace container. Do not add a Scan singleton, a broad service protocol, or
direct service lookup in a view.

## Media lifecycle

Still capture performs bounded inference and display downsampling, applies the
same composing-zone-aware square crop to both outputs, derives a tentative focus
region, and commits one typed `StagedImage`. Short Pro video capture keeps the
original recording alive while it samples five deterministic frames, prepares a
bounded playback clip, and extracts companion WAV audio. Temporary
audio/compressed artifacts remain leased until staging accepts them, so failed,
cancelled, timed-out, superseded, and unconsumed preparation results delete
their files. `DetachedWork` propagates parent cancellation into the bounded
workers; synchronous ImageIO/AVFoundation work observes cancellation at the
explicit stage boundaries.

Once a prepared video is committed to `StagedCapture`, its recording generation
and cancel UI finish before the optional Camera Roll save completes. The save
still retains the original recording until its PhotoKit write returns, while a
late cancel action cannot discard media that has already crossed the staging
boundary.

The original-recording and PhotoKit lifetime contract is documented in
[`27-camera-roll-media-export.md`](../../../../../../docs/features-and-hardware/27-camera-roll-media-export.md).

Generic crop encoding lives in `Core/Media/ImageCropProcessor.swift` because
Capture and Profile both consume it. `Core/UI` owns `ImageCropperView` and the
presentation-only flash control. Capture-specific source/crop metadata remains
in `Capture/Shared/Models/IdentifiableImage.swift`; Profile owns a separate
avatar-crop value. Feature callers inject crop/zoom/flash feedback actions;
shared components do not resolve the haptic or camera service.

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

`ImageFocusRegionDetector` runs after still encoding on a bounded derivative
with its existing deadline and acceptance policy. The region remains transient
tentative metadata and never replaces the full inference image.

## Verification

`MerianTests/Features/Capture/Scan` mirrors this owner. The focused suites cover
frame-sampling and playback presentation, recording/progress generation fences,
temporary-file lease transfer/cleanup, detached-work cancellation propagation,
semantic dependency routing, and architecture constraints. The architecture
guard keeps every production Scan Swift file at or below 600 lines, requires the
ownership folders, rejects the removed aggregate `Capture.swift`, forbids global
service resolution, and keeps Models platform-neutral.

The canonical hardware and media contracts remain in
[`01-camera-and-hardware.md`](../../../../../../docs/features-and-hardware/01-camera-and-hardware.md)
and
[`03-image-pipeline.md`](../../../../../../docs/system-architecture/03-image-pipeline.md).
