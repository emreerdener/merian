# Capture, performance, and fixtures

Read this reference for camera, image/audio/video capture, inference staging,
hardware throttling, simulator workflows, previews, or UI tests.

## Production capture invariants

- Preserve the `CameraManager` and `HardwareOrchestrator` contract. Do not
  override frame-rate, memory, or thermal bounds to make a test pass.
- Degrade expensive visual effects at serious thermal pressure and keep capture
  buffers bounded. Avoid retaining full-resolution images across actor or UI
  boundaries when a file URL, thumbnail, or downsampled representation suffices.
- Enforce size/count limits before decoding or accumulating variable input.
- Persist capture state through the existing staging/offline path before remote
  inference. A simulator-only shortcut must not become another production path.

## Safe simulator and UI-test behavior

- Use existing Debug-only launch arguments, `UITestSeedCoordinator`, preview
  containers, protocol-backed fakes, and checked-in deterministic fixtures.
- Keep fixture activation compile-time and runtime gated to Debug/UI tests.
  Release builds must be unable to activate it.
- Seed the same durable/domain state that production presentation consumes when
  testing post-capture UI. Do not intercept `CameraManager`, fabricate an
  `AVCapturePhoto`, or call an internal inference delegate out of sequence.
- Never force unwrap fixture images or encoded data. Fail with a clear test
  assertion or guarded diagnostic.
- Do not add static coordinates, personal locations, live provider requests, or
  production credentials to fixtures. Location-dependent UI uses synthetic,
  documented, non-personal test data at the domain boundary.

## Test selection

- Pure state or mapping change: focused Swift Testing/XCTest target.
- Camera/hardware change: focused manager/orchestrator tests plus a build for the
  relevant simulator and, when hardware-only behavior changed, explicitly note
  the required physical-device verification.
- UI flow: focused UI test using a deterministic launch seed, not taps based on
  assumed coordinates.
- Project/source change: `make xcodegen`, `make validate-ios-project`, and the
  generated-project contract tests.
- Cross-surface change: also run the queue/repository or DTO gate that proves the
  handoff boundary.

Document why an unavailable hardware check could not run and what evidence is
still required before release. A local simulator pass does not prove camera,
thermal, signing, or TestFlight behavior.
