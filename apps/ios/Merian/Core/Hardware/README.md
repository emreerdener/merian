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
the shared capture bar. `AppDIContainer` creates the long-lived observable
instance; feature views receive it through the established environment and pass
narrow actions into feature state owners.

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

`AudioCaptureManager` owns the long-lived bioacoustic engine, bounded PCM-to-DSP
stream, 15-second Int16 WAV lifecycle, review playback, and observable capture
state. Its maximum-duration feedback is initializer-injected; `AppDIContainer`
supplies the live heavy-impact closure so the manager does not resolve haptics.
Record views receive an immutable presentation projection and never access the
manager directly. Manager-owned startup and resume task handles share a
generation fence with DSP and countdown publication. Leaving Audio,
backgrounding, reset, pause, stop, and replacement invalidate that fence; a late
or cancellation-ignoring activation releases its lease without starting the
engine or mutating a newer session.

`AudioSessionCoordinator` is the cross-feature, token-aware lease owner for
recording and playback audio sessions. `AudioCaptureManager` and `SpeechManager`
release only their current lease, so delayed teardown from an older operation
cannot deactivate a replacement session. Keep this owner separate from either
feature and do not call `AVAudioSession.sharedInstance()` from a paged view. A
lease becomes current only after configuration and activation both succeed, and
successful deactivation consumes it. A failed replacement restores the prior
configuration before leaving that lease current. If restoration also fails, the
coordinator deactivates the partial session and invalidates prior ownership
rather than publishing a lease for an unknown configuration. A failed first
activation likewise deactivates any partially activated session before returning
the error.

`SpectrogramActor` owns the off-main FFT, mel-scale projection, and bounded
rolling ambient-noise floor. Its guidance policy classifies clipping by peak and
the remaining levels by the rolling minimum RMS floor; it is not a calculated
signal-to-noise ratio in decibels. Rendering belongs to `Core/Media` and
`Core/UI`, while Record owns only the mounted guidance and scrub interaction.

Manager and DSP tests live in
`apps/ios/MerianTests/Core/Hardware/AudioCaptureManagerTests.swift` and
`SpectrogramActorTests.swift`. Transition-token and audio-session lease tests
live beside them in `AudioCaptureTransitionStateTests.swift` and
`AudioSessionCoordinatorTests.swift`. Record presentation tests remain with the
feature, and reusable raster tests live in `Core/Media` test ownership. The
coordinator suite covers successful replacement, failed-replacement restoration,
failed-rollback invalidation, and failed-first-activation cleanup.

## Location authorization and deterministic UI tests

`EnvironmentContextManager` owns the runtime location-authorization request gate
used by Capture and Explore. Both the eager `validatePermissions()` path and the
async `requestLocationAuthorizationIfNeeded()` path must call
`shouldRequestLocationAuthorization(...)` before asking Core Location to present
a system prompt.

The common Debug UI-test launcher supplies
`-seedLocationPermissionPromptSuppressed`. The flag is honored only when the
`UITesting` environment contract is also active; it suppresses the Core Location
prompt without fabricating authorization, coordinates, or cached environment
context. A future UI test that intentionally exercises the iOS location prompt
must use a launcher that omits this argument. The Release
`UITestSeedCoordinator` implementation always disables the fixture, and archive
validation rejects the marker if it reaches the main executable.

## Push notification routing

`PushNotificationManager` owns `UNUserNotificationCenter` delegate work and
notification payload parsing. It emits validated typed `AppRoute` requests
through an initializer-injected main-actor closure. The private production
initializer binds that closure to the app-host `AppRouteCoordinator`; tests
construct the manager with a private coordinator so they do not mutate shared
application routing state. Dismiss actions remain non-routing, and the route
source remains `.pushNotification`.

Keep payload parsing and OS delegate timing in Hardware, typed route policy in
Core Utilities, and presentation in the Capture workspace host. Coverage lives
in `MerianTests/Core/Hardware/PushNotificationManagerTests.swift` and
`MerianTests/Core/Utilities/PushNotificationRoutingTests.swift`.

Push registration, notification catalog/count, and mark-read wire requests live
in `Core/Network/Endpoints/MerianNetworkClient+Notifications.swift`.
`PushNotificationManager` still owns permissions, token synchronization, and
registration lifecycle; `AppIconBadgeCoordinator` still owns badge refresh/cache
policy. Endpoint extraction does not move OS integration or badge state into
Network. `NotificationEndpointTests` covers request fields and count
projections, and `NotificationAndPublicProfileEndpointTransportTests` covers
replay, cancellation, and body-ignoring registration success. Run the
[Core Network notification/public-profile matrix](../Network/README.md#notification-and-public-profile-verification)
for changes across this boundary.

## Camera frame-rate observation

`CameraManager` observes `HardwareOrchestrator.targetFPS` with one-shot
observation tracking. The change callback must re-arm observation before it
suspends. `CameraTargetFPSDebouncer` then cancels and replaces pending
applications, correlates each task with a UUID generation, and reads the current
target after the 100 ms debounce. This keeps rapid thermal escalation and
recovery aligned with the latest hardware target even when cancellation finishes
cooperatively.

Only the debounce policy and observable target live on `@MainActor`.
`AVCaptureSession.inputs`, device locking, and frame-duration changes continue
on the serial camera queue.

## Camera recording concurrency

`CameraManager` owns AVFoundation session mutations and all movie-output and
connection state on its serial camera queue. A video request is identified by
both a UUID generation and its UUID-derived output URL. Delayed timeouts and
automatic stops also carry an action UUID so a cooperatively cancelled task
cannot act after replacement. Recording delegate callbacks must match the
configured output and the current URL before they may clear state or resume a
continuation. Keep observable UI updates on `@MainActor` and guard them with the
same recording generation.

The recording state lives as one value under `videoRecordingLock`. Do not split
the continuation, URL, timer tasks, or start metadata into independently mutable
properties, and never nest `videoRecordingLock` with the camera manager's other
locks.
