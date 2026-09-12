# Capture Shared

The `Shared` directory owns Capture-domain code consumed by more than one
product area or modality. Code that is also used outside Capture belongs in
`Core` instead. The canonical image preparation, focus, and handoff behavior is
documented in the
[image pipeline](../../../../../../docs/system-architecture/03-image-pipeline.md).

## Ownership

- `Models/` contains shared Capture values such as observation context, the
  file-backed Photos transfer wrapper, and `IdentifiableImage` source context,
  provenance, distance, and resumable crop geometry. It also owns the fixed
  `CaptureControlBarLayout` consumed by Shell, Scan, Record, and Describe, plus
  the platform-neutral feedback and source vocabulary in
  `CaptureControlHapticPolicy.swift`, shared by Shell controls and Scan's
  video-start transition. These values do not invoke platform effects.
- `ViewModels/` contains the action coordinator shared by the Shell and capture
  modes.
- `Services/ImageFocusRegionDetector.swift` owns the Capture-only Vision
  objectness request, its cancellation/deadline bridge, and deterministic
  candidate resolution shared by Scan, Shell imports, and Staging crop
  confirmation. It consumes the Core image downsampler and emits the existing
  cross-feature `NormalizedImageFocusRegion`. Existing diagnostics expose only
  outcome, duration, and a coarse area bucket; no image content or region
  coordinates are logged or sent to telemetry. The service owns no endpoint or
  mutable singleton.
- `Components/RecordingCountdownBadge.swift` owns the passive countdown
  treatment shared by Record audio and Scan video capture. Each caller supplies
  its duration, progress, and accessibility prefix.
- `Utilities/ComposingCenterEnvironment.swift` owns the cross-modality SwiftUI
  environment contract: Shell supplies the measured composing center and Record
  consumes it for aligned audio presentation.

Generic bounded media transport, including `SendableCGImage`, belongs to
`Core/Media` because both Capture and Insights consume it.

## Verification

`MerianTests/Features/Capture/Shared` owns the deterministic focus-region suite
and the Shared architecture guard. The guard freezes the detector's sole Capture
owner, exact framework imports, retired Utilities paths, test ownership,
live-service exclusions, and the 600-line production-file ceiling.
