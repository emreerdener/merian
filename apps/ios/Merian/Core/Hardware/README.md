# Core Hardware

The `Hardware` directory contains managers for monitoring and interacting with
the device's physical state.

## Purpose

This area houses the `HardwareOrchestrator`, which monitors
`ProcessInfo.thermalState` and `isLowPowerModeEnabled`. It dynamically manages
resource intensity (such as capping framerates to 24fps or dropping heavy
shaders) under thermal pressure to ensure the app remains stable during intense
camera and AI usage.

## Speech recognition ownership

`SpeechManager` is cross-feature hardware infrastructure. It owns Speech
authorization, microphone permission, `AVAudioEngine`, recognition requests,
live audio level, and the token-aware `AudioSessionCoordinator` lease used by
Capture Describe, Insight Field Notes, Insight audio playback coordination, and
the Shell-owned Capture controls. `AppDIContainer` creates the long-lived
observable instance; feature views receive it through the established
environment and pass narrow actions into feature state owners.

Do not move dictation tasks or audio-session teardown into a paged feature view.
`SpeechManager` remains responsible for activating late, tearing down every
failure/cancellation path, and deactivating only its current audio-session
lease. Its overlap guard may return without opening a new session when another
consumer is starting or recording, so feature adapters must verify `isRecording`
before treating startup as successful.

Capture Describe and Insight Field Notes are the hardened feature consumers.
Their Services layers build live manager adapters, while their view models own
text/session generations. A stop during pending startup cancels and retains that
startup task instead of calling shared teardown concurrently with audio
configuration. A replacement waits for the canceled startup to finish; if an
injected, cancellation-ignoring startup nevertheless reports success, the stale
session is stopped before the replacement enters `SpeechManager`. When the
manager ends recognition automatically, Field Notes invalidates its generation
and rejects late transcription without calling shared teardown again.

Shared manager lifecycle tests live in
`apps/ios/MerianTests/Core/Hardware/SpeechManagerTests.swift`; consumer overlap
coverage remains in the Describe and Field Notes feature view-model suites.

## Audio capture and session ownership

`AudioCaptureManager` is the stable observable Capture Record facade. It owns
the 15-second countdown, bounded display history, noise-guidance hold policy,
review/submission paths, and lifecycle presentation state. Its maximum-duration
feedback is initializer-injected; `AppDIContainer` supplies the live
heavy-impact closure so the manager does not resolve haptics. Record views
receive an immutable presentation projection and never access the manager
directly.

`AudioCapture/Services/AudioRecordingEngineController` is the focused recording
owner behind that facade. It owns the lazy `AVAudioEngine`, input tap, canonical
Int16 PCM WAV, bounded PCM stream, detached DSP task, exact recording identity,
startup/resume operation token, and recording-specific audio-session lease.
Engine construction, session effects, route-recovery wait, file naming, and
deletion are initializer-injected. The controller rejects a second pending
resume before process-wide session activation. A late activation is rejected by
exact operation identity, and all failure and cancellation paths finish the
stream, remove the tap before stopping the engine, cancel DSP, release the exact
lease, and delete the partial WAV. Its stored deactivation dependency accepts a
concrete lease, so teardown with no owned lease emits no synthetic release.
`AudioRecordingWAVFormatPolicy` and `AudioRecordingEngineModels` keep the file
contract and sendable presentation values outside the lifecycle owner.

`AudioCapture/Services/AudioReviewPlaybackController` owns review presentation,
activation, progress, completion, and the playback-specific audio-session lease
on `@MainActor`. `AudioReviewPlaybackFilePlayer` privately owns `AVAudioPlayer`
on an actor backed by a dedicated serial executor: file opening, synchronous
hardware start/stop, seeking, and position reads never execute on the UI thread
or Swift's cooperative executor pool. Only sendable values cross that boundary;
the AVFoundation player never escapes.

Every accepted playback request has a generation. Stop clears UI ownership
immediately, cancels and joins pending startup/seek work, then stops the player
before releasing its exact lease. Replacement waits for this retirement and
preserves the last live position, unless a newer seek superseded it. Late
startup cannot restart audio after teardown. Seeks made during preparation or
activation remain pending; seeks during playback cancel and replace completion
and reject obsolete progress reads. A failed file open reports an asynchronous
startup failure so the manager can retain its original-recording fallback for an
unusable boosted preview. Session and completion failures still finalize the
current request. Manager reset always stops review playback, even while
recording startup is resolving. Tests inject deterministic players, session
effects, and wait gates through the existing dependency value.

`AudioCapture/Services/AudioReviewBoostController` separately owns the
review-only boost selection, cancellable preparation generation, and temporary
derivative. It invokes the shared DSP through an uncached local-preview entry
point so retirement cannot invalidate Explore or Insight caches. The manager
keeps original WAV paths for review confirmation, staging, persistence, and
inference; only the playback controller switches sources while retaining
position and playback intent. Late results are deleted after disable, submit,
discard, reset, or lifecycle exit. The Audio preference defaults off and is
sampled per recording; automatic preview boost waits for Play. See the
[canonical review boost contract](../../../../../docs/features-and-hardware/12-audio-listen-mode.md#recording-review-audio-boost).

`AudioSessionCoordinator` is the cross-feature, token-aware lease owner for
recording and playback audio sessions. `AudioRecordingEngineController`,
`AudioReviewPlaybackController`, `AudioPlaybackSessionController`,
`CameraVideoAudioSession`, and `SpeechManager` release only their current lease,
so delayed teardown from an older operation cannot deactivate a replacement
session. The reusable playback owner adds the established ducking configuration,
coalesces activation, rejects late acquisition after teardown, and reacquires a
lease made stale by a newer owner. Keep this owner separate from either feature
and do not call `AVAudioSession.sharedInstance()` from a paged view. A lease
becomes current only after configuration and activation both succeed, and
successful deactivation consumes it. A failed replacement restores the prior
configuration before leaving that lease current. If restoration also fails, the
coordinator deactivates the partial session and invalidates prior ownership
rather than publishing a lease for an unknown configuration. A failed first
activation likewise deactivates any partially activated session before returning
the error. A task cancelled before its queued activation reaches the coordinator
performs no audio-session mutation.

`SpectrogramActor` owns the off-main FFT, mel-scale projection, and bounded
rolling ambient-noise floor. Its guidance policy classifies clipping by peak and
the remaining levels by the rolling minimum RMS floor; it is not a calculated
signal-to-noise ratio in decibels. Rendering belongs to `Core/Media` and
`Core/UI`, while Record owns only the mounted guidance and scrub interaction.

Manager and DSP tests live in
`apps/ios/MerianTests/Core/Hardware/AudioCaptureManagerTests.swift` and
`SpectrogramActorTests.swift`. Recording, WAV-format, playback, and structural
coverage live under `Core/Hardware/AudioCapture/` in
`AudioRecordingEngineControllerTests.swift`,
`AudioReviewPlaybackControllerTests.swift`, and
`AudioCaptureArchitectureTests.swift`. Transition-token and audio-session lease
tests live beside the original manager suite in
`AudioCaptureTransitionStateTests.swift` and
`AudioSessionCoordinatorTests.swift`. Mounted reusable playback lease coverage
lives with its Core Media owner in `AudioPlaybackSessionControllerTests.swift`.
Record presentation tests remain with the feature, and reusable raster tests
live in `Core/Media` test ownership. The recording suite covers teardown order,
retained versus deleted WAV ownership, engine-start failure, bounded route
recovery, cancellation-ignoring activation, controller-level duplicate-resume
coalescing, resume retry, and the canonical PCM format. The playback suite
covers late activation, failed player start, completion-wait failure, stale
completion, resume position, manager reset, and manager-state finalization; the
coordinator suite covers successful replacement, failed-replacement restoration,
failed-rollback invalidation, and failed-first-activation cleanup. The Core
Media playback-session suite covers idle-mount isolation, lazy activation
coalescing and retry, stale lease reacquisition, cancellation-before-activation,
late-acquisition release, teardown during current-lease validation, and cleanup
after replacement.

## Haptic feedback ownership

`HapticManager` is the stable `@MainActor @Observable` application facade. It
owns global preference and expedition-mode admission, suppression diagnostics,
the latest attempt projection, semantic public trigger names, and the timing of
multi-pulse sequences. Existing callers may continue to receive it through
`AppDIContainer`, environment injection, or narrow feature closures.

Focused implementation lives under `Haptics/`:

- `Models/HapticFeedbackModels.swift` owns platform-neutral attempt, diagnostic,
  event, feedback-kind, and Core Haptics profile values.
- `Policies/HapticFeedbackPolicy.swift` owns pure admission, profile mapping,
  intensity clamping, and suppression-log-key decisions.
- `Services/HapticFeedbackController.swift` owns the reusable UIKit generators
  and lazy Core Haptics engine. Exact engine identity fences stopped/reset
  callbacks so an obsolete engine cannot clear its replacement. Impact and
  selection routes always deliver their UIKit feedback; supported Core Haptics
  adds the matching transient, while an unavailable or failed engine leaves the
  UIKit delivery intact.
- `Services/HapticAudioSessionAdapter.swift` is the sole haptic owner that
  inspects `AVAudioSession`. It preserves best-effort feedback during recording
  without making the facade or a feature view an audio-session owner.

Generator, Core Haptics engine, audio-session, and injected clock closures carry
explicit `@MainActor` function types. This keeps the hardware contract enforced
even if a dependency value is copied outside its current owner. The focused
domain enums contain only routes exposed by the facade; UIKit-only `.soft` and
`.warning` branches and the unobservable intermediate Core Haptics outcome are
not part of the extracted domain.

The facade delays generator preparation by 300 milliseconds to keep hardware
work off app initialization. Do not instantiate UIKit or Core Haptics
generators—including impact, selection, and notification generators—in feature
views. Route user-facing actions through the manager or inject a semantic
closure into the feature owner. Tests live under
`MerianTests/Core/Hardware/Haptics/`; coverage for Capture's pure
control-feedback policy lives separately in
`MerianTests/Features/Capture/Shared/CaptureControlHapticPolicyTests.swift`.

## Environment context and location authorization

`EnvironmentContextManager` remains the caller-compatible
`@MainActor @Observable` facade used by Capture, Explore, Scans, Insights, and
Profile. It owns only dependency composition, observable location-state
projection, and the stable context methods. Projected state is read-only to
callers so the focused location owner cannot be desynchronized. Focused
implementation lives under `EnvironmentContext/`:

- `Models/EnvironmentContextModels.swift` owns the returned context value and
  internal placemark, weather, and location-snapshot values.
- `Policies/EnvironmentLocationPolicy.swift` owns authorization, prompt,
  accuracy, location-profile, three-decimal cache-key, placemark-presentation,
  and region-normalization decisions.
- `Services/EnvironmentLocationController.swift` is the sole Core Location
  delegate and `CLLocationManager` owner. It coalesces authorization waiters,
  owns live tracking and one-shot requests, scopes cancellation to the calling
  request, rejects negative-accuracy updates, and keeps coarse fallbacks out of
  the accurate cache. Revocation retires active one-shot requests, and a
  cancelled request cannot escape through the cached-location fallback. The
  controller restores both the coarse composing accuracy and its 100 m distance
  filter after all shutter waiters resolve, whether or not live tracking is
  active. One shared two-second timeout carries an exact UUID generation, so a
  cancelled non-cooperative timeout cannot resolve a replacement request.
- `Services/EnvironmentGeocodingService.swift` is the sole `CLGeocoder` owner.
  Location-name and ISO-region projections share one same-coordinate placemark
  request, one bounded in-memory insertion-order cache, and one active-request
  registry keyed at the established three-decimal precision. Failed and
  projection-empty resolutions are not cached.
- `Services/EnvironmentWeatherService.swift` is the sole WeatherKit owner. It
  adapts `WeatherService.shared` into current and historical reading closures;
  no view or deterministic policy resolves WeatherKit directly.

`fetchDeferredContext` still starts geocoding and current weather concurrently,
preserves the independently resolved location name if WeatherKit fails, and
returns value state rather than publishing context presentation. Historical
lookup remains date-pinned and preserves the capture date when weather is
absent. The facade, controller, geocoder, and weather adapter use small
initializer-injected dependency values rather than a broad protocol or a new
singleton.

`EnvironmentContextManager.lastKnownLocation` returns cached coordinates only
while the current authorization state permits location access; revocation hides
both accurate and coarse retained fixes from Capture, Explore, and Map callers.
The facade rechecks that projection after its one-shot location suspension, so
revocation during a deferred capture cannot fall back to a retained fix or begin
geocoding/weather work. Both the eager `validatePermissions()` path and the
async `requestLocationAuthorizationIfNeeded()` path pass through the same policy
before the controller asks Core Location to present a system prompt. Passive
region and display-name resolution only proceeds from already-authorized state
and never prompts.

The common Debug UI-test launcher supplies
`-seedLocationPermissionPromptSuppressed`. The flag is honored only when the
`UITesting` environment contract resolved by
`Configuration/TestExecutionCoordinator.swift` is also active; it suppresses the
Core Location prompt without fabricating authorization, coordinates, or cached
environment context. A future UI test that intentionally exercises the iOS
location prompt must use a launcher that omits this argument. The Release
`UITestSeedCoordinator` implementation always disables the fixture, and archive
validation rejects the marker if it reaches the main executable.

Deterministic coverage lives under
`MerianTests/Core/Hardware/EnvironmentContext/`. Policy, controller, geocoder,
facade, and architecture suites cover authorization and accuracy boundaries,
revocation, overlap/cancellation/timeout generations, invalid-fix rejection,
accurate-versus-coarse cache ownership, live-tracking transitions, cache
coalescing, empty-result retry, and eviction, service concurrency and failure
fallback, UI-test prompt suppression, declaration ownership, and focused line
ceilings. The focused matrix currently contains 34 deterministic tests. The
retired root model and aggregate test files must not be recreated.

Before release, verify Environment Context on a signed physical device. Grant,
deny, and revoke Location access while the camera is active and while a shutter
one-shot is pending; a revoked facade must stop exposing its retained fix and
must not start geocoding or weather work. Regrant access and verify live coarse
tracking resumes, shutter capture can obtain an accurate fix or bounded coarse
fallback, and returning from the one-shot restores hundred-meter accuracy plus
the 100 m distance filter. Record simulator and physical-device evidence
separately.

## Framework publisher bridge

`Utilities/Publisher+MainActor.swift` owns the Combine bridge used by Apple and
hardware publishers whose originating executor is unknown. It schedules onto the
main queue, preserves publisher ordering, and enters the main actor through
`MainActor.assumeIsolated`. Callers retain and cancel the returned cancellable.

Do not use this helper for `AppEventPublisher`: the app bus is already
synchronous and `@MainActor`-isolated, so an asynchronous hop would change its
reentrancy contract. `FrameworkPublisherBridgeTests` verifies ordered main-actor
delivery, while the routing architecture suite freezes the reviewed raw-sink
allowlist. Media player observation remains owned by `Core/Media`.

## System notification boundary

System authorization, APNs registration, local scheduling, typed push routing,
and app-icon badge state no longer live in Hardware. Their focused owner is
[Core Notifications](../Notifications/README.md). Hardware retains camera,
audio, haptic, environmental, thermal, battery, speech, and audio-session
responsibilities only.

Push registration, notification catalog/count, and mark-read wire requests
remain in `Core/Network/Endpoints/MerianNetworkClient+Notifications.swift`. Core
Notifications composes push registration and unread-count refresh behind focused
Services. `Features/Explore/Notifications` composes catalog and mark-read
adapters and owns the in-app activity UI and state. Do not restore notification
declarations or tests under Core Hardware.

## Camera ownership

The root `CameraManager.swift` is the MainActor observable facade and the
frame/depth/photo delegate bridge. `CameraSessionController` owns the lazily
resolved capture session, video/depth/photo outputs, shared serial camera queue,
session lifecycle, device selection and locking, frame-rate/zoom/focus/torch
mutations, and hardware still-photo setup. It injects that queue plus a lazy
session provider into `CameraVideoRecordingService`, the separate live
AVFoundation owner for the movie output. Constructing the manager, controller,
or service resolves neither the session nor the movie output. The camera preview
may resolve the root session when its view mounts; output factories and the
recording session provider are evaluated only on the serial queue during
explicit camera work. Stop requests and device controls inspect only an existing
session, so cleanup and pre-preview UI actions do not create capture hardware.
Every asynchronous stop request still publishes its completion when no session
exists or the session is already stopped. Capture objects remain behind one
serial-queue mutation contract even though their responsibilities no longer
share one oversized file.

Initial session configuration reserves ownership only while it can create the
required video input and attach the required video and photo outputs. A
transient discovery/input failure releases that reservation so a later start can
retry, and the start callback is published only after AVFoundation reports the
session running. A session-lifecycle generation also suppresses a queued start
callback after stop has already invalidated that start. The MainActor facade
independently generation-fences observable start and stop publication, so an
older completion cannot overwrite a newer session intent. The pure presentation
state coalesces duplicate starts and duplicate stops instead of invalidating the
one callback that can converge facade state. Optional depth attachment cannot
displace the required photo output.

Focused camera support lives below `Camera/`:

- `Models/CameraVideoRecordingModels.swift` owns the value-only recording
  result, generation, and scheduled-action identities.
- `Policies/CameraVideoRecordingPolicy.swift` owns the already-granted
  microphone reuse decision and the pure generation/action correlation gate.
- `Policies/CameraSessionPolicy.swift` owns `CameraSessionPresentationState` and
  its same-intent coalescing/generation fence, plus pure zoom clamping,
  optical-stop filtering, supported frame-duration clamping, and safe
  frame-duration update ordering.
- `Coordination/CameraPhotoCaptureCoordinator.swift` owns still-photo request
  reservation, checked continuations, timeout tasks, cancellation, and atomic
  terminal-result claiming under one internal lock.
- `Coordination/CameraVideoRecordingCoordinator.swift` owns the single live
  recording request, checked continuation, start metadata, generation/action
  gates, timeout and automatic-stop tasks, and atomic terminal-result claiming
  under one internal lock.
- `Coordination/CameraTargetFPSDebouncer.swift` owns the MainActor debounce task
  and its UUID replacement fence.
- `Services/CameraSessionController.swift` owns the lock-backed lazy root
  capture stack and all session, output, and active-video-device operations on
  the serial camera queue. It exposes no observable state and does not resolve
  app-level orchestration or viewfinder services.
- `Services/CameraVideoRecordingService.swift` owns lazy movie-output creation
  and attachment, rotation and stabilization configuration,
  start/stop/cancel/timeout camera-queue operations, file cleanup, hardware
  logging, and recording delegate correlation. It exposes no observable state.
- `Services/CameraVideoAudioSession.swift` owns recording audio admission,
  per-request shared audio leases, and camera-queue microphone attachment and
  removal. It never prompts for microphone permission.

`CameraArchitectureTests` freezes those owners and framework boundaries. It also
caps the value, policy, and FPS files at 100 lines, caps the photo coordinator
at 220 lines, caps the video coordinator at 380 lines, and caps the session
controller, recording service, and `CameraManager.swift` at 600 lines.

## Camera frame-rate observation

`CameraManager` observes `HardwareOrchestrator.targetFPS` with one-shot
observation tracking. The change callback must re-arm observation before it
suspends. `Camera/Coordination/CameraTargetFPSDebouncer.swift` then cancels and
replaces pending applications, correlates each task with a UUID generation, and
reads the current target after the 100 ms debounce. This keeps rapid thermal
escalation and recovery aligned with the latest hardware target even when
cancellation finishes cooperatively.

Only the debounce policy and observable target live on `@MainActor`.
`CameraSessionController` keeps `AVCaptureSession.inputs`, device locking, and
frame-duration changes on the serial camera queue.

## Camera photo concurrency

`CameraManager` creates `AVCapturePhotoSettings`, snapshots observable flash
state, and converts the accepted delegate result to `Data`.
`CameraSessionController` validates the video connection, applies supported
flash, rotation, resolution, and depth settings, and invokes `capturePhoto` on
the serial camera queue. Photo capture reads only an already-configured depth
output; a non-LiDAR capture does not instantiate an unattached depth output.
`CameraPhotoCaptureCoordinator` owns request lifetime. The manager reserves the
settings `uniqueID` before installing the task cancellation handler. If
cancellation wins before checked-continuation registration, the coordinator
marks the reservation and registration consumes it as `CancellationError`
without enqueueing a hardware capture.

Timeout, camera-not-ready failure, task cancellation, and delegate completion
all atomically remove the active request before canceling its timer and resuming
its continuation outside the lock. A late terminal path is therefore ignored,
and a late delegate callback does not perform file-data conversion. The
coordinator imports no AVFoundation, UI, network, or persistence framework. Do
not call it while holding the manager's frame-analysis lock or from another
coordinator's locked transition.

## Camera recording concurrency

`CameraSessionController` owns the root session and shared serial queue, then
`CameraManager` injects the queue and a non-eager controller-backed session
provider into `CameraVideoRecordingService`. The service lazily creates its
movie output and owns every movie-output and movie-connection mutation on that
queue. `Camera/Models` supplies the recording and generation identities;
`Camera/Policies` supplies the pure generation/action gate and already-granted
microphone decision. A video request is identified by both a UUID generation and
its UUID-derived output URL. Delayed timeouts and automatic stops also carry an
action UUID so a cooperatively cancelled task cannot act after replacement.
Recording delegate callbacks must match the service's configured output and the
canonical file URL before they may clear state or resume a continuation. The
recording identity resolves symlinks on the existing parent directory before
appending the UUID filename, including when the output file has not yet been
created. This admits equivalent sandbox paths without admitting another file or
directory. Callback canonicalization runs outside the coordinator lock; the
locked transition revalidates the exact generation after normalization. Rejected
start/finish callbacks and watchdog output state are logged so a callback
rejection is distinguishable from missing AVFoundation callbacks.
`CameraManager` alone publishes generation-checked observable recording state on
`@MainActor`.

`CameraVideoRecordingCoordinator` keeps the continuation, URL, timer tasks, and
start metadata in one lock-owned request. Installing or replacing a scheduled
action first publishes its action token under the lock, then creates and
attaches the task; a task that loses that race is canceled. Terminal paths
remove the request atomically, then cancel tasks and expose a one-shot
completion outside the lock. That completion atomically consumes its checked
continuation, so even a copied handle cannot resume the request twice. The
coordinator imports no AVFoundation, UI, network, or persistence framework. The
service's narrow `@unchecked Sendable` conformance is justified only by its
documented split: recording audio-lifetime access is MainActor-only, while
capture objects are lazily resolved and mutated only on the injected queue.
Never call a coordinator, controller, or service while holding `CameraManager`'s
frame-analysis lock.

`CameraVideoAudioSession` owns per-request movie audio admission and cleanup. It
acquires a fresh `.videoRecording` lease before microphone attachment, disables
AVFoundation automatic shared-audio-session configuration, and detaches the
microphone before releasing the exact lease on every terminal path. Silent
recordings do not acquire or deactivate a lease. Concurrent movie requests
cannot reconfigure an admitted recording. This closes the unregistered
video-owner gap where delayed Explore/Insight playback teardown could deactivate
camera audio. Empty microphone removals and an already-attached movie output
avoid unnecessary session configuration transactions while still refreshing
connection settings. `CameraVideoAudioSessionTests` covers that delayed
teardown, failure/retry, cancellation, silent recording, overlapping admission,
and replacement playback. Its live-input adapter tests also prove an empty
detach never discovers a microphone, silent recording stays microphone-free, and
an audio-enabled failure/retry discovers input only after lease activation.

## Camera verification

Changes to `CameraManager.swift` or `Camera/` must run the generated-project and
source-membership gates, the focused `CameraManagerTests`,
`CameraPhotoCaptureCoordinatorTests`, `CameraVideoRecordingCoordinatorTests`,
`CameraSessionPolicyTests`, `CameraSessionControllerTests`,
`CameraVideoAudioSessionTests`, `AudioSessionCoordinatorTests`, and
`CameraArchitectureTests` selectors, and then the complete `merianTests` target.
Use the canonical commands and evidence rules in the
[testing strategy](../../../../../docs/development-guides/08-testing-strategy.md#camera-verification).
`CameraManagerTests` freezes the non-eager recording-service construction
contract, while `CameraSessionControllerTests` freezes non-eager capture-stack
construction, no-op control/stop behavior before first resolution, stop
completion delivery without a session, single root-session creation under
concurrent access, and retry after a transient required-input configuration
failure. Pure policy, construction, and architecture tests do not exercise
AVFoundation hardware.

Before release, verify on a physical device that capture starts after camera and
microphone authorization, photo capture completes, a five-second recording and
an early manual stop each finish exactly once, rotation and stabilization remain
correct, foreground/session interruption recovery succeeds, and rapid
thermal/FPS target changes settle on the latest target. Exercise the same flows
with depth capture enabled on supported hardware. Play audible media in Explore
or Insights, return to Scan, and test the first and repeated Pro video captures
with microphone access both granted and denied. Confirm the microphone is
released after completion, cancellation, and timeout, and that playback works
afterward. Record evidence obtained on simulators and physical devices
separately; neither substitutes for the other.
