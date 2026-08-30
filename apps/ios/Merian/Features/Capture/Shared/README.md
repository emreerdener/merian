# Capture Shared

The `Shared` directory owns Capture-domain code consumed by more than one
product area or modality. Code that is also used outside Capture belongs in
`Core` instead.

## Ownership

- `Models/` contains shared Capture values such as observation context, the
  file-backed Photos transfer wrapper, and `IdentifiableImage` source context,
  provenance, distance, and resumable crop geometry.
- `ViewModels/` contains the action coordinator shared by the Shell and capture
  modes.
- `Components/RecordingCountdownBadge.swift` owns the passive countdown
  treatment shared by Record audio and Scan video capture. Each caller supplies
  its duration, progress, and accessibility prefix.
- `Utilities/ComposingCenterEnvironment.swift` owns the cross-modality SwiftUI
  environment contract: Shell supplies the measured composing center and Record
  consumes it for aligned audio presentation.

Generic bounded media transport, including `SendableCGImage`, belongs to
`Core/Media` because both Capture and Insights consume it.
