# Capture Shared

The `Shared` directory owns Capture-domain code consumed by more than one
product area or modality. Cross-feature infrastructure belongs in `Core`, while
cross-feature deterministic value graphs belong in top-level `Models`. The
canonical image preparation, focus, and handoff behavior is documented in the
[image pipeline](../../../../../../docs/system-architecture/03-image-pipeline.md).

## Ownership

- `Models/` contains shared Capture values such as the file-backed Photos
  transfer wrapper and `IdentifiableImage` source context, provenance, distance,
  and resumable crop geometry. It also owns the baseline
  `CaptureControlBarLayout` and adaptive `CaptureChromeLayout` consumed by
  Shell, Scan, Record, and Describe, plus the platform-neutral feedback and
  source vocabulary in `CaptureControlHapticPolicy.swift`, shared by Shell
  controls and Scan's video-start transition. These values do not invoke
  platform effects.
- `ViewModels/` contains the action coordinator shared by the Shell and capture
  modes.
- `Services/ImageFocusRegionDetector.swift` is the Capture telemetry façade for
  the Core/Media focus engine. It preserves the 300 ms optional visible outcome
  for Scan, Shell imports and Staging crop confirmation. Core owns Vision,
  deterministic candidate resolution and a separate positive worker-drain wait
  for native durable preparation. Capture diagnostics expose only outcome,
  duration and a coarse area bucket; no image content or region coordinates are
  logged or sent to telemetry. Neither owner has endpoint authority.
- `Components/CaptureChromeLayoutEnvironment.swift` owns the SwiftUI environment
  and tray-height preference bridge; the shared clearance models remain
  independent of SwiftUI.
- `Components/RecordingCountdownBadge.swift` owns the passive countdown
  treatment shared by Record audio and Scan video capture. Each caller supplies
  its duration, progress, and accessibility prefix.
- `Components/CaptureAuxiliaryControlModifier.swift` owns the shared 50 pt
  circular glass appearance used by Shell's secondary controls and Scan's photo
  library button. It accepts an optional tint and falls back to circular
  material before iOS 26; callers retain foregrounds, animations, and action
  semantics.
- `Utilities/ComposingCenterEnvironment.swift` owns the cross-modality SwiftUI
  environment contract: Shell supplies the measured composing center and Record
  consumes it for aligned audio presentation.

Generic bounded media transport, including `SendableCGImage`, belongs to
`Core/Media` because both Capture and Insights consume it. The durable
`ObservationContext` belongs to `Models/Media` because Capture, Core AI,
persistence, historical loading, and Insights all consume it.

## Verification

`MerianTests/Core/Media` owns deterministic focus resolution and worker-drain
coverage. `MerianTests/Features/Capture/Shared` retains the architecture guard
separating the Capture telemetry façade from Core image work, retired Utilities
paths, live-service exclusions and the 600-line production-file ceiling.

`CaptureStagingToolbarPresentationTests` verifies `CaptureChromeLayout` retains
the 124 pt baseline inset and applies the same measured expansion to capture
controls, Describe content, and camera/audio overlays. The environment and
preference bridge remains in `Components`; the clearance values in `Models` must
not import SwiftUI.
