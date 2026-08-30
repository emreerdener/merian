# Capture Record

The `Record` directory owns the Audio Listen Mode presentation used by the
Capture pager. It presents idle, recording, paused, and review state without
owning the audio engine, Capture lifecycle controls, or submission.

## Ownership

- `Models/` contains immutable UI snapshots plus deterministic artwork, layout,
  and signal-guidance presentation policies. Models do not import SwiftUI or
  UIKit.
- `Services/` is the only Record layer that references `AudioCaptureManager` or
  the shared haptic manager. It projects the manager into a presentation value
  and builds the narrow closure dependencies used by the view model.
- `ViewModels/` owns only idle-artwork selection and review scrubbing state. It
  receives seeking and feedback actions through its initializer.
- `Views/` composes idle, recording, and review presentation from immutable
  input. It performs no networking and does not resolve global services.
- `Components/` owns the idle artwork/prompt, spectrogram interaction, and
  signal-quality guidance surfaces.

`Capture/Shell` is the composition boundary. It resolves the environment-owned
`AudioCaptureManager`, creates the Record presentation and dependency values,
and keeps the pager state. The shared Capture control bar retains microphone
permission, start, pause, resume, stop, discard, playback, and confirmation
actions. `Capture/Submission` retains live/offline analysis orchestration.

## Shared owners

- `Core/Hardware/AudioCaptureManager.swift` owns the 15-second Int16 WAV
  recording, review playback, bounded DSP stream, published lifecycle state, and
  manager-owned asynchronous transition handles.
- `Core/Hardware/AudioCaptureDependencies.swift` provides the narrow live/test
  audio-session and engine-start closures. `AudioCaptureTransitionState.swift`
  provides the generation fence shared by startup, resume, DSP, and countdown
  publication.
- `Core/Hardware/SpectrogramActor.swift` owns FFT, mel-scale, and rolling
  ambient-noise classification. `Core/Hardware/AudioSessionCoordinator.swift`
  owns one-shot, token-aware recording/playback session leases shared with
  dictation. Failed replacement activation restores the prior configuration;
  failed rollback deactivates the partial session and invalidates its lease.
- `Core/Media/AudioSpectrogramRenderer.swift` owns the reusable palette, raster,
  and live-versus-static display policy.
- `Core/UI/Components/AudioSpectrogramView.swift` owns the cross-feature SwiftUI
  renderer used by Record and Insight audio playback.
- `Capture/Shared/Components/RecordingCountdownBadge.swift` owns the countdown
  treatment shared by audio and video capture.

UI-sensitive timing remains with the mounted components: idle artwork advances
every six seconds, the one-per-process recording prompt lasts 3.5 seconds with a
350 ms handoff, and review drag gestures determine scrub animation timing. The
15-second duration, 360-column display bound, visible copy, accessibility,
control semantics, and queue-before-inference behavior are unchanged.

## Verification

Feature tests live under `apps/ios/MerianTests/Features/Capture/Record/`.
Hardware and reusable renderer tests live under
`apps/ios/MerianTests/Core/Hardware/` and `apps/ios/MerianTests/Core/Media/`.
The architecture suite enforces the layered folders, Services-only live adapter,
platform-neutral Models, shared-owner locations, and the 600-line
production-file review guard. Hardware tests also hold resume activation open to
lock duplicate-request coalescing and late-completion fencing, and exercise
transition invalidation, successful replacement, configuration restoration, and
rollback-failure and first-activation cleanup.

Simulator suites cover presentation, state transitions, cancellation, and
dependency behavior, but they do not validate a real microphone route or
process-wide `AVAudioSession` handoff. Before release, verify on a physical
device: first-use permission, Camera-to-Audio startup, record/pause/resume and
early-stop review, mode/background preservation, both 15-second confirmation
branches, feedback, review playback/scrubbing, and the Audio-to-Describe
handoff.

See
[Audio Listen Mode](../../../../../../docs/features-and-hardware/12-audio-listen-mode.md)
for the canonical behavior and lifecycle contract.
