# Core Application Services & Managers

Merian uses a structured singleton pattern managed through
`AppDIContainer.swift`. These singletons own global application state without
triggering excessive SwiftUI view rebuilds.

## Hardware Domain

### `SpeechManager`

- `@MainActor @Observable final class` living at
  `apps/ios/Merian/Core/Hardware/SpeechManager.swift`, registered in
  `AppDIContainer` and distributed to the view hierarchy via
  `DIContainerModifier`.
- Owns the cross-feature `AVAudioEngine` + `SFSpeechRecognizer` pipeline used by
  Capture Describe, Insight Field Notes, Insight media coordination, and the
  shared capture bar.
- **`isRecording: Bool`** — the single source of truth for dictation state.
  `DescribeInputLifecycleObserver` forwards changes to the generation-fenced
  `DescribeInputViewModel`, which clears
  `CaptureActionCoordinator.isDictationRequested` after automatic termination.
  `FieldNotesEditorView` forwards the same transition to
  `FieldNotesEditorViewModel`, which clears editor ownership and rejects late
  transcription without repeating shared teardown. Never set it to `true` until
  `audioEngine.start()` succeeds; reset it to `false` in all failure and
  teardown paths.
- **`isStarting: Bool`** — prevents overlapping permission/session startup and
  exposes a request that is still negotiating permissions or audio hardware.
  Capture Describe uses that state to end the UI request while letting the
  canceled startup own its cleanup; it does not call shared teardown
  concurrently with configuration.
- **`startDictation(onResult: @MainActor @escaping (String) -> Void) async throws`**:
  - Returns without opening another session when `isStarting` or `isRecording`
    is already true. Callers must verify the post-await recording state instead
    of treating a non-throwing return as proof that they own speech input;
    Capture Describe's injected adapter does this and clears a rejected request.
  - Requests microphone permission with
    `AVAudioApplication.requestRecordPermission()`. Throws `PermissionError` on
    denial; the lifecycle observer clears the requested-recording state so the
    control returns idle.
  - Requests speech authorization, then retries recognizer availability five
    times at 200 ms intervals. If no recognizer becomes available, throws
    `DictationUnavailableError` instead of leaving the button in a starting
    state.
  - Checks `Task.isCancelled` after each `await` suspension point. If cancelled
    after the `AVAudioSession` was already activated, releases the current
    `AudioSessionCoordinator.Lease` before returning — preventing stale
    deactivation work from killing a newer audio session.
  - Configures `AVAudioSession` as `.record` / `.measurement` through
    `AudioSessionCoordinator.shared.activate(.recordMeasurement(...))`, not by
    calling `AVAudioSession.sharedInstance()` directly on the main actor. This
    serializes dictation with `AudioCaptureManager` and makes teardown
    token-aware.
  - `isRecording = true` is assigned as the **absolute final line** — only after
    `try audioEngine.start()` confirms the engine is live.
- **Capture Describe adapter boundary**: The Services-owned
  `DescribeInputViewModel.Dependencies.live(speechManager:)` factory is the only
  Describe state-layer code that references the concrete manager. The view model
  stores closure dependencies, generation-fences partial results, and retains a
  canceled startup handle. A replacement start awaits that handle; if a
  cancellation-ignoring dependency returns `true`, the stale session is stopped
  before the replacement calls the manager. This prevents `stopDictation()` from
  racing detached audio configuration while preserving deterministic cleanup.
- **Insight Field Notes adapter boundary**: `FieldNotesSheet` reads the
  environment-owned manager and constructs the Services-owned
  `FieldNotesEditorDependencies.live(speechManager:)` adapter.
  `FieldNotesEditorViewModel` owns the session generation, serializes
  replacement startup behind canceled teardown, and rejects callbacks after
  explicit stop or automatic termination. Its focused tests also prove automatic
  termination does not call shared teardown a second time.
- **`stopDictation()`** — delegates entirely to `teardownAudioEngine()` then
  sets `isRecording = false`. Safe to call when the engine was never started.
- **`teardownAudioEngine()` (private)** — whenever an engine exists, calls
  `audioEngine.stop()` and `audioEngine.inputNode.removeTap(onBus: 0)`. This
  prevents an orphaned tap crash when `start()` throws after `installTap` has
  already been called. Ends and nils the recognition request and task, then
  releases the leased audio session through
  `AudioSessionCoordinator.shared.deactivate(ifCurrent:)`.
- **Auto-termination**: The `SFSpeechRecognitionTask` result handler dispatches
  back to `@MainActor` via `Task { @MainActor [weak self] in ... }`. When
  `error != nil || result.isFinal == true`, it calls `stopDictation()`
  internally — the user does not need to tap the mic again to stop a session
  that the system ended (e.g. 60-second silence timeout).
- **`PermissionError`** — a `LocalizedError` struct defined in the same file.
  Thrown on permission denial or an unusable zero-Hz input format. The lifecycle
  view models catch startup failures through injected adapters: Describe clears
  the requested-recording flag, while Field Notes clears editor ownership and
  presents the localized inline error. No mode-specific error handling lives in
  the shared manager.

### `AudioSessionCoordinator`

- Swift actor at `apps/ios/Merian/Core/Hardware/AudioSessionCoordinator.swift`
  that serializes process-wide recording and playback session ownership.
- `activate(_:)` returns a monotonically tokened `Lease`; teardown calls
  `deactivate(ifCurrent:)`, so an obsolete Speech, Record, or playback owner
  cannot deactivate a newer session.
- Ownership advances only after the complete configuration and activation
  operation succeeds. A failed replacement restores the prior configuration
  before leaving its lease current. If that rollback fails, the coordinator
  deactivates the partial session and invalidates prior ownership. Successful
  deactivation consumes the current lease so repeated teardown is a no-op. A
  failed first activation also deactivates any partial session and publishes no
  lease.
- `MediaPlaybackAudioSession` remains beside the coordinator because Explore and
  Insight playback use the same process-wide activation contract. Feature views
  do not call `AVAudioSession.sharedInstance()` directly.

### `AudioCaptureManager`

- `@MainActor @Observable final class` at
  `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift`. `AppDIContainer`
  constructs it with an injected maximum-duration heavy-feedback closure and
  distributes it via `DIContainerModifier`; the manager does not resolve the
  haptic singleton.
- Owns the full `AVAudioEngine` bioacoustic recording pipeline for the `.audio`
  capture page.
- **`isRecording: Bool`** — single source of truth for recording state. Set to
  `true` only after `audioEngine.start()` succeeds.
- **`isPaused: Bool`** — engine is paused mid-recording (tap preserved,
  countdown halted). Can only be `true` when `isRecording` is also `true`.
- **`recordingProgress: Double`** — 0.0 → 1.0 over 15 seconds, driven by a
  100-tick countdown Task (150 ms per tick).
- **`spectrogramColumns: [SpectrogramColumn]`** — rolling 360-column display
  buffer fed by `SpectrogramActor` from each 2048-frame FFT window.
- **`snrLevel: SNRLevel`** — most recent legacy-named ambient-noise/clipping
  classification from `SpectrogramActor.snrLevel(from:)`.
- **`pendingPlaybackPath: String?`** — non-nil after recording finishes, before
  the user confirms or discards. Drives the review state UI.
- **`playbackProgress: Double`** — 0.0 → 1.0 playhead position; preserved across
  play/stop cycles so `playPendingRecording()` resumes from the scrubbed
  position.
- **`audioFilePath: String?`** — set to the WAV filename when the user confirms
  via review UI, or when a maximum-duration recording auto-confirms because
  confirmation is disabled; consumed and cleared by
  `CaptureWorkspaceOrchestrationModifier.onChange`, which either stages the clip
  into `stagedCapture.audios` for the shared mixed-media toolbar flow or routes
  it through `submitAudio` for the audio-only flow, then calls `reset()`.
- **`requestMicrophonePermissionForRecording() async throws`**: called only from
  the explicit Audio red-button action, before camera handoff. This keeps the
  system prompt tied to the user action.
- **`startRecording() async throws`**: guards with
  `!isRecording && !isStartingRecording` (the `isStartingRecording` flag is set
  before detached engine setup to prevent a second call from slipping through
  the guard during the asynchronous setup window — this was the source of the
  `nullptr == Tap()` AVAudioEngine crash). It never prompts and fails closed
  unless microphone permission is already granted. Session activation flows
  through the shared `AudioSessionCoordinator`, which returns a lease token
  stored on `AudioCaptureManager`; teardown deactivates only if that lease is
  still current, eliminating stale stop-work from interrupting a newer
  record/playback cycle. Writes **Int16 PCM WAV** via an explicit
  `AVAudioFormat(commonFormat: .pcmFormatInt16, ...)` to avoid the
  WAVEFORMATEXTENSIBLE (`audioFormat = 0xFFFE`) variant that the edge audio
  parsers do not support. The tap now copies each `AVAudioPCMBuffer`
  synchronously into a bounded `AsyncStream(bufferingNewest: 2)` before handing
  it to `SpectrogramActor`, preventing tap-owned buffers from crossing the async
  boundary and capping DSP backlog.
- **Recording-transition fence** — startup, resume, DSP publication, and the
  countdown carry an `AudioCaptureTransitionToken`. The manager retains startup
  and resume task handles, invalidates their generation on lifecycle exit,
  pause, stop, cancel, reset, or replacement, and releases a late lease without
  starting its engine. `cancelPendingRecordingTransition()` is the narrow Shell
  hook used before pausing on mode/background changes.
- **Camera handoff contract** — `CaptureControlBar` owns one cancellable audio
  startup task and awaits `CameraManager.stopSessionAndWait()` before calling
  `startRecording()`. Leaving Audio, backgrounding, or removing the control bar
  cancels that outer task and invalidates the manager-owned transition without a
  toast. This prevents rapid Camera → Audio → Record and Audio → Camera
  reversals from overlapping camera and audio hardware ownership. Cancellation
  is explicitly forwarded to the detached AVFoundation setup task, which checks
  it after session activation and before engine start; the generation fence also
  rejects a dependency that returns despite cancellation.
- **Transient input-route recovery** — after the recording audio session is
  active, a zero-rate or zero-channel input format is retried four times at 75
  ms intervals with `audioEngine.reset()`. A route that remains invalid after
  the bounded 300 ms window still throws
  `AudioCaptureError.hardwareSampleRateZero`.
- **`pauseRecording()`** — invalidates pending transition work, cancels the
  countdown, calls `audioEngine.pause()`, and sets `isPaused = true`.
- **`resumeRecording()`** — retains one manager-owned task, coalesces duplicate
  taps while activation is pending, reacquires a fresh
  `AudioSessionCoordinator.Lease`, and verifies its transition and engine
  identity before calling `audioEngine.start()` and rebuilding the countdown
  from current `recordingProgress`.
- **`stopRecordingEarly()`** — cancels the countdown and always routes the
  partial clip to review. Only reaching the 15-second maximum may bypass review
  when confirmation is disabled.
- **`seekPlayback(to:)`** — seeks `AVAudioPlayer.currentTime` and updates
  `playbackProgress`; works while playing or stopped.
- **`cancelRecording()`** — cancels countdown task, tears down engine, deletes
  partial file from `tmp/`, calls `discardPending()`.
- **`discardPending()`** — deletes pending file if present, **always** clears
  `spectrogramColumns`, `snrLevel`, `snrHoldTicks` — display state is cleared
  unconditionally (not gated on `pendingPlaybackPath`) so calling it before
  `startRecording()` also wipes the previous session's columns.
- **`reset()`** — tears down the engine/tap/session lease, deletes any
  unsubmitted pending temp file, clears playback/review/spectrogram state, and
  prepares the next session. Call after `audioFilePath` has been consumed by the
  `CaptureWorkspaceOrchestrationModifier.onChange` handoff (stage-or-submit), or
  from that modifier when `CaptureWorkspaceView` disappears.
- **Playback finalization**: `playbackCompletionTask` is now a stored handle,
  cancelled by `stopPlayback()` and `reset()`. This prevents an orphaned sleep
  task from retaining `AVAudioPlayer` and from clearing a newer playback session
  after the user has already stopped or restarted audio.
- **Record presentation adapter**: Capture Shell resolves the environment-owned
  manager, while `Capture/Record/Services/AudioRecordingDependencies.swift` is
  the only Record file that projects its state and actions. The Record view
  model receives closure dependencies and owns only idle artwork and review
  scrubbing.
- **Strict Requirement**: Never call `AVAudioSession.sharedInstance()` directly
  on `@MainActor`. Route all activation/deactivation through
  `AudioSessionCoordinator`.

### `SpectrogramActor`

- Swift `actor` at `apps/ios/Merian/Core/Hardware/SpectrogramActor.swift`. All
  FFT and mel-scale arithmetic runs on a background actor thread, keeping
  `@MainActor` free for 60fps rendering.
- **2048-point real FFT** via Accelerate `vDSP_fft_zrip` with
  `vDSP_hann_window`. Wrapped in `autoreleasepool` per buffer to prevent
  `AVAudioPCMBuffer` Obj-C object accumulation.
- **128-bin mel scale**, 80 Hz – 16 kHz: covers the bioacoustically relevant
  range for bird, insect, and frog ID.
- **`processColumns(buffer:) -> [SpectrogramColumn]`** — main entry point from
  the tap callback; emits one column per 2048-frame window so a 4096-frame tap
  contributes two visual columns instead of dropping half of the buffer.
- **`process(buffer:) -> SpectrogramColumn?`** — compatibility helper that
  returns the first processed column.
- **`snrLevel(from:) -> SNRLevel`** — rolling 48-entry noise floor history (~2
  s). Despite the historical type name, non-clipping levels use the absolute
  rolling minimum RMS floor: `.clipping` (peak > 0.95), `.warning` (floor >
  0.08), `.caution` (floor > 0.015), `.clear` (floor ≤ 0.015).
- **`reset()`** — clears the noise floor history. Called by
  `AudioCaptureManager.reset()` between sessions.

### `CameraManager`

- Abstracts AVFoundation via `AVCaptureDevice.DiscoverySession`, preferring
  `.builtInTripleCamera` on Pro devices for optical zoom support, falling back
  to `.builtInLiDARDepthCamera`, `.builtInDualCamera`, `.builtInDualWideCamera`,
  and `.builtInWideAngleCamera` in that order. Depth data via
  `AVCaptureDepthDataOutput` is attached conditionally and works with any device
  in the list that supports it.
- Activated via `.handleActivePhase()` calls in `MerianApp.swift`.
- Governs `subjectDistanceInMeters`, auto-focus thresholds, thermal bounds, and
  frame drops on the dedicated camera queue.
- Avoids Accelerate `vImage` CPU starvation during paused states via an atomic
  `nonisolated(unsafe) private var activeInferencePaused` boolean, synchronized
  with the `@MainActor` preference boundary. When set, this triggers an early
  return in `captureOutput`, halting the histogram allocation pipeline and
  preserving battery and thermals whenever the Viewfinder AI is paused.
- **Deferred Mutex Unlocks**: Mitigates AVFoundation buffer leaks and device
  thread lockouts by placing `defer { device.unlockForConfiguration() }` and
  `defer { CVPixelBufferUnlockBaseAddress }` guards across all hardware control
  paths.
- **Session Queue Ownership**: `AVCaptureSession.inputs` and all video-device
  lookups must run inside the camera queue. `toggleFlash()`, `applyZoom`,
  focus/exposure, FPS changes, and idle throttling keep AVFoundation reads and
  `lockForConfiguration()` off `@MainActor`, then publish `isFlashEnabled`,
  `zoomFactor`, or other observable state back via `Task { @MainActor in ... }`.
  Never read `session.inputs` synchronously from a SwiftUI action handler.
- **Latest-State FPS Debounce**: `withObservationTracking` registrations are
  one-shot. The target-FPS callback must re-arm `trackFPS()` before awaiting or
  scheduling delayed work. `CameraTargetFPSDebouncer` owns a cancel-and-replace
  task plus UUID generation, reads `HardwareOrchestrator.targetFPS` after the
  100 ms delay, and uses compare-before-apply/clear semantics. Never capture an
  FPS value before the delay or rely on task cancellation alone; either pattern
  can let a stale thermal generation survive.
- **Recorded Video Stabilization Boundary**: `AVCaptureMovieFileOutput` may be
  pre-attached during visual camera setup so the hold-to-record path feels
  immediate, but its video connection keeps stabilization off until
  `recordVideo(...)` is actually starting a clip. The start path requests
  AVFoundation `.auto` stabilization only when the connection reports support,
  logs the requested and active mode through `MerianLog.hardware`, and resets
  the connection to `.off` on finish, cancellation, or failure so still-photo
  captures do not inherit stabilization crop, latency, or resolution changes.
- **Video Recording Generation Boundary**: one active recording value owns the
  continuation, UUID generation, UUID-derived output URL, start metadata, and
  scheduled tasks under `videoRecordingLock`. Timeout and automatic-stop work
  must match both the generation and its current action UUID; task cancellation
  by itself is insufficient because it is cooperative. Recording delegate
  callbacks first move to the camera queue, verify `movieOutput` identity, and
  match the callback URL before taking state. Never clear or resume recording
  state from a callback, timeout, stop, or cancellation path that does not carry
  the expected generation. All `AVCaptureMovieFileOutput` and connection access
  belongs to the camera queue; generation-checked UI state alone returns to
  `@MainActor`.

### `EnvironmentContextManager`

- Manages the `EnvironmentContext` struct, which is defined in
  `apps/ios/Merian/Core/Hardware/EnvironmentContext.swift` as a plain data model
  with `location`, `locationName`, `weatherCondition`, and `weatherTemperature`
  fields.
- Maintains two data sources without triggering UI rerenders:
  - **CoreLocation**: Caches and updates `CLLocationCoordinate2D`, `altitude`,
    and `course`.
  - **WeatherKit**: Fetches hyper-local `temperature` and `condition` to
    supplement inference payloads.
- Updates are gated by a `cacheThreshold` to limit unnecessary location and
  weather polling.
- **Concurrent geocode + weather**: In `fetchDeferredContext`,
  `reverseGeocode(location:)` is launched as an `async let` child task before
  the `weatherService.weather(for:)` call begins. Both I/O operations —
  typically 300–800 ms each — run in parallel, cutting total context-fetch
  latency by 300–1000 ms per shutter press.

### `PhotoLibraryManager`

- `@MainActor @Observable final class` at
  `apps/ios/Merian/Core/Data/Images/PhotoLibraryManager.swift`. It retains the
  production `.shared` singleton and accepts injected `AppSettings` for tests.
- Owns two distinct Photos boundaries: read/write access for the latest gallery
  thumbnail and add-only access for photo/video writes. Saving media must not
  broaden add-only authorization into library reads.
- Routes writes through one media-aware PhotoKit helper.
  `PhotoLibraryMediaKind.photo` creates a `.photo` resource after GPS scrubbing;
  `.video` creates a file-backed `.video` resource without decoding or rewriting
  the clip.
- `saveImageToLibrary` and `saveVideoToLibrary` are automatic capture methods
  and return immediately when `AppSettings.saveToCameraRoll` is false. The
  setting key and default-off behavior are stable.
- `saveImageManual` and `saveVideoManual` represent explicit Downloads and do
  not consult the automatic-save setting. They still require add-only Photos
  permission and report success as `Bool`.
- Awaits `PHPhotoLibrary.performChanges` before returning. The caller must keep
  an input video alive through that await. The manager deletes only temporary
  scrubbed photos that it created; it never deletes retained playback clips.
- Automatic camera writes assign the resolved shutter location to the Photos
  asset. Manual exports do not inject persisted scan telemetry as location.
- The complete contract, including capture ownership, approved cloud-host
  policy, count formatting, failure behavior, and device QA, is in
  [Camera Roll and Captured-Media Export](../features-and-hardware/27-camera-roll-media-export.md).

### `HapticManager`

- Governs `UIImpactFeedbackGenerator` tactile feedback.
- Generates `NotificationFeedback` for success/failure workflows without
  requiring `AudioToolbox` imports.
- **Strict Requirement**: Never use `UIImpactFeedbackGenerator` or
  `.sensoryFeedback` modifiers directly in views. Always route haptic feedback
  through `HapticManager.shared` API methods (e.g., `triggerSheetSpring()`,
  `triggerLightImpact()`) to ensure the user's `isHapticsEnabled` preference is
  respected globally.
- `HapticManager`, `HardwareOrchestrator`, and `PhotoLibraryManager` keep
  `.shared` production singletons but accept injected `AppSettings` for isolated
  tests and previews. Do not reach around those injected boundaries with direct
  `UserDefaults.standard` writes in tests; mutate the injected `AppSettings`
  instance instead.
- **Analysis-phase haptic map**: Four strategic touchpoints span the analyzing
  experience in `InferenceEngine` and `InsightHeader`:
  - `triggerLightImpact(intensity: 0.3)` — fires when `isVisionStreaming` flips
    to `true` (Vision pipeline onset).
  - `triggerSelectionPulse()` — fires on every badge phrase rotation tick after
    the first (every 2.3 s).
  - `triggerLightImpact(intensity: 0.5)` — fires in `InsightHeader.onAppear`
    when the common name title animates in from the analyzing state (peak reveal
    moment).
  - `triggerSelectionPulse()` — fires after the 700 ms Vision→Gemini paragraph
    crossfade delay, marking the hand-off from local to cloud reasoning.

### `PushNotificationManager`

- Encapsulates `UNUserNotificationCenter` operations on the `@MainActor` thread.
- Polls `authorizationStatus` to keep the local
  `AppSettings.isPushNotificationsEnabled` /
  `UserDefaultsKeys.isPushNotificationsEnabled` flag in sync with the OS
  Settings state. If a user revokes permissions externally, the local flag is
  corrected asynchronously via `Task { @MainActor in }` (not
  `DispatchQueue.main.async`) to maintain Swift 6 strict concurrency compliance.
- Configured as the `UNUserNotificationCenterDelegate`. Injects `scanId` values
  into `.userInfo` payloads so background offline completions can surface
  notifications over the lock screen.
- **Rich Media & Categorization**: Registers custom categories
  (`INFERENCE_COMPLETE`) with Interactive Actions ("View Details", "Share
  Discovery") and natively attaches species thumbnail images for premium
  lock-screen previews.
- **Delivery Control**: Uses `threadIdentifier` (`inference_complete_thread`) to
  prevent lock-screen explosion when sequentially scanning subjects, and
  elevates deliveries to `.timeSensitive` automatically (iOS 15+) for priority
  pass-through during field-use.
- **Deduplication**: `sendInferenceCompleteNotification` guards against
  duplicate notifications using a session-scoped `notifiedScanIds: Set<String>`.
  The first call for a given scan ID proceeds and inserts the ID; subsequent
  calls for the same scan return immediately. The `UNNotificationRequest` uses
  `"inference_\(scanId)"` as its identifier rather than a fresh `UUID`, so even
  if two requests reach `UNUserNotificationCenter` concurrently (not possible on
  `@MainActor` but defensive), the OS deduplicates them. This prevents the user
  receiving two "Analysis complete" alerts when both the live inference path and
  the background URLSession path complete for the same scan in close succession.
- **Safe Deep Linking**: Intercepts deep link taps from notification actions and
  routes the UI directly to the relevant `InsightSheet`. It rigorously filters
  out `UNNotificationDismissActionIdentifier` to ensure users who simply swipe
  away a notification are not forcefully navigated when they next open the app.
- **Context-Aware Foreground Suppression**:
  `willPresent(_:withCompletionHandler:)` reads the persisted
  `suppressInferenceBanners` flag synchronously because the notification
  delegate is nonisolated and must call its completion handler immediately. All
  app code that mutates this flag goes through
  `AppSettings.suppressInferenceBanners`; `InsightSheetView` sets it to `true`
  on `onAppear` and clears it on `onDisappear`, so the flag precisely tracks
  insight sheet visibility. When `true`, inference notifications are delivered
  silently via `completionHandler([])` because the user can already see the
  result. Native achievement notifications are also foreground-suppressed via
  `completionHandler([])` so the SwiftUI milestone banner owns active in-app
  unlock UX without stacking under an iOS banner. Background delivery bypasses
  the delegate and remains native. **Both notification call sites
  (`InferenceEngine` and `OfflineQueueManager+URLSession`) schedule
  notifications unconditionally — without any `applicationState != .active`
  guard.** Foreground suppression is delegated entirely to this `willPresent`
  path; background delivery bypasses the delegate and is shown automatically by
  the OS.
- **App Icon Badge Synchronization**: Exposes `setBadgeCount(_:)` to mirror the
  application's `hasUnseenScan` state into the OS-level app icon badge count,
  seamlessly providing a visual indicator on the Home screen. This cleanly
  branches between modern `UNUserNotificationCenter` APIs (iOS 16+) and standard
  `UIApplication` fallbacks, keeping inference alerts directly coupled to the
  user's scan-viewing behavior.
- **Explore unread coordination**: `AppIconBadgeCoordinator` is the single
  process-wide owner of unread-count refreshes used by lifecycle, `MainTabBar`,
  and Explore. Concurrent callers await the same task, and a successful result
  is reusable for 10 seconds. Explore-post activity uses Realtime as the primary
  update path and polls every five minutes to cover Field trip-only activity,
  missed events, and subscription failure. Realtime events and notification-
  sheet dismissal use `force: true`. Failed or cancelled refreshes do not start
  the reuse window or erase the last persisted count.

## AI & Offline Synchronization

### `InferenceEngine`

- The core processing unit in `apps/ios/Merian/Core/AI/`.
- Dispatches sensor data via `CaptureTelemetry` — forwarding `depthScaleText`,
  `deviceLocale`, `currentMonth`, and coordinate state — to the active Supabase
  Edge path (`MerianNetworkClient.identifyMultiModal` /
  `buildMultiModalRequest(...)`).
- Selects between `gemini-2.5-flash` and `gemini-2.5-pro` based on the user's
  subscription tier, then maps the taxonomy strings from the response back to
  local model properties.
- Maps ephemeral telemetry metadata (`gpsLatitude`, `gpsLongitude`,
  `gpsElevation`, `weatherCondition`, `weatherTemperatureF`, `locationName`)
  into the parsed `SpeciesData` model, abstracting this detail from the Edge
  runtime and making it consistent across live and offline inference paths.
- The payload is already durable in `OfflineQueueManager` before provider
  dispatch. On network failure, the engine retires only its exact foreground
  generation so background recovery can resume; it publishes Graceful
  Degradation UI only if that full generation is still current.
- **Server success fence**: Current `/identify-multimodal` `200` means
  moderation, required media promotion, primary species resolution, scan
  creation, and owner-scoped read-back have completed. Operational finalization
  failure is retryable `503 scan_persistence_failed`; terminal policy rejection
  is `400 observation_rejected`. Neither is a successful result to commit
  locally.
- **First-result critical path**: visual analysis receives the original
  Analyze-tap timestamp, commits persisted media and parsed `speciesData`
  immediately, and measures the response-to-state boundary. A one-shot UIKit
  draw probe in `InsightSheetView` closes tap-to-first-render timing on the
  first actual result frame. `ScanMilestoneCoordinator` runs in follow-up work,
  polls `/check-scan-status` before retrieving the server-applied Field trip
  progress receipt, then calculates awards and batches standard outings,
  Seasonal Challenges, achievements, and **New to Naturebook**. The coordinator
  derives a lowercase coordination key at ingress but preserves the caller's
  trimmed ID for network and durable-store operations. The queue generates
  lowercase UUIDs but preserves caller-supplied stable IDs. This prevents
  server/client casing from splitting milestone ownership without changing a
  caller's queue identity contract. Tools requiring server persistence stay
  disabled until the existing ingestion ledger confirms the final scan ID. The
  progress call may carry the durable camera-only selected-goal hint, and its
  completion publishes a scan-specific contribution invalidation so an open
  historical Insight reloads without replaying milestone celebrations.
- **Inline/background upload handoff**: `analyze()` installs a two-second
  fail-safe, then asks `MerianNetworkClient` to release the live scan's deferred
  queue row when request-body upload completes. Network failure releases the row
  immediately. Every callback carries the expected foreground generation, so a
  delayed callback is an idempotent no-op after replacement. Progress, response
  fallback, failure, and timer races cannot release another attempt's queue
  ownership. A separate foreground-inference claim lets recovery media stage
  without allowing staged replay to dispatch a duplicate primary identification.
- **Post-inference carousel handoff**: On a successful result, the saved user
  media is rebuilt into `ActiveScanMedia` _before_ `speciesData` is assigned.
  This ensures the insight sheet carousel always has the user's saved
  image/audio/description pages available on first render — the reference image
  is never the only visible page when the sheet opens. After `speciesData` is
  set, the transient live image frame is cleared.
- **Shared live-success finalization**: `analyze()` and `analyzeNonVisual()`
  share private finalization helpers for new-discovery marking, achievement
  notification refresh, reanalysis metadata transfer (`customTags`, collections,
  field notes), exact-generation queued-scan flush/delete handoff, completion
  notification delivery, and reference URL normalization. The helpers stay
  inside `InferenceEngine` so they preserve `@MainActor` state ordering and the
  `AppDIContainer` singleton boundaries while removing duplicated success-path
  logic.
- **Non-biological correction reanalysis**: Correction from the Non-biological
  collection is a scoped refinement entry point, not a record mutation. The old
  non-biological record stays unchanged until a replacement result succeeds.
  This entry point bypasses only the Pro reanalysis feature gate; the submitted
  replacement still goes through normal paid → complimentary → Flash selection
  and applicable scan accounting.
- **Shared post-inference hydration**: Biological visual, audio, and describe
  results all route through `schedulePostInferenceHydrationIfNeeded(...)`, which
  owns the single `liveHydrationTask`, skips Wikipedia when `wikipediaOverview`
  is already present, performs scoped enrichment before GBIF image hydration,
  and marks `enrichedSpeciesTimestamps` only after usable metadata lands. Visual
  captures pass `.showLoadingWhenReferenceMissing`; nonvisual captures pass
  `.none` so they keep the same quiet reference-loading behavior they had before
  the helper extraction.
- **TaskGroup Retain Cycles (`InferenceEngine`)**: Replaced implicit, strong
  `[self]` captures across `withTaskGroup` blocks with robust
  `@MainActor [weak self]` guard unwrapping. If network tasks stall, the engine
  immediately releases all in-flight state, enabling dynamic RAM scavenging and
  eliminating implicit zombie executions bounding the `InferenceEngine` layer.
- **Unconditional Local Notifications**: Dispatches a local "Analysis Complete"
  push notification upon successful inference without any
  `applicationState != .active` guard. `PushNotificationManager.willPresent`
  handles foreground suppression by reading the persisted
  `suppressInferenceBanners` key, while all UI/view-model mutation goes through
  `AppSettings.suppressInferenceBanners`. This ensures notifications fire when
  the user is in the library grid, but are silently delivered when the user is
  already on the insight sheet viewing results.
- **Live presentation lifecycle**: `activeScanId` identifies the durable scan,
  while `activeLiveInferenceAttemptGeneration` identifies the current
  presentation and `activeForegroundInferenceGeneration` identifies its durable
  queue owner. Task defer, provider dispatch, persistence, result/error
  publication, and background hydration compare the appropriate full tuple.
  Defer clears `isProcessing` and the active fields only when its presentation
  UUID still owns the slot. Background recovery may replace only the exact
  released presentation/foreground pair and invalidates that slot before
  cooperatively cancelling the live task.
- **Dedicated external API session (`externalAPISession`)**: Wikipedia and GBIF
  hydration calls use a `private static let externalAPISession` with its own
  `URLSessionConfiguration` (`timeoutIntervalForRequest = 5`,
  `timeoutIntervalForResource = 10`, `httpShouldSetCookies = false`,
  `urlCache = nil`). This session is isolated from the Supabase session so TLS
  pinning for `*.supabase.co` is never applied to public third-party endpoints,
  and the connection pool is independent from the Supabase auth pool.

**Multi-File Structure**: The engine is split across three files:

- `InferenceEngine.swift` — the main engine with its public API unchanged.
- `InferenceProcessingActor.swift` — a dedicated actor for base64 encoding and
  response parsing/persistence. It receives all data as parameters and has no
  access to `InferenceEngine`'s private state. It exposes two methods:
  `encodeBase64(compressedDatas:)` and `parseAndSave(...)`. `parseAndSave`
  returns a `ParseAndSaveResult` struct with `mappedData: SpeciesData?`,
  `isNewDiscovery: Bool`, and `savedPaths: [String]`, but the longer-term media
  source of truth is the ordered timeline exposed through
  `CapturedMediaSnapshot`. Persistence writes both the scalar
  `capturedMediaJSON` and the V41 `capturedMediaEntries` relationship; snapshot
  reads prefer the JSON mirror first so insight-sheet layout does not fault
  relationship rows on the main actor. Video entries are serialized as
  `StoredVideoMediaReference(video:, thumbnail:)`, keeping the playable `.mp4`
  and poster thumbnail together. The relationship mirror remains a fallback for
  older data and may only preserve the video path; the scalar JSON carries the
  richer poster metadata used by current UI and Explore sharing.
- `InferenceEdgeDTOs.swift` — contains hand-written `APIError` and enrichment
  DTOs plus the marked, generated `EdgeResponseWrapper`, `EdgeResponse`,
  taxonomy, insight, quality, candidate, and pet response graph. The Identify
  block comes from `_shared/identify/contract.ts`; regenerate it with
  `make generate-edge-dto-contract` rather than editing or extending it.
- `CapturedMediaWireDTOs.swift` — contains the separate generated PostgREST
  boundary for the durable `scans.captured_media` outer-key/`_0` union. Its
  source is `_shared/capturedMediaContract.ts`; regenerate it with
  `make generate-captured-media-dto-contract`. Keep this compatibility decoder
  separate from the Gemini response schema and map it into `SerializedMediaItem`
  only after validation.

### `OfflineQueueManager`

- Manages background `URLSession` uploads, queuing scan media to the local
  Documents Directory when the device is off-grid.
- **Durable live-scan suppression**:
  `enqueueCapture(...,
  startSyncImmediately: false)` persists eligible online
  live-camera still scans without immediately consuming the uplink twice.
  `syncPendingScans()` filters the process-local deferred-ID set until
  `releaseDeferredLiveUpload` is called with the matching foreground inference
  generation by inline request progress, its two-second fail-safe, request
  failure, connectivity loss, or app backgrounding. A stale release cannot
  affect a replacement generation. Relaunch starts with an empty set, so durable
  rows are never stranded after termination; live success still cancels tasks
  and removes the queue row through exact-generation cleanup. Gallery,
  audio-bearing, and video submissions continue using immediate background sync.
- **Deferred environment context**: `updateDeferredContext` merges late
  WeatherKit/geocoding values into the queued record. The live path also calls
  `/update-scan-context`, allowing the server to apply the same owner-scoped
  context to an in-progress ingestion or a completed scan without identifying
  the media again.
- Registers background handlers in `AppDelegate` so `URLSession` callbacks
  complete independently from the main UI thread.
- Uses `BackgroundTaskWrapper.execute(name:operation:)` to wrap operations in
  `UIBackgroundTaskIdentifier` windows, preventing system suspension mid-flight.
- **Durable job control plane**: `OfflineJobScheduler` is the reconnect facade.
  It delegates existing scan upload/replay execution back to
  `OfflineQueueManager` while scheduling cloud deletion and collection sync
  through `OfflineJobRecord` rows. `OfflineQueuedScan.queue*` fields and bounded
  `OfflineQueueEvent` rows replace the old process-local retry authority, so app
  relaunch preserves attempts, next retry time, last server stage, and
  user-attention state. A persisted deadline is not itself a timer:
  `OfflineJobScheduler` selects the earliest active scan/job deadline and owns
  one token-fenced wake, rebuilt after retry persistence, foreground activation,
  connectivity restoration, or queued-Insight presentation. Connectivity loss
  cancels the ephemeral task but not its durable source date. Stale dates use a
  bounded one-second wake; needs-attention rows are excluded; an atomic claim
  clears both scan and job deadlines. Automatic scan upload, inference, cloud
  deletion, and collection-sync retries all share
  `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`; after that ceiling
  the job moves to `needsAttention` instead of rescheduling.
- **Mixed-Media Persistence**: Persists one canonical ordered media timeline
  across images, videos, audio clips, and descriptions. Images, video clips, and
  video poster thumbnails are written to `.documentsDirectory` via
  `FileIOActor`. Pro video capture samples five inference frames and extracts
  video-audio WAVs from the original temporary recording, requests native
  AVFoundation stabilization for the active recording when supported, then
  stages an upload-bounded playback `.mp4` for local review, scan-library
  playback, Explore sharing, and cloud storage. The preferred playback file is a
  compressed network-optimized 720p export, but compression failure or timeout
  falls back to the original recording only when it remains within the hard
  video upload cap. Extracted video-audio WAVs are exported into Documents with
  `AVAssetReader` + `AVAssetWriter` and attached to the video media reference
  for inference replay rather than displayed as separate audio pages. New WAV
  and compressed-playback files remain in `CaptureScanTemporaryFileLease`
  ownership until staging accepts them. Parent cancellation propagates through
  `DetachedWork`, and cancellation, timeout, validation failure, supersession,
  or an unconsumed late result deletes every unaccepted artifact. The
  queue/database layers derive legacy arrays (`localImagePaths`,
  `localVideoPaths`, `audioFilePaths`, `observationContextsJSON`) from that same
  timeline at the edges. For video, `thumbnailImagePaths` includes the poster
  for thumbnails and upload previews, while `activeScanMedia` emits the video
  page itself so Insight does not show a duplicate image before the clip.
  Cloud-backed scan refreshes treat `scans.captured_media` as authoritative only
  when its nonempty decoded projection contains a usable image or video. Empty
  manifests and device-only legacy items fall through to durable URL/context
  columns; older rows with video URLs are normalized into playback video items
  so sampled inference frames do not appear as standalone carousel media.
- **Recursive Queue Draining**: The `URLSession` delegate calls
  `syncPendingScans()` recursively when a completed batch detects
  `unsyncedItemsCount > 0`, draining the queue automatically without user
  intervention.
- **Generation-fenced ownership**: Every upload batch and inference attempt has
  a UUID carried through background expiration, request preparation, URLSession
  task descriptions, delegate callbacks, retry/status scheduling, task
  cancellation, UI progress, and inference-driven queue deletion. Per-scan
  delayed work uses `GenerationTaskRegistry` slot tokens and
  compare-before-clear. A cooperatively cancelled task from attempt A cannot
  clear or cancel replacement B after resuming from an `await`. Status probes
  and server polls keep their token for the full awaited operation and
  revalidate after each suspension instead of clearing ownership before work
  begins. Current task descriptions are
  `upload_v2|ownerUUID|scanId|uploadIndex|generation|serverObjectKey` and
  `inference_v3|ownerUUID|generation|scanId`; parsers retain legacy
  compatibility for tasks created by older app builds. Carrying both the exact
  Auth owner and server-issued key prevents a cold-launch identity guess from
  changing the upload owner. Queue-backed foreground inference additionally
  persists its UUID on the scan-ingestion job and atomically consumes it before
  provider dispatch. `InferenceEngine` checks the scan, presentation UUID, and
  foreground UUID at task entry, after suspension, immediately before provider
  dispatch, and before each result or failure effect. A current failure handler
  snapshots that proof before synchronous retirement; a stale handler cannot
  emit telemetry, update the circuit breaker, trigger a haptic, or replace the
  UI with an error.
- **Orphaned `.uploading` Reconciliation**: `markScansAsUploading` runs before
  `generateUploadURLs`, returns the scan IDs whose `.pending → .uploading`
  transition actually committed, and `syncPendingScans` signs/dispatches only
  those claimed files. If the claim save fails, the actor rolls back and no
  URLSession tasks are launched. If the URL-generation request fails after a
  successful claim (e.g. task cancelled when the user backgrounds), any scans
  already transitioned to `.uploading` are reset to `.pending`, then each
  affected scan records durable retry metadata through
  `OfflineQueueRetryPolicy`. When the shared automatic retry budget is
  exhausted, those rows move to `queueNeedsAttention` rather than scheduling
  another in-memory retry. Additionally, `replayInferenceForUploadedScans`
  cross-references live URLSession tasks on every call to catch orphans that
  bypass the catch block. Upload/inference claims, retries, and both reconcilers
  use one cached queue actor. Each reconciliation captures `observedThrough`
  before URLSession enumeration and excludes rows updated later, so a stale task
  snapshot cannot reset a newer claim while waiting for that actor.
- **Server-Owned Inference Recovery**: Before replay resets an orphaned
  `.inferencing` scan, it polls `/check-scan-status` with the queued scan's
  required video count. A `found` result first persists the cloud-complete
  marker, then performs a targeted one-row history fetch. Successful hydration
  deletes the queue row. Transient fetch, lease, promotion, or queue-delete
  failures keep the row `.inferencing` and consume only the bounded local
  recovery budget. A decoded row that violates Captured Media Wire V1 returns a
  typed contract mismatch, skips the full-history fallback, and immediately
  pauses as `server_result_local_recovery_contract_mismatch` while retaining the
  cloud-complete no-redispatch fence. `processing` / `finalizing` / `retrying`
  server jobs schedule another poll, `failed_retryable` respects the server
  `retry_after` before retreating to `.staged` for provider failures or
  `.pending` with cleared consumed keys for durable media failures, and terminal
  failures mark the queue row as needing attention. The server job was claimed
  with the same media counts, staged object keys, upload-session ids, and
  manifest checksum that the queue submitted, and the paired version-3
  `scan_ingestion_intents` row stores the sanitized replay request for staged
  media/audio/video and text-only scans without retired description timestamps.
  The scheduled `replay-scan-ingestion` worker may complete that authoritative
  server attempt before the app wakes again, so local replay waits on status
  polling instead of guessing from process-local retry state. This keeps video
  playback finalization from being mistaken for a local inference failure after
  app suspension or restart. Server-side replay is also capped at 10 claims per
  sanitized intent; over-budget jobs are marked `failed_terminal` at
  `server_replay_limit_reached`.
- **`MerianConfig` Batch Limits**: `uploadBatchSize` (5),
  `pendingScanFetchLimit` (50), `mediaStagingMaxFilesPerRequest` (6),
  `mediaStagingMaxImageFilesPerRequest` (5),
  `mediaStagingMaxAudioFilesPerRequest` (2), `stagedImagePayloadMaxBytes` (5
  MB), and `audioPayloadMaxBytes` (2.7 MB) are governed by `MerianConfig`
  constants rather than inline literals.
- **`MediaStagingContract`**: Owns the canonical R2 staging manifest for queued
  images, audio, and video: sanitized filename, deterministic
  `staging/{userId}/...` key, media kind, content type, `sizeBytes`,
  `clientScanId`, `mediaRole`, optional `uploadPurpose`, upload task
  description, audio-file count, and byte-budget validation before
  `.pending → .uploading`. Ordinary ingestion omits the purpose;
  `scan_share_restore` is reserved for deterministic media repair of an exact
  scan after analysis or during guarded missing-owner-row recovery. A completed
  job requires a fresh unrestricted scan read: an existing row must be live and
  owner-exact, while a genuinely missing row may only stage for guarded
  reconstruction. Pre-scan signing grants no scan-write or publication
  authority. The same manifest is sent to `/generate-upload-urls`, whose Edge
  parser validates kind/type/size/role before signing and creates staged
  media-asset session rows for scan uploads. Ordinary inference audio is
  `.wav`/`audio/wav` only. M4A is a durable restore/playback format and requires
  exact `scan_share_restore` metadata plus `.m4a`/`audio/mp4`; the signer
  rejects extension/MIME mismatches. Before this validator runs, older
  pending/staged queue rows with local M4A atomically clear stale keys, hold a
  persisted repair latch, transcode into a Documents-owned WAV, rewrite both
  persisted media representations, and re-enter `.pending` for fresh signing.
  Upload and inference claims cannot consume an in-progress repair, and a failed
  legacy decode becomes needs-attention instead of a retry loop. The complete
  position-aligned signed response is validated before any PUT. Every response
  item declares the exact signed `Content-Type` and `Content-Length`; iOS
  applies both, and a signing-time file-size snapshot is rechecked immediately
  before task creation. Changed files discard their URL and re-sign on the next
  scheduler pass. Exact server keys—not locally predicted owner segments—travel
  in task descriptions. Swift and Deno tests both load
  `docs/contracts/media-staging-upload-manifest.json` to catch drift in limits,
  allowed content types, and optional session fields. This prevents upload
  completion, replay, request construction, and Edge signing from reconstructing
  object keys differently. The server later recovers those upload-session ids
  from `scan_media_assets` and includes them in the ingestion-job manifest
  checksum.
- **Concurrent upload staging (`withTaskGroup`)**: File copy and
  `URLSession.uploadTask` creation for each image in a batch are fanned out via
  `withTaskGroup`. Pre-flight guards (URL validation, file existence,
  tombstoning) remain serial; only the NVMe write (`FileManager.copyItem`) and
  task creation are concurrent. For a 3-image scan this eliminates 500 ms–2 s of
  head-of-line blocking before the OS background session takes over.
- **Serialized funding admission at enqueue time**: before writing files or
  allowing foreground inference, `insertAndPersistRecord` and
  `enqueueNonVisualCapture` synchronously call `EntitlementManager.claimFunding`
  for the active account and stable scan ID. Observable entitlement booleans
  remain UI hints. The manager subtracts unresolved local complimentary/legacy
  blockers from verified server availability and records paid Pro, complimentary
  Pro, immediate Flash, or deferred Flash. Only one image, standalone audio, or
  description with no video is Flash-eligible; mixed/multi-item/video work
  without Pro funding is rejected rather than queued. Immediate and deferred
  Flash reserve the advisory daily token before SwiftData commit. Save failure
  rolls back and refunds both local admissions before deleting staged files;
  `AppTelemetry.trackOfflineQueued()` is not fired on rejection.
- **Durable funding lifecycle**: the scan job persists `funding_reservation`
  beside `inference_generation`. Relaunch restores active claims; legacy jobs
  without funding are conservative blockers. Proven pre-dispatch failure first
  saves `funding_reservation_released: true`; a failed marker save keeps
  capacity reserved. Ambiguous delivery remains reserved, and manual retry of
  released work makes a fresh exact-shape claim. The scheduler dispatches
  complimentary claims first, uses one bulk funding-state read, refreshes
  entitlement for released/absent or terminal-consumed blockers, and persists
  paid/complimentary/immediate-Flash reclassification before dispatch.
  `syncPendingScans` performs no second advisory admission check. Supabase still
  applies authoritative entitlement and quota before provider work. Completion
  reconciles both `plan_used` and `credit_consumed`; paid or truly complimentary
  funding refunds an optimistic Flash token. Valid non-biological results count
  under their funding plan, and correction reanalysis does not bypass daily
  accounting.
- **Sync Phase Transitions**: Drives `SyncStateManager` through
  `.uploading(count:)` → `.inferencing` → `.finalizing` → `.idle` as the
  pipeline progresses.
- **Diagnostics export**: `writeQueueDiagnosticsExport(eventLimit:)` writes
  support JSON containing job rows, redacted queued-scan metadata, and queue
  events only. This internal exporter is not exposed in Settings. App
  version/build and embedded source revision/fingerprint/state bind the artifact
  to its exact binary. It intentionally omits raw media paths and payload
  contents, descriptions, Field notes, location/GPS, raw metadata, and arbitrary
  persisted error/event messages. Retained error/status/stage fields accept
  canonical lowercase machine tokens only. The versioned export caps jobs,
  scans, and events at 500 rows each and clamps all requested event limits to
  1...500; zero never falls through to a persistence API's “no limit” behavior.
  The temporary JSON uses complete data protection.

### `MessageScanShareCacheWriter`

- App-side writer for the iMessage scan library cache. It reads completed
  biological `LocalScanRecord` values, limits the snapshot to the 100 most
  recent scans, renders downsampled thumbnails and attachment JPEGs, and writes
  `message-scan-share-cache.json` plus image directories into
  `group.app.merian.shared`.
- The Messages extension reads this cache only. It must not open SwiftData,
  mutate scans, run inference, or assume the containing app is alive.
- The generated description text excludes field notes by default. Field notes
  are included only when the user explicitly enables the action-sheet toggle in
  the Messages extension.

### `SyncStateManager`

- `@MainActor @Observable` singleton exposing the current sync phase to UI
  components.
- Driven exclusively by `OfflineQueueManager` — no other code should write to
  it.
- Replaced the original `isSyncing: Bool` + `pendingUploadCount: Int` properties
  with a `SyncPhase` enum:
  - `.idle` — no activity
  - `.uploading(count: Int)` — media files are being PUT to R2 staging
  - `.inferencing` — the Gemini Edge function is running
  - `.finalizing` — writing `LocalScanRecord` and cleaning up queue entries
- The `.finalizing` phase may represent a live/background dual-path race for the
  same stable scan ID. Local persistence is serialized by
  `ScanFinalizationCoordinator`, which is acquired by
  `processAndCleanupOfflineScan`, `saveLiveScanRecord`, and
  `saveNonVisualRecord` before writing `LocalScanRecord.id`. Do not bypass this
  coordinator from new scan-finalization entry points.
- Backward-compatible computed shims (`isSyncing`, `pendingUploadCount`) are
  preserved for existing consumers.
- **Write API** — all normal lifecycle methods require the operation UUID:
  - `beginSync(itemCount:generation:)` registers or replaces the upload batch;
    `beginInferencing(generation:)` idempotently registers an inference;
    `beginFinalizing(generation:)` advances only that inference token.
  - `completeSync(generation:)` removes only the matching inference token. Use
    from inference result/failure teardown.
  - `completeUploadPhase(generation:)` removes only the matching upload batch.
    Use from generation-checked `finishUploadSync`.
  - `forceIdle()` invalidates the current upload and all inference tokens. Late
    completions become no-ops and cannot decrement work started after
    connectivity restores.
- Internally, one `UploadActivity` and an `[UUID: InferenceActivity]` map
  replace the former force-resettable integer count. Phase priority is
  finalizing, inferencing, uploading, then idle.

### `ScanRepository`

- `@MainActor` singleton facade over `OfflineQueueManager` and SwiftData,
  decoupling UI and ViewModels from `ModelContext` and queue internals.
- Injected at startup via `configure(with:)`, which also seeds the "Favorites"
  collection if absent and imports the legacy `needsCollectionSync` pending bit
  into a coalesced `OfflineJobRecord`. After that bridge, the job record is the
  scheduler authority.
- **`configure(with:)` — non-blocking launch**: The Favorites collection seed is
  deferred to `Task { @MainActor in }` so `configure` returns immediately
  without performing any SQLite I/O on the synchronous launch path. On large
  libraries, the original synchronous `FetchDescriptor<ScanCollection>()`
  blocked the main thread before the first frame rendered. The deferred fetch
  also uses `fetchCount` with `#Predicate { $0.name == "Favorites" }` +
  `fetchLimit = 1` — O(1) regardless of collection count.
- **`syncHistoricalScansDown`**: Before fetching cloud collections, routes
  pending collection uploads through
  `OfflineQueueManager.drainCollectionSyncIfPossible()` so launch-time history
  restore shares the same collection single-flight latch as ordinary UI edits.
  This push-before-pull ordering prevents the reconciliation delete pass from
  wiping collections created offline or before authentication, while also
  preventing historical sync from bypassing the normal collection ordering
  guarantees. If collection mutations cannot be drained safely, reconciliation
  aborts rather than reading stale cloud state. After the push, fetches cloud
  scan and collection history with pagination
  (`MerianConfig.historicalSyncPageSize`,
  `MerianConfig.collectionsSyncPageSize`). Each raw PostgREST scan page is split
  into rows and decoded with the SDK's production decoder; malformed rows are
  quarantined with a bounded coding path while valid neighbors reconcile
  immediately through one reused `HistoricalDatabaseActor`. Pagination advances
  by the raw remote row count, never the surviving decoded count, so quarantine
  cannot repeat or skip a page. Collections remain accumulated until every scan
  page has reconciled, then pass once to `syncCollectionsDown`. The scan
  projection includes the existing nullable `is_biological_subject` field:
  inserts use the cloud value when present and retain the legacy `true` default
  only for older null rows, while updates apply only a non-null remote value.
  Classification is never inferred from stored reasoning. **Never reorder the
  push and pull** — reversing them causes unsynced local collections to be
  treated as obsolete and deleted on the next app launch.
- **`eradicateScan`**: Commits database changes (delete record, insert cloud
  deletion task) before touching disk. File deletion via
  `FileIOActor.shared.deleteImages(at:)` runs only after a successful
  `modelContext.save()`; save failures rollback pending context changes and
  abort disk deletion, preventing partial-failure inconsistency.
- **`ingestScans` timestamp guard**: During historical cloud sync, each scan's
  `timestamp` string is parsed via `DateUtilities.iso8601FractionalFormatter`
  (with whole-second fallback). If both formatters fail on a malformed
  timestamp, the scan record is **skipped with a logged error** rather than
  defaulting to `Date()` (which would fabricate a current timestamp and make the
  scan appear as "Today", corrupting sort order). Caller sees a
  `MerianLog.data.error("ingestScans: unparseable timestamp ...")` in the logs
  for affected scan IDs.

### `ScansManager` and `ScansLibrarySearchCoordinator`

- `ScansManager` owns observable filter input, selection/action feedback, and
  the reviewed app-event subscription. It delegates every mutable search task,
  generation, posting/filter snapshot, lookup map, and sorted-ID cache to the
  contained `ScansLibrarySearchCoordinator`.
- The coordinator offloads search index rebuilds from the main `.onChange()`
  thread to avoid stalls on large scan lists.
- Uses an O(1) delta update pattern: computes `oldIds.subtracting(newIds)` and
  `newIds.subtracting(oldIds)` via Swift Set operations, updating only the
  affected entries rather than rebuilding the full index on every change.
- **Dynamic Hot-Swapping**: To prevent stale caches when users mutate inner
  properties of existing scans (e.g., adding `customTags`), `ScansManager`
  listens for `AppEvent.scanSearchIndexInvalidated(scanId:)` and asks the
  coordinator to perform a targeted isolated re-evaluation via
  `SearchDatabaseActor`. The scan row—not the event payload—remains
  authoritative.
- **Dual-path indexing**: Full rebuilds cooperatively extract `RawScanSnapshot`
  values from the already-resident `allScans` array on `@MainActor` in
  128-record chunks with `Task.yield()` between chunks, then construct both
  `SearchableScan` payloads and `SearchIndexSnapshot` posting lists inside one
  cancellation-aware detached task. Incremental inserts stay on
  `SearchDatabaseActor`, but fetch their delta through one batch
  `FetchDescriptor` (`WHERE id IN (...)`) rather than faulting records
  one-by-one; the main actor then upserts only the changed documents into the
  existing snapshot.
- **O(1) lookup caches**: `ScansLibrarySearchCoordinator` keeps `[String: Int]`
  index positions, a `[String: LocalScanRecord]` live-reference fallback map,
  `[String: ScanSortPrimitive]` sort snapshots, and a `sortedAllScanIDsCache`
  keyed by `ScanSortOption.rawValue`. The record map is rebuilt from the
  existing `@Query` array only; it must not trigger a second SwiftData fetch or
  copy model data. `record(for:)` resolves through the index first and falls
  back to the map if an index is stale during a snapshot transition.
- **Generation-guarded commits**: The coordinator's private generation
  increments whenever `allScans` changes. Full-rebuild snapshot extraction and
  incremental actor fetches both verify that generation before committing, so a
  cancelled or stale indexing task cannot overwrite a newer library snapshot.
- **`searchString` composition**: Each scan's search index string is a robust
  concatenation of
  `commonName + scientificName + petLabel + ecologyType + semanticTags + taxonomyClass + taxonomyOrder + taxonomyFamily + commonGroupName + aiReasoning + locationName + habitatDescription + weatherCondition + lifeStage + reproductiveCondition + sex + sexEvidence + similarSpecies.joined() + iucnRedListStatus + hazardType + ecologicalInteractions`.
  The `commonGroupName` is derived by
  `SearchDatabaseActor.commonGroupName(for:)`, which maps Latin class names to
  plain-English synonyms (e.g. `"aves"` → `"bird birds avian"`). Combined with
  the AI's natural language reasoning and specific telemetry (weather, ecosystem
  variables, and locations), casual semantic queries like "small bird", "rainy
  day", "juvenile", or textual habitat traits effortlessly filter the index
  without strict taxonomy matches.
- **Indexed query path**: `SearchIndexSnapshot` maintains four bounded in-memory
  indexes: exact word terms plus unigram, bigram, and trigram posting lists.
  Query tokens are normalized through `SearchIndexTokenizer`, then
  `SearchFilterActor` intersects posting lists to narrow candidates before
  performing the final `searchString.contains(...)` verification. This keeps
  substring semantics intact (`"yard"` still matches `"backyard"`, and
  one-character queries no longer fall back to the full library) without
  scanning the entire library for every keystroke.
- **Generation-scoped advanced-filter index**: `ScanLibraryFilterIndexSnapshot`
  stores one immutable, pre-normalized `ScanLibraryFilterDocument` per scan plus
  cached filter-sheet dimensions and category counts. Main-actor extraction
  yields every 128 records; normalization and aggregate construction run on a
  detached utility task. A filter change builds one `ScanLibraryFilterQuery`,
  normalizing selected values and date bounds once, then performs matching and
  sorting together off-main. Never add a computed filter option that scans
  `allScans` or a predicate that reads `LocalScanRecord` inside the query loop.
- **Targeted invalidation**: custom-tag notifications and Explore share-state
  events advance the cache generation, coalesce every pending scan ID into the
  replacement search task, rebuild the immutable filter snapshot, and rerun the
  active query. Coalescing is required: cancelling task A before carrying A's ID
  into task B can silently remove A from the index.
- **Debug completion hook**: In `DEBUG`, `ScansManager` proxies the contained
  coordinator's internal `SearchDebugEvent` callbacks for `indexingCompleted`,
  `filterIndexingCompleted`, and `searchCompleted`. The test suite uses these
  events to await real background completion instead of sleeping for guessed
  debounce/indexing windows, which makes search regressions deterministic
  without changing the production control flow.
- **Category bucketing**: Category filters (`Plants`, `Fungi`, `Birds`, etc.)
  are precomputed into `SearchCategoryBucket` posting lists inside the snapshot,
  so category-only searches never re-evaluate taxonomy on every document.
- **`semanticTags` composition**: Assembled at write time in
  `BackgroundDatabaseActor` and `ScanRepository` as
  `[commonName, scientificName, optional pet label] + colors + groupTags`.
  `groupTags` are the 1–5 broad-to-specific categorical labels (e.g.
  `["animal", "bird", "songbird"]`) sourced from `species_dictionary.group_tags`
  — generated once per species by a background Gemini Flash call and returned in
  the `/identify` response on cache hit. `group_tags` is a `TEXT[]` column on
  `species_dictionary`, not `scans`.
- **Detached Primitive Sort Engine**: The coordinator maps pure `@Model` objects
  into `ScanSortPrimitive` arrays and delegates ordering to the value-only
  `ScanLibrarySortPolicy` inside `Task.detached`. The "no query / all
  categories" path caches sorted ID arrays per sort option, so repeated sort
  changes and query clears do not rebuild the same full-library sort every time.
- **Injected actions**: `ScansLibraryDependencies` is the only Library owner
  that resolves media export, Explore publication, local publication-state
  writes, app events, error formatting, or haptics. Deterministic tests replace
  every closure without constructing a network client or UI presenter.

### `ProfileDatabaseActor` (Profile Stats)

- `@ModelActor` in
  `apps/ios/Merian/Features/Profile/UserProfile/Services/ProfileDatabaseActor.swift`.
- Owns the off-main projection pipeline used by `ProfileTabViewModel`: species
  count, streak, 52-week heatmap, and award payloads. The
  `ProfileTabDependencies` live adapter creates the ad-hoc Profile render actor;
  the view never creates it directly.
- **Shared stats projection**: `calculateProfileStats()`, `calculateAll()`,
  `calculateHeatmapData()`, and `calculateAwardsProjection()` all load the same
  cached `ProfileStatsProjection` instead of issuing separate SwiftData fetches.
  The projection is built from `propertiesToFetch` scalar columns and contains
  only `Sendable` values (`ProfileAnalyticsProjection`, timestamps, and a
  precomputed unique-species count).
- **Cache fingerprint**: The actor validates cached projections with
  `recordCount`, latest scan ID, and latest timestamp before reuse.
  Inserts/deletes naturally invalidate the cache without reloading full rows
  just to check freshness. Callers that edit existing scan fields in place must
  invalidate before requesting cached profile stats. The post-inference
  `calculateAwards()` entry point does this itself because concurrent queued
  scans can mutate records without changing the fingerprint.
- **Achievement detail projection**: The richer detail projection is lazy and
  separate from the stats projection because it includes thumbnail paths and
  `capturedMediaJSON`-derived presentation fields. Do not merge it into the
  default profile stats path; that would pull media-adjacent columns into every
  Profile render.

### `ArchiveManager`

- Dataset archive download coordinator for generated export ZIP files.
- Polls available disk space via `getAvailableDiskSpace()` for diagnostics and
  support. Biological scan evidence is no longer rescued on a timer because
  cloud media is durable regardless of subscription tier.
- `downloadArchive(id:url:)` streams the generated ZIP to the local Documents
  directory and reuses an existing file for the same archive id.

### `MerianConfig`

- Centralized enum (`Core/Utilities/MerianConfig.swift`) holding all policy
  constants for the data and AI layers.
- A policy change requires exactly one edit, with no risk of values diverging
  across files.
- Referenced by `OfflineQueueManager`, `ScanRepository`
  (`HistoricalDatabaseActor`), `CaptureWorkspaceViewModel`, and
  `InferenceEngine`.

| Constant                              | Value  | Consumer                                               |
| ------------------------------------- | ------ | ------------------------------------------------------ |
| `uploadBatchSize`                     | 5      | `OfflineQueueManager+Sync`                             |
| `pendingScanFetchLimit`               | 50     | `OfflineQueueManager+Sync`                             |
| `mediaStagingMaxFilesPerRequest`      | 6      | `MediaStagingContract`                                 |
| `mediaStagingMaxImageFilesPerRequest` | 5      | `MediaStagingContract`                                 |
| `stagedImagePayloadMaxBytes`          | 5 MB   | `MediaStagingContract`, Edge image fetch contract      |
| `audioPayloadMaxBytes`                | 2.7 MB | `MediaStagingContract`, `MerianNetworkClient`          |
| `historicalSyncPageSize`              | 200    | `ScanRepository`                                       |
| `collectionsSyncPageSize`             | 100    | `ScanRepository`                                       |
| `ingestCheckpointInterval`            | 50     | `HistoricalDatabaseActor`                              |
| `imageCompressionQuality`             | 0.85   | `Capture`, `CaptureWorkspaceViewModel`                 |
| `visionConfidenceThreshold`           | 0.65   | `VisionSubjectClassificationResolver`                  |
| `visionMarginThreshold`               | 0.15   | `VisionSubjectClassificationResolver`                  |
| `scanningPhaseRotationIntervalNs`     | 2.3 s  | `ContinuousScanningPhraseSleeper`, `QueuedContentView` |

### `UserDefaultsKeys`

- Centralized enum (`Core/Utilities/UserDefaultsKeys.swift`) holding all
  persisted key strings.
- Prevents silent key mismatches between storage sites. UI-facing state should
  normally flow through `AppSettings`, not local `@AppStorage` wrappers.
- **Do not inline string literals for these keys anywhere in the codebase.**
  Always reference the constant.

| Constant                               | Key string                                | Sites                                                                                                                                                                                                                                                                                                                 |
| -------------------------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hasUnseenScan`                        | `"hasUnseenScan"`                         | `AppSettings` typed property. Read by `MainTabBar`; written by live/background inference completion; cleared by `InsightSheetView`, `CameraSheetRouter`, and `ScansShellViewModel` from Scans-sheet lifecycle triggers.                                                                                               |
| `hasCompletedOnboarding`               | `"hasCompletedOnboarding"`                | Legacy routing preference only. `MerianApp` combines it with current required consent and the manager's pending restoration signal to choose onboarding, a launch-matched restoration surface, or the workspace. Active provider/hardware lifecycle behavior still requires current adult, Terms, and Gemini consent. |
| `pendingManualAppleRevocationNotice`   | `"pendingManualAppleRevocationNotice.v1"` | `SupabaseManager` persists the legacy Apple fallback before sign-out; `MerianApp` restores the manual-removal alert on launch/foreground until explicit resolution. The Settings sheet only explains the two revocation paths. This key must survive account-local database cleanup.                                  |
| `themeMode`                            | `"themeMode"`                             | `MerianApp`, theme bootstrap                                                                                                                                                                                                                                                                                          |
| `opensExploreOnLaunch`                 | `"opensExploreOnLaunch"`                  | Default-off `AppSettings` preference sampled once by `MerianApp`; after onboarding and current required consent, an ordinary cold launch may initialize the Capture workspace with Explore presented. Registered during settings initialization and reloaded by `AppSettings.reloadFromDefaults()`.                   |
| `isPushNotificationsEnabled`           | `"isPushNotificationsEnabled"`            | `AppSettings` typed property. Notification settings, inference completion, and offline failure/completion paths read/write through settings except low-level authorization mirrors.                                                                                                                                   |
| `isMultiCaptureEnabled`                | `"isMultiCaptureEnabled"`                 | `CaptureWorkspaceViewModel`, `CaptureWorkspaceViewModel+DescribeSubmission`, onboarding migration                                                                                                                                                                                                                     |
| `showsCaptureGoalProgress`             | `"showsCaptureGoalProgress"`              | `AppSettings` typed property. The **Field trip goals** setting controls whether `CaptureWorkspaceView` presents the active outing target capsule and may forward its camera-only selected-goal hint; default `true`. Server progress remains enabled with deterministic fallback when off.                            |
| `legacyMultiImageScanMode`             | `"multiImageScanMode"`                    | one-time migration in `MerianApp`                                                                                                                                                                                                                                                                                     |
| `hasPromptedForNotificationsPostIdent` | `"hasPromptedForNotificationsPostIdent"`  | `AppSettings` typed property. `CameraSheetRouter` uses it to present the post-identification notification prompt only once.                                                                                                                                                                                           |
| `hasSeenExploreOnboarding`             | `"hasSeenExploreOnboarding"`              | `AppSettings` typed property. `InsightSheetViewModel` uses it for the one-time Explore sharing prompt.                                                                                                                                                                                                                |
| `hasUnseenExplorePost`                 | `"hasUnseenExplorePost"`                  | `AppSettings` typed property. Set after local share, cleared when the Recent Explore feed is loaded, and read by `MainTabBar`.                                                                                                                                                                                        |
| `lastSeenExplorePostSharedAt`          | `"lastSeenExplorePostSharedAt"`           | `AppSettings` typed property. Updated by `ExploreFeedViewModel` after the Recent feed loads and used by `MainTabBar` badge refresh.                                                                                                                                                                                   |
| `suppressInferenceBanners`             | `"suppressInferenceBanners"`              | `AppSettings` typed property for mutation; `PushNotificationManager.willPresent` performs a direct synchronous key read because the delegate method is nonisolated.                                                                                                                                                   |
| `lastBackgroundedDate`                 | `"lastBackgroundedDate"`                  | `AppLifecycleManager`                                                                                                                                                                                                                                                                                                 |
| `lastHistoricalSyncDate`               | `"lastHistoricalSyncDate"`                | `AppLifecycleManager`, `SupabaseManager`                                                                                                                                                                                                                                                                              |
| `enrichedSpeciesTimestamps`            | `"enrichedSpeciesTimestamps"`             | `InferenceEngine`                                                                                                                                                                                                                                                                                                     |
| `isLiveInferencePaused`                | `"isLiveInferencePaused"`                 | `CameraSettingsView`, `CameraManager`                                                                                                                                                                                                                                                                                 |
| `invertZoomDirection`                  | `"invertZoomDirection"`                   | `ZoomSliderView`, `CameraPreviewView` (pan gesture), `CameraSettingsView`                                                                                                                                                                                                                                             |
| `zoomSideLeft`                         | `"zoomSideLeft"`                          | `ZoomSliderView`, `MainOverlayView`, `CameraSettingsView`                                                                                                                                                                                                                                                             |
| `zoomSliderVisible`                    | `"zoomSliderVisible"`                     | `ZoomSliderView`, `CameraSettingsView`                                                                                                                                                                                                                                                                                |
| `needsCollectionSync`                  | `"needsCollectionSync"`                   | Legacy one-release bridge only. `ScanRepository.configure(with:)` imports it into `OfflineJobRecord(id: "collection-sync")`; active scheduling should use the job record.                                                                                                                                             |
| `hiddenSmartCollectionIDs`             | `"hiddenSmartCollectionIDs"`              | `SmartCollectionPreferences` stores locally hidden smart collection ids; these are UI-only and are not synced through `/sync-collections`.                                                                                                                                                                            |
| `speciesPreferredNamePrefix`           | `"speciesPreferredName_"`                 | `SpeciesPreferredNameStore` bridge for per-species display-name overrides used by Insights and Explore.                                                                                                                                                                                                               |

`KeychainKeys.hasAuthenticatedOAuth` is the single source of truth for the
authenticated-session marker used by `SupabaseManager`, `MerianNetworkClient`,
and `KeychainManager` migration logic. Do not inline
`"Merian_HasAuthenticatedOAuth"`.

`KeychainKeys.legacyGhostModeUserID` names the retired same-UUID presentation
marker only so upgraded clients can delete it. Account presentation no longer
consults that Keychain entry.

### `FieldNotesRepository`

- `@MainActor` local/private field-note boundary living in
  `Core/Utilities/FieldNotesRepository.swift`.
- Resolves notes in durability order: `LocalScanRecord.fieldNotes`,
  `OfflineQueuedScan.fieldNotes`, then the legacy `FieldNotesStore` bridge.
  Successful SwiftData reads mirror the bridge; bridge-only reads are promoted
  back into SwiftData.
- SwiftData writes save explicitly and call `modelContext.rollback()` on
  failure. The legacy bridge is mirrored only after a SwiftData commit succeeds,
  preventing `UserDefaults` from claiming a note that the local database
  rejected.
- Owns Explore-to-local repair through
  `promoteExternalFieldNotesIfLocalMissing(...)`. Public Explore notes are
  accepted only when every local/private store is empty, so publishing or hiding
  Explore notes cannot erase private scan-library notes.
- Feature effect boundaries in Insights and Explore should call this repository
  instead of directly mutating `LocalScanRecord.fieldNotes` or
  `FieldNotesStore`. Insight Field Notes confines those calls to
  `FieldNotes/Services/InsightFieldNotesDependencies.swift`; its views and view
  models consume injected closures. Repository reconciliation tests live under
  `MerianTests/Core/Utilities/FieldNotesRepositoryTests.swift`.

### `SpeciesPreferredNameRepository`

- `@MainActor` SwiftData-backed repository living beside the typed preference
  stores in `Core/Utilities/UserDefaultsKeys.swift`.
- Uses `UserSpeciesPreference` as the source of truth for Insight load/set/clear
  operations.
- `MerianApp` calls `migrateLegacyPreferences(modelContext:)` immediately after
  the `ModelContainer` is available. The migration scans legacy
  `speciesPreferredName_*` keys, preserves any existing SwiftData value over
  stale legacy data, promotes missing rows, saves once, and removes legacy keys
  only after the save succeeds.
- Falls back to the legacy `SpeciesPreferredNameStore` key-value bridge on read
  only as a safety net, promoting that legacy value into SwiftData and clearing
  the key after save.
- Syncs with Supabase `user_species_preferences` on auth restore, foreground
  activation, and after local set/clear edits. Sync is single-flight on the
  main-actor repository boundary, so repeated lifecycle/auth/edit triggers
  coalesce behind the active task instead of issuing overlapping PostgREST reads
  and upserts; if a trigger arrives while a sync is already running, the
  repository records a trailing follow-up request so edits saved after the
  active task's local fetch are flushed before the coalesced task completes.
  Clean lifecycle/auth syncs also use a 60-second freshness gate after a
  successful sync so cold launch does not perform an auth-restore sync followed
  immediately by an identical foreground sync. Local edits bypass that freshness
  gate, and local clears are queued in `pendingSpeciesPreferredNameDeletes`
  until a remote `deleted_at` tombstone upsert succeeds.
- Treat normalized equality as convergence before comparing timestamps. A
  matching active name never upserts merely to copy a timestamp, and an existing
  remote tombstone satisfies a pending local delete. Only a real value/tombstone
  conflict uses last-write-wins: remote-newer pulls, while local-newer or equal
  pushes. This prevents devices from echoing an already-matching value.
- Persists lightweight support diagnostics in `UserDefaults`: last attempt time,
  last success time, current status (`running`, `success`, `failure`, or
  `skipped`), failure/skip message, and last successful pushed/pulled row
  counts. These values are diagnostic-only; SwiftData remains the source of
  truth for the preferences themselves.
- Exposes a bounded display-map helper for Explore feed/map hydration.
  `ExploreFeedViewModel` owns the observable preferred-name cache and resolves
  feed cards, map previews, comments, detail titles, and share text from that
  cache; `ExplorePost` and `ExploreMapPost` remain pure network DTOs.
- Dog/cat pet labels bypass this repository. They are scan-level
  `PetIdentification` metadata, not user-selected species common-name
  preferences, and must never be written to `UserSpeciesPreference`.
- Successful SwiftData writes clear stale legacy keys instead of mirroring back
  to `UserDefaults`, so SwiftData is the only live source of truth.
- This is intentionally not part of `AppSettings`: preferred common names are
  per-species data with local SwiftData durability and eventual cloud backing,
  not global UI preference state.

### `AppSettings`

- `@MainActor @Observable` service living alongside `UserDefaultsKeys` in
  `Core/Utilities`.
- Owns the typed, in-memory representation of high-churn persisted settings such
  as `themeMode`, `isMultiCaptureEnabled`, `requiresScanConfirmation`,
  `showsCaptureGoalProgress`, `gridColumns`, `saveToCameraRoll`, and
  notification toggles.
- Writes through to `UserDefaults` on mutation, reloads from
  `UserDefaults.didChangeNotification`, and exposes `refreshFromDefaults()` for
  foreground reconciliation after background delegates or extensions mutate
  persisted values while SwiftUI is suspended.
- Injected through `AppDIContainer` and SwiftUI environment. Settings-first
  views should bind `@Environment(AppSettings.self)` and use the typed
  properties directly instead of declaring local `@AppStorage` wrappers.
- Rule: `UserDefaultsKeys` remains the storage registry; `AppSettings` is the
  preferred UI-facing boundary for global UI/preferences state.
- `CaptureWorkspaceViewModel` and its modality extensions read capture
  preferences through `diContainer.appSettings`, not `AppSettings.shared`, so
  preview/test containers can isolate multi-capture and confirmation behavior
  without mutating global defaults.
- Core hardware/data managers that need settings (`HardwareOrchestrator`,
  `HapticManager`, `PhotoLibraryManager`) also accept `AppSettings` injection
  while preserving `.shared` defaults for production wiring.
- Transient app-wide UI flags (`hasUnseenScan`, Explore unread/chip/onboarding
  state, post-identification notification prompt state,
  `suppressInferenceBanners`) now live on `AppSettings` too. Direct
  `UserDefaults` access is reserved for keyed per-entity stores
  (`FieldNotesStore`, `ExploreShareStateStore`, `SpeciesPreferredNameStore`),
  migrations, throttle timestamps, and synchronous system delegates that cannot
  hop to `@MainActor`.
- `OfflineQueueManager` owns an injectable `hardwareOrchestrator` reference for
  the expedition-mode upload gate. Tests that exercise sync gating should
  replace that reference temporarily instead of mutating
  `HardwareOrchestrator.shared`.

## Media & Image Processing

### `ExternalImageImportStore`

- Actor-owned Application Support inbox for one-photo iOS document imports.
- Validates local URLs as `UTType.image`, scopes access only for the source-copy
  window, records an atomic manifest, and exposes FIFO pending receipts across
  cold launch and onboarding.
- The inbox is not SwiftData and does not use the Messages/widget App Group.
  `CaptureWorkspaceViewModel` retains receipts through quota or staging-capacity
  blocks and acknowledges them only after staging or terminal decode failure.
- `ImportedImageMetadataExtractor` reads embedded capture date and a complete
  signed GPS pair before image preparation. Missing or partial metadata remains
  missing; it is never synthesized.

### `MediaPreparationActor`

- Actor-owned Zero-OOM boundary for file-backed still-image preparation.
- Gallery, Photos document imports, and refinement staging call
  `prepareStillImage(fileURL:isPro:)`, receiving only bounded inference bytes,
  bounded display bytes, a sendable preview `CGImage`, and
  `MediaPreparationMetrics`.
- Avatar crop previews call `preparePreviewImage(fileURL:maxSize:)` before any
  `UIImage` is constructed on `@MainActor`.
- Enforces Merian's image contract in code: non-empty encoded payloads, longest
  edge caps from `MerianConfig`, and the 5 MB staged image byte ceiling.

### `LocalImageLoader`

- A Zero-OOM actor governing remote image fetches, APFS extraction, and
  thundering-herd cache coalescing.
- Prevents redundant remote fetches using tracked `Task` closures off the
  `@MainActor`.
- **Async Decode Bounds**: A cancellation-aware four-permit pool suspends excess
  callers without blocking threads. Admitted synchronous ImageIO work runs on an
  explicitly QoS-tagged concurrent queue, preventing both decode
  over-subscription JetSam panics and priority-inversion hang warnings.
- **Isolated media session**: `mediaSession` uses
  `httpMaximumConnectionsPerHost = 4`, `httpShouldSetCookies = false`,
  `requestCachePolicy = .useProtocolCachePolicy`, and a dedicated `URLCache`
  bounded to 24 MB in memory and 256 MB on disk. This keeps immutable, versioned
  thumbnail responses out of the shared cache while allowing reuse across view
  reconstruction and app launches; connection fan-out remains aligned with
  decode capacity.
- Supports fallback fetching: loops natively through comma-separated URLs via
  Zero-OOM `ImageDownsampler` bounds.
- I/O helpers (`loadLocal`, `fetchRemote`) are `static nonisolated` — prevents
  `Task.detached` from re-entering the actor executor mid-operation and keeps
  network orchestration off the actor executor; synchronous decode work is
  isolated on the dedicated decode queue.

### `SimilarSpeciesImageFetcher`

- `@MainActor @Observable` generation-fenced state owner for Wikipedia/GBIF
  fallback imagery and a resolved fallback name.
- Receives `SimilarSpeciesImageDependencies`; it owns no network session or
  image-loader singleton.
- `SimilarSpeciesImageService` concurrently resolves permitted external URL
  metadata, restores candidate order after concurrent downloads, and delegates
  bitmap work to `LocalImageLoader` rather than inflating raw `UIImage(data:)`
  blobs.

## Networking

### `MerianNetworkClient`

- Routes all Deno function endpoints via `MerianEnvironment.supabaseUrl`; if
  Supabase config is incomplete, endpoint construction throws
  `MerianError.invalidURL` and no fallback network request is attempted.
- Centralizes JWT validation in `performAuthenticatedRequest`, which handles
  authentication for all five public endpoints.
- Prewarms `/identify-multimodal` with `OPTIONS` through the same TLS-pinned
  `URLSession` used by the real request; the Supabase auth SDK's connection pool
  is not treated as an inference connection prewarm.
- `performAuthenticatedRequest` accepts an optional request-body completion
  callback. A per-task `URLSessionTaskDelegate` fires it from upload progress;
  receiving a response is the fallback for transports/test protocols without
  progress events, and transport errors fire it immediately. Inference requests
  also attach the aggregate `X-Merian-Constrained-Network` diagnostic tag and
  log `Server-Timing` plus the Edge region.
- Calls `getValidAuthHeaders()` with `try` (not `try?`) so authentication errors
  propagate to callers rather than being silently dropped. Previously, using
  `try?` made network failures impossible to diagnose.
- Extracts `DeviceIdentityManager.shared.deviceId` without depending on
  arbitrary session state.
- Traps `.401 Unauthorized` responses in `performAuthenticatedRequest` by
  delegating to `SupabaseManager.shared.getValidAuthHeaders()`, which handles
  Ghost session refresh.
- `restoreExploreMediaObjectKeys` now uploads via
  `URLSession.upload(for:fromFile:)` with bounded concurrency, and MIME type
  detection prefers file extension plus a small header read instead of inflating
  full image or video files into RAM.
- Single `checkScanStatusDetails` calls may attach `OwnedScanRecoveryPayload`
  for eligible older/interrupted missing owner rows; bulk probes never do.
  Record-based Explore sharing polls status, defers to active/retryable
  ingestion, stages available local image/video/audio, and retries one combined
  `recovery_scan` plus media-restoration request. Ask the Community repairs
  through status before its image restore. The server independently validates
  and gates every repair.
- Live multimodal audio reads preflight total byte size before any
  `Data(contentsOf:)` or base64 allocation, then use `.mappedIfSafe`. Queued
  audio does not use inline base64: `MediaStagingContract` validates and uploads
  it to R2, then replay sends only `audioR2ObjectKeys`.
- `/identify` and `/identify-multimodal` body assembly share a private inference
  payload builder. User/device context, EXIF-derived month/time formatting,
  telemetry key casing, observation context parsing, and inline media budget
  validation now live behind one path instead of being duplicated across
  foreground and background request builders.
- **`endpointURL(_:) throws -> URL`**: All Edge function URL construction goes
  through this private helper. It throws `MerianError.invalidURL` if
  `supabaseUrl` is misconfigured, rather than crashing the process with a
  force-unwrap (`URL(string: "...")!`).
- **Dedicated Supabase `URLSession`**: A private `lazy var session` handles all
  Supabase Edge and R2 calls. Configuration: `timeoutIntervalForRequest = 30`,
  `timeoutIntervalForResource = 90` (hard cap — Gemini cannot bypass this
  regardless of the per-request timeout), `httpMaximumConnectionsPerHost = 6`,
  `httpShouldSetCookies = false`, `urlCache = nil`. TLS pinning via
  `MerianTLSDelegate` is applied to `*.supabase.co` only. **Media and external
  API calls use their own isolated sessions** (never `URLSession.shared`):
  `LocalImageLoader`, `ArchiveManager`, and
  `InsightMediaExportManager`/`ExportProcessingActor` each declare a
  `private static let mediaSession` (30 s / 300 s timeouts);
  `SimilarSpeciesImageService`, `InferenceEngine`, and `GBIFHeatmapTileService`
  declare isolated external sessions (10 s / 30 s timeouts) for Wikipedia/GBIF
  best-effort enrichment fetches. Their SwiftUI consumers own no `URLSession`.
- **TLS certificate pinning (`MerianTLSDelegate`)**: A private
  `URLSessionDelegate` validates the server certificate chain for
  `*.supabase.co`. The check walks the full chain (leaf → intermediate → root):
  a connection is accepted if **any** certificate in the chain matches a pinned
  hash. This means the intermediate CA hash acts as a genuine fallback across
  leaf rotations, not just a backup placeholder. `pinnedCertHashes` contains two
  active hashes: the leaf cert (`OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=`)
  and the intermediate CA (`HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=`).
  Other hosts (e.g. R2) fall through to default ATS validation. Pinning is
  skipped in `DEBUG` builds. **Rotation runbook**: before the leaf expires,
  compute the new hash with
  `openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64`,
  add it to the set alongside the current one, ship the update. Remove the stale
  hash after the old cert has expired everywhere. The intermediate CA hash only
  needs updating if Supabase migrates CAs.

### Edge Network Operations (Cloudflare R2 & PostgreSQL Bulk Insertions)

- **Centralized Cloudflare R2 Operations (`_shared/aws.ts`)**: `copyR2Object()`
  and `deleteR2Object()` are defined once and shared across `moderation`,
  `export-dwca`, and `revenuecat-webhook`, rather than duplicating
  `aws.sign(...)` headers in each. The filename and `aws4fetch` type name refer
  to AWS Signature V4 for R2’s S3-compatible API; they do not indicate an Amazon
  AWS storage or compute dependency.
- **Shared Diagnostic Prompts (`_shared/diagnostic.ts`)**: The AI prompting
  logic for `fetchDiagnosticComparison` is extracted into a shared utility,
  preventing 1:1 duplication between the `identify` and `enrich-scan` Edge
  functions.
- **N+1 Query Prevention (`sync-collections`)**: Collection rows are batch
  upserted, existing memberships for all owned collection IDs share one
  composite-keyset read, and membership additions/removals are emitted in
  bounded set-based chunks. The endpoint never issues one membership read or
  insert per record.
- **Explore request guards**: Explore write endpoints now share
  `_shared/http.ts.parseJsonBody(...)` for object-body validation and
  `_shared/explore.ts.assertCanInteractWithExplorePost(...)` for the identical
  "post still shareable + no mutual block" gate used by comment and like flows.
  `syncPublicAuthorIdentity(...)` remains the single author-sync path for public
  writes. Explore reads consume the current projection and must not refresh
  identity or repair ownership as a side effect.

### `SupabaseManager`

- Wraps GoTrue bindings and exports a unified
  `getValidAuthHeaders() async throws -> [String: String]` method that
  consolidates OAuth conditional checks (`Merian_HasAuthenticatedOAuth`) and
  Ghost Session regeneration (via `.identifierForVendor`).
- Initializes with the typed `MerianEnvironment` configuration. Invalid or
  missing Supabase config is logged and represented by a fallback client only to
  keep app boot non-crashing; actual app network requests are still blocked by
  `MerianNetworkClient.endpointURL(_:)` until config is valid.
- A Debug simulator pointed at the production Supabase host reports
  `.productionSupabaseInDebugSimulator` as a startup fault, but remains valid
  and connected. This protects routine testing by making production use
  conspicuous without preventing an intentional smoke test. The Xcode Run
  environment variable `MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1`
  suppresses only that warning; it does not redirect or sandbox requests.
- **`authListenerTask` handle**:
  `@ObservationIgnored private var authListenerTask: Task<Void, Never>?` — the
  auth state listener task is stored rather than fire-and-forget, consistent
  with the task handle pattern used across the engine layer. This allows the
  task to be cancelled on deinit and prevents duplicate listener registration.
- **Cold-start session adoption**: `AuthSessionAdoption` distinguishes no
  session, a valid session, and an expired cached session awaiting SDK refresh.
  The awaiting-refresh path leaves `isAuthenticated` false and `currentUser`
  unset, but passes the cached user ID to `ConsentManager` so required-consent
  restoration cannot briefly resolve to Ready. The subsequent `tokenRefreshed`
  or `signedOut` event completes the decision.
- **Purchase-principal resolver**: each usable Auth session outside a pending
  protocol-3 stable sign-out passes through one single-flight
  `resolveAndLinkPurchasePrincipal` operation. A pending fresh-anonymous
  destination uses the exact reservation claim described below and never enters
  this ordinary path. A 256-bit `WhenUnlockedThisDeviceOnly` installation
  capability is generated and read-verified before first use; Edge stores only
  SHA-256 and returns explicit `legacy` or `stable` mode. The client never
  selects or persists a RevenueCat App User ID as authority. A device-only
  binding-intent counter advances and read-verifies before network I/O; the
  server rejects older intents, while Auth-event generation checks before and
  after the serialized SDK identity mutation prevent a late result from an old
  session from installing paid readiness for a new one.
- **Unified Auth-transition ownership**: one `AuthTransitionCoordinator` owns
  Apple, Google, Sign out, recovery, Apple credential revocation, and account
  deletion. Its token records kind, phase, source, expected destination, and
  Auth generation. Competing operations cannot begin; stale provider callbacks
  and wrong Apple controllers are ignored. Account-bound metadata, purchase,
  entitlement, and routing writes verify token ownership plus the live session
  after suspension. The Auth listener observes basic SDK state but cannot run
  identity side effects ahead of the active owner.
- **Stable versus legacy identity**: stable mode passes the immutable
  server-issued purchase-principal ID and binding generation to
  `RevenueCatManager`. It clears and synchronizes legacy account attributes,
  then writes no account email, username, display name, avatar, account kind, or
  Auth UUID subscriber attribute because that customer can survive an account
  switch. Legacy mode keeps the uppercase Auth UUID and historical attribute
  path for old-client compatibility. A definite missing additive route may fall
  back to legacy; auth, timeout, configuration, provider, and database failures
  remain fail-closed. RevenueCat is never configured with an anonymous SDK ID
  and sign-out never calls SDK logout.
- **`ghostSessionTask` single-flight**:
  `@ObservationIgnored private var ghostSessionTask: Task<User?, Never>?` —
  serializes anonymous session creation across all callers and returns the
  resolved Supabase user to each waiter. This closes the suspension-window race
  where multiple `getValidAuthHeaders()` calls could each enter
  `initializeGhostSession()` and perform overlapping `signInAnonymously()`
  requests.
- **Sign-out identity single-flights**: protocol-3 stable mode creates a random
  rotation UUID and 256-bit secret, persists/read-verifies a `preparing`
  Keychain journal, and prepares a server-owned reservation while the exact
  linked source and binding generation are still live through
  `prepare_signout_rotation`. It persists and verifies the returned `prepared`
  receipt and expiry before local sign-out. One newly created anonymous session
  then invokes `claim_signout_rotation` for that exact reservation; it never
  enters ordinary purchase-principal resolution. The claim atomically returns
  the same principal/provider ID with an advanced binding generation. iOS
  validates that receipt, serially relinks RevenueCat, requires
  `EntitlementManager.beginSession(...)` to return `true`, rechecks the same
  Auth generation, and removes the journal last. The exact restored source may
  invoke `cancel_signout_rotation` with the same proof; every unrelated
  permanent session, old anonymous session, expired claim, malformed journal, or
  unreadable Keychain stays fail-closed and cannot invoke the generic resolver
  or provider link. The journal pins the exact installation-capability
  fingerprint and disables capability creation while pending. It makes no
  receipt-sync or provider-transfer call. Legacy mode retains
  `signOutPurchaseHandoffTask`: bind → uppercase UUID RevenueCat link →
  `syncPurchases()` → authoritative server verification and reconciliation →
  entitlement refresh → same-session verification → verified proof removal.
  Either pending boundary keeps purchase/restore/redeem disabled.
- **Unauthorized identity preservation**: a generic route `401` is not proof
  that Auth deleted the user and never rotates the current UUID. A Ghost can be
  replaced only when the response carries the stable missing/invalid-session
  contract and an SDK refresh fails. This prevents repeated endpoint failures
  from manufacturing Supabase and RevenueCat customers.
- **DRY OAuth Abstraction**: Apple Sign In and Google Sign In share a single
  `private func finalizeOAuthLogin` path, removing the duplicate
  `.linkIdentityWithIdToken` / `.signInWithIdToken` logic that previously
  existed in both flows. The existing-account fallback is entered only for
  Supabase Auth code `identity_already_exists`; network, timeout, configuration,
  and other linking errors preserve the active guest session.
- **Apple revocation credential**: Apple completion also requires the one-use
  authorization code. After Supabase installs the session,
  `register-apple-revocation-token` receives the code, identity token, and one
  stable registration UUID with a bounded response-loss retry. Server-side Apple
  verification and Vault persistence are part of sign-in success; failure clears
  the new local session. The manager treats Apple's credential-revoked
  notification as a revalidation signal. It snapshots the active Apple
  identity's provider-specific `UserIdentity.id`, calls
  `getCredentialState(forUserID:)`, and applies the asynchronous result only if
  that same Apple identity remains active. `.authorized` preserves the session;
  `.revoked`, `.notFound`, `.transferred`, unknown states, and lookup failures
  clear the matching local session. This client transition never fabricates
  server provider completion.
- **Durable Ghost merge completion**: Before switching sessions,
  `SupabaseManager` stores each source-issued, provider-bound proof in a
  versioned `WhenUnlockedThisDeviceOnly` Keychain queue. Completion is
  single-flight per active task generation, so an older cancelled task cannot
  clear a newer handle after sign-out/re-login. Successful and terminal
  invalid/expired entries are removed individually; transient,
  wrong-destination, and Auth-cleanup failures remain queued for session-restore
  retries. HTTP 503 `merge_temporarily_unavailable`, including a server-side
  scan-ledger invariant failure, always remains queued; only the public terminal
  404/410 handoff codes authorize removal.
- **`keyWindowAnchor()` helper**: A private
  `keyWindowAnchor() -> ASPresentationAnchor` method was extracted to remove the
  identical implementation that was previously copy-pasted into two separate
  `presentationAnchor` methods.
- **Deduplicated anonymous sign-in**: The two identical anonymous sign-in code
  paths were collapsed into a single `isSessionMissing` check, removing the
  duplicate `signInAnonymously()` block.
- Maps Apple and Google OAuth hooks to migrate anonymous accounts, then resolves
  the current session's stable or legacy purchase identity before paid
  readiness.
- The database Ghost merge's destination reconciliation row repairs Merian's
  provider lookup schedule only. After commit, the server separately reads both
  RevenueCat customers, mirrors/verifies the source's active finite or lifetime
  Pro horizon, and blocks source Auth deletion on any failure. The durable
  client calls `syncPurchases()` before local evidence rebind and proof removal.
  Ghosts may purchase, restore, redeem, and receive reviewed beta grants.
  - User-facing **Sign out** calls `transitionToGhostSession()` while presenting
    only **Sign out**, **Continue with Apple**, and **Continue with Google**.
    Stable mode rotates Supabase Auth under the same purchase principal and
    keeps StoreKit access there; beta/promotion/support grants remain attached
    to their account owner. Legacy mode uses `/transfer-signout-purchases` and
    receipt sync until the supported-client rollback window closes. Account
    deletion owns its own transition and atomically verifies distinct recovery
    and acknowledgement capabilities in one device-only Keychain envelope. It
    records `capability_preparation_pending`, completes non-destructive server
    prepare, records `capability_prepared_pending`, and only then records
    `capability_intake_pending` before destructive commit. A lost response
    therefore replays only the same server-idempotent commit or uses the
    account-free public recovery route while all other account work stays
    fenced. `not_committed` retires only the proof/marker; a successful receipt
    advances through cleanup and capability retirement; iOS signs out without
    replacement or purchase transfer, purges SwiftData, acknowledges, verifies
    proof removal, and removes the marker last. Foreground and cold launch
    present a blocking recovery surface and retry the exact interrupted phase.
    Only the server's explicit `409 purchase_continuity_pending` may move an
    unaccepted intake into the durable `capability_rejection_retirement_pending`
    phase. That phase verifies removal of only the unused proof before removing
    the marker and never signs out or purges local data; unknown or ambiguous
    recovery never does. Global sign-out remains inappropriate because it would
    revoke other active devices.
  - `AppLifecycleManager` retries an unresolved purchase-identity binding on
    foreground activation, including while the required-consent gate is closed.
    The retry is bound to the exact current Auth generation and durable Keychain
    capability/handoff; it cannot rotate Auth or create a replacement RevenueCat
    customer. Paid readiness reopens only after server entitlement verification.

### `DetachedWork`

- Small shared executor-escape helper defined alongside app-wide DI primitives.
- Sanctioned use cases: background SDK bootstrap, sendable image preparation,
  bounded file cleanup, and narrow background database bridges.
- `DetachedWork.fireAndForget(...)` replaces ad hoc `Task.detached` in
  high-level app flows so the exceptional escape from structured concurrency
  remains explicit and lintable.
- `DetachedWork.value(...)` retains the detached task handle, forwards parent
  cancellation to it, and checks cancellation before and after accepting its
  result. Detached operations still check cancellation between expensive native
  stages and retain cleanup ownership for any output that can arrive late.
- Rule: if a detached boundary is still needed, route it through `DetachedWork`;
  otherwise prefer structured `Task {}` or actor-owned APIs.

### `KeychainManager`

- **`baseQuery(for:)` helper**: A private
  `baseQuery(for key: String) -> [String: Any]` method builds the base
  `[kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]` dictionary. This
  was previously duplicated verbatim in all three methods (`set`, `bool`,
  `removeObject`).
- Supports `Bool`, `String`, and `Data` values. Callers may select
  `AfterFirstUnlockThisDeviceOnly` (the default) or the stricter
  `WhenUnlockedThisDeviceOnly` accessibility used by bearer merge proofs.
- Durable state machines use throwing reads and verified removal so
  `errSecItemNotFound` remains distinguishable from Security.framework failure.
  An unreadable handoff queue is retained and keeps analytics fail-closed.
- **`migrateFromUserDefaults()`**: The `init` migration logic was extracted into
  a named method for clarity.

## Events & Circuit Breaking

### `AppEventPublisher` and `AppRouteCoordinator`

- `AppDIContainer` owns one instance of each service. Preview containers receive
  isolated instances; neither type exposes a second static singleton.
- `AppEventPublisher` is a synchronous `@MainActor` bus for loss-tolerant
  invalidations and lifecycle commands. Its `PassthroughSubject` is private and
  exposed through one `AnyPublisher` constructed during initialization; repeated
  subscriber access does not allocate another type-erasure wrapper.
  Reference-type consumers own their `AnyCancellable` and capture themselves
  weakly; SwiftUI `.onReceive` is owned by the mounted view. Every consumer
  reloads authoritative state from SwiftData, UserDefaults, Supabase, or the
  owning service.
- `AppRouteCoordinator` is a bounded `@MainActor @Observable` state machine for
  navigation. It prioritizes and coalesces typed `AppRoute` envelopes, preserves
  FIFO ordering for equal timestamps, fences account/session changes, and keeps
  a presentation route in flight until the exact root sheet dismisses. Pending
  duplicates retain stable request identity but adopt the latest lightweight
  payload; an applied presentation cannot be rewritten by a duplicate callback.
- `CaptureWorkspaceViewModel` is the sole root consumer. `CameraSheetRouter`
  presents Paywall, Insight, Scans, Profile, Explore, achievement detail, and
  notification prompt through one `.sheet(item:)` host. Occupied presentations
  defer and resume through `onDismiss`, not an assumed animation delay. Capture
  crop/video/description/question/survey presentations report the same UIKit
  slot as occupied and resume deferred routes from their own exact callbacks.
- Candidate and confidence review, Insight Chat follow-ups, and Explore activity
  navigation use small typed pending-action values at their feature owner. They
  dismiss the source and execute from its exact `onDismiss` after revalidating
  scan/presentation identity; elapsed animation delays are not a routing
  primitive.
- Explore post detail, Insight content and shell, Profile, achievement detail,
  candidate cards, and Species Dictionary detail each serialize sibling local
  destinations through one typed presentation value. Sheet and cover bindings
  filter that value, and async commits require current identity, no
  cancellation, and an available slot.
- `SupabaseManager` distinguishes the SDK's explicit `initialSession` restore
  from runtime sign-in. Only the former may adopt a cold-launch private route;
  runtime account transitions advance the account generation and reject it.
- `NotificationCenter` remains only at reviewed Apple-framework boundaries. The
  production allowlist and CI guard reject application-defined notification
  names/posts, bus singleton access, duplicate AppEvent subjects, and route-like
  AppEvent cases. Framework publishers with unknown originating executors use
  `sinkOnMainActor`; lifecycle-owned SwiftUI `.onReceive` subscriptions apply
  explicit main-queue delivery before mutating view state.
- Raw `.sink` is separately fail-closed to five exact lifetime owners. Those
  subscriptions store or return their cancellable, avoid strong owner cycles,
  and preserve the bus/framework actor contract. Any new owner requires a
  capture, cancellation, ordering, and actor-isolation review; the exact matrix
  is canonical rather than duplicated here.
- The complete event/route matrices, delivery guarantees, source priorities,
  expiry policy, and presentation contract are in
  [Event and Presentation Routing](../system-architecture/10-event-and-presentation-routing.md).

### `CircuitBreakerManager`

- Lives at `Core/Security/CircuitBreakerManager.swift`.
  `@MainActor @Observable final class` with a `static let shared` singleton
  registered in `AppDIContainer`.
- Exposes `isCircuitTripped: Bool` — when `true`, outbound inference requests
  should be skipped to avoid hammering a failing edge endpoint.
- **Trip logic**: `recordFailure()` increments a consecutive-failure counter.
  After 3 consecutive failures (`failureThreshold`), `tripCircuit()` sets
  `isCircuitTripped = true` and starts a 15-minute cooldown `Timer`. On cooldown
  expiry, `resetCircuit()` clears the trip and the counter.
- **Reset logic**: `recordSuccess()` zeroes the counter and resets the circuit
  if it was tripped, allowing the next request to proceed normally.
- **Usage**: Callers in `InferenceEngine` and `OfflineQueueManager` should call
  `recordFailure()` on unrecoverable network errors and `recordSuccess()` on a
  successful inference response. Gate new inference attempts behind
  `!circuitBreakerManager.isCircuitTripped`.

## Telemetry & Billing

### `RevenueCatManager`

- Owns RevenueCat customer identity, paid access, paid-offline behavior,
  offerings, purchase, and restore. `isSubscribed` is paid status; `isProActive`
  combines paid status with current-launch server-verified functional access;
  and `canStartProScan` additionally requires capacity to fund a new analysis.
- Treats exact RevenueCat identity linkage and permission to mutate provider
  state as separate conditions. Stable readiness requires one exact provider App
  User ID, active Auth UUID, and server binding generation. SDK identity
  mutations run serially, and the newest request always runs last; stale
  anonymous-to-authenticated results cannot reopen purchase admission.
- Handles RevenueCat `CustomerInfo` refreshes, evaluates standard Pro
  entitlements, and treats `pro_week` as a detached non-subscription purchase
  that is active for seven days from its purchase date.
- Opens local paid state only when RevenueCat entitlement verification is
  `verified` or `verifiedOnDevice`; an unverified snapshot fails closed. The
  active binding must also authorize the RevenueCat store behind each active
  product. Stable mode rejects promotional, missing, and unknown store
  provenance for `pro_annual`, entitlement rows, and the detached seven-day pass
  even when `activeSubscriptions` contains the product identifier. Account-owned
  promotions enter only through the approved account-grant or legacy
  compatibility lane. The SDK log handler drops provider message bodies and
  emits only fixed severity categories, never customer/account IDs or raw
  errors.
- A store introductory trial activates through its receipt without a manual
  RevenueCat approval. A beta promotion is different: it is an explicit, finite
  secret-key grant of the same `pro` entitlement. Once either is projected to
  Supabase, it resolves as `pro_paid` and includes Field Chat for the active
  period. RevenueCat project-level Pro billing grants neither state.
- Connects anonymous and authenticated sessions to the resolved purchase
  identity; the `revenuecat-webhook` Edge function remains the server-side
  purchase authority. It verifies signed delivery, fetches authoritative
  CustomerInfo, persists recurring/grace expiry, and writes snapshot-primary
  tier/timed-pass state through the service-only transaction. The durable
  `reconcile-revenuecat-subscribers` sweep repairs missed deliveries; the iOS
  manager is never the database entitlement authority.
- `RevenueCatOfferingPolicy` defines the paywall's required App Store product
  identifiers: `pro_week` and `pro_annual`. `fetchOfferings()` logs an error
  when there is no current offering, no available packages, or either required
  product is absent. These diagnostics do not create products or repair package
  mapping; App Store Connect product readiness and RevenueCat dashboard mapping
  remain release prerequisites.
- Stable App User IDs are immutable server-owned purchase-principal identifiers;
  uppercase Supabase UUIDs remain the legacy compatibility IDs. Customer counts
  need not match `public.users`, and historical provider rows are never deleted
  for normalization. StoreKit state follows the active principal binding, while
  beta/promotion/support access comes from a private account-owned grant ledger.
  The stable rollout remains disabled by default and held for disposable replay,
  provider sandbox, minimum-client, PII-scrub, monitoring, exact-SHA review, and
  explicit production authorization. See the
  [RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md).

### `EntitlementManager`

- Lives at `Core/Security/EntitlementManager.swift`. Owns the authenticated
  current-launch result of private `get_my_entitlement()`; no complimentary-only
  mode unlocks offline from a prior launch.
- Exposes `currentPlan`, `currentTier`, paid status, total scans remaining,
  unheld scans available to start, in-flight holds, and the monotonic
  entitlement version.
- Buffers the newest valid scan-response snapshot until the launch RPC
  establishes a baseline. It then accepts only same-user snapshots whose version
  is at least current, preventing a stored replay from restoring stale capacity.
- An active hold grants functional Pro access for recovery and capped non-scan
  actions but cannot fund another analysis. Paid RevenueCat offline access is
  unchanged.
- Serializes idempotent `ScanFundingReservation` values on `@MainActor` by
  account and scan. `locallyAvailableComplimentaryCredits` subtracts unresolved
  local and conservative legacy blockers from verified server availability.
- Owns deferred ordering and blocker state. A terminal consumed state is not
  removed until a later successful entitlement refresh; released/absent terminal
  state also requires refresh, while current paid proof safely promotes deferred
  work to paid Pro.
- Releases proven local pre-dispatch failures only after the durable job marker
  is saved. HTTP 402 invalidates current complimentary proof. Successful scan
  metadata is reconciled from `plan_used` plus `credit_consumed`.
- Full contract documented in
  [18-complimentary-pro-scans.md](../backend-and-data/18-complimentary-pro-scans.md).

### `ScanAdmissionManager`

- Lives at `Core/Security/ScanAdmissionManager.swift`. Before online Capture
  starts camera/audio hardware or submits staged evidence, it calls the
  authenticated `get_my_scan_admission_preview(...)` RPC for the active Supabase
  account.
- Validates the exact decision/plan/daily-count shape and never caches a
  response. An exhausted daily allowance or unavailable Pro path opens the
  existing paywall before inference or queue mutation. An unavailable online
  preview blocks the attempt with retry feedback; offline work falls back to
  `UsageManager`.
- The preview never reserves quota. The Edge route's later
  `reserve_ai_quota(...)` call remains authoritative, so Capture retains the
  exact `429 ai_quota_daily_exceeded` paywall fallback for a concurrent race.

### `UsageManager`

- Lives at `Core/Analytics/UsageManager.swift`. Maintains the advisory daily
  free-tier capture/paywall meter; Supabase owns provider authorization.
- `canPerformScan(isProActive:) -> Bool` — returns
  `isProActive || freeScansRemaining > 0`. Capture controls use
  `RevenueCatManager.canStartProScan` for presentation, while actual queue
  admission uses `EntitlementManager.claimFunding` before reserving Flash.
- `consumeScan(scanId:)` — called once at enqueue time inside
  `OfflineQueueManager.insertAndPersistRecord` / `enqueueNonVisualCapture`, only
  for an immediate/deferred Flash funding claim and before the
  `OfflineQueuedScan` record is committed. `syncPendingScans` has no second
  local check.
- `refundScan(scanId:)` — idempotently restores an optimistic local token when
  queue persistence/local pre-dispatch work fails or when durable
  reclassification proves paid/complimentary Pro. It does not refund a charged
  provider reservation or settle a complimentary hold.
- Grants 1 free daily scan via `UserDefaults` keyed against
  `DeviceIdentityManager.shared.deviceId`. Resets limits at calendar day
  boundaries via `evaluateDailyRefresh()`, called from
  `AppDIContainer.handleActivePhase()` on foreground transitions.
- **Debug override**: `FeatureFlag.unlimitedFreeScans.defaultValue` is `false`.
  DEBUG Settings/environment overrides bypass only this local meter;
  Release/TestFlight ignores them and all builds remain subject to server quota.
- The authoritative database uses a UTC-day bucket and stable request UUID.
  Local refunds do not refund a provider attempt. `reconcileServerPlanUsed`
  consumes the meter for `free` and refunds it for paid/complimentary plans by
  scan ID.
- Full contract documented in
  [02-revenue-and-identity.md](../features-and-hardware/02-revenue-and-identity.md#usage-limits-usagemanager).

### `SocialGuardManager`

- Lives at `Core/Security/SocialGuardManager.swift`. Manages a persistent local
  `Set<String>` of blocked user UUIDs (`blockedUserIds`).
- Updates UI blocking state across Discovery feeds optimistically (immediately
  on the local set), then asynchronously flushes the UUID to the `/block-user`
  Edge node via `MerianNetworkClient`.
- Automatically reverts the block if the Edge API returns an error, restoring
  the previous set state.
- Full contract documented in
  [02-revenue-and-identity.md](../features-and-hardware/02-revenue-and-identity.md#trust--safety-socialguardmanager).

### `GamificationManager`

- Lives at `Core/Analytics/GamificationManager.swift`. `@MainActor @Observable`
  singleton that persists lightweight gamification state in `UserDefaults`.
- `unlockedSpeciesCount` — incremented each time `recordNewSpeciesDiscovered()`
  is called (by `InferenceEngine` when `isNewDiscovery == true`).
- `hasFireflyBadge` — unlocked when `unlockedSpeciesCount >= 5`; persists the
  discovery milestone and triggers a selection haptic when first unlocked.
- `unlockedAchievements: Set<String>` — type keys of all completed awards,
  persisted across sessions.
- `evaluateAchievementsForNotifications(awards:)` — called after
  `ProfileDatabaseActor.calculateAwards()` completes after every inference. That
  entry point refreshes its projection before evaluating in-place inference
  writes. The manager checks for newly completed awards, persists
  `unlockedAchievements`, returns toast-eligible awards, and queues native local
  push notifications via `PushNotificationManager` when the achievement
  notification setting allows it. It never imports or invokes the in-app visual
  presenter; `ScanMilestoneCoordinator` batches the returned typed awards after
  Field trip progress. Cat and dog achievements use a July 4, 2026 notification
  cutoff so historical qualifying scans are seeded silently instead of showing
  retroactive unlock banners.
- **The Field Naturalist** is the server-authoritative exception to the local
  scan calculator. `ScanMilestoneCoordinator` merges the typed earliest standard
  outing or Seasonal Challenge result, saves it in an account-scoped
  `UserDefaults` cache, and passes it to `GamificationManager` only when the
  current server mutation reports a new unlock. There is no rollout cutoff
  because Field trips had no prior user engagement.
- Full architecture documented in
  [06-profile-and-gamification.md](../features-and-hardware/06-profile-and-gamification.md).

### `MilestoneToastPresenter`

- Lives at `Core/UI/Feedback/AchievementToastPresenter.swift` and is kept under
  the legacy filename for Xcode/project continuity. It is an
  `@MainActor
  @Observable` DI-owned FIFO in-app milestone queue.
  `AppDIContainer` constructs the one production presenter,
  `MilestoneToastHostRegistry`, injectable `MilestoneToastClock`, and
  `ScanMilestoneCoordinator`; previews/tests receive isolated graphs, and none
  of these types exposes a production `.shared`. The container also injects its
  producer-only `AppEventSending` capability into the scan coordinator; the
  coordinator never reaches through `AppDIContainer.shared` to publish progress
  invalidations.
- Supports `.achievement(AwardPayload)` for achievement unlocks and
  `.dictionary(.newToMerian)` for species-dictionary contribution milestones,
  plus `.fieldTrip(FieldTripMilestonePayload)` for standard outing and Seasonal
  Challenge progress.
- `ScanMilestoneCoordinator` is the production scan-completion boundary shared
  by foreground `InferenceEngine` and background `OfflineQueueManager` paths. It
  deduplicates by a trimmed, lowercase coordination key while preserving the
  caller's transport/store ID, awaits the existing persistence/progress attempt,
  gathers achievements without presenting them immediately, evaluates
  `SpeciesData.isNewToMerianDictionary`, and synchronously enqueues standard
  Field trips, Seasonal Challenges, achievements, then **New to Naturebook**.
  Identification corrections reapply progress through the same coordinator but
  do not replay the original scan-achievement/dictionary batch. When Field trips
  are disabled, the coordinator skips its progress resolver while ordinary scan
  achievements and dictionary milestones continue normally. `.fieldTrips` is
  currently enabled in the central `FeatureFlags` registry; availability
  injection remains as a test seam and future emergency client-build control.
  Retryable failures keep the selected-goal SwiftData row as a durable outbox,
  release ordinary milestones through a separate once-per-scan guard, and use
  the 2/5/15-second per-scan budget plus a global cap of 16 sleeping in-process
  retries. Oldest overflow releases process-local captures;
  `OfflineJobScheduler` replays leftover hints after relaunch; only success,
  terminal ingestion failure, or disabled Field trips acknowledges and removes
  the hint.
- The presenter controls only in-app banner presentation. It does not mutate
  Field trip progress, achievement progress, dictionary state, analytics, or
  native notification authorization. DEBUG Settings preview entry points enqueue
  representative achievement, dictionary, and Field trip payloads through the
  same queue while bypassing persistence and OS notifications.
- The process-local queue retains at most 32 lightweight items. Overflow drops
  only ephemeral feedback after durable progress has already committed.
  Duplicate typed payloads coalesce onto the first stable item ID and enqueue
  calls report explicit accepted/coalesced/overflow/stale-session outcomes.
  Rendering is capped at one active payload subtree plus two decorative
  backplates. Outer overlay visibility, active-item identity, and clamped
  backing-depth changes each have one distinct animation owner; the full queued
  UUID array is never used as an animation key.
- The foreground-host registry retains at most eight UUIDs, gives the latest
  mounted feedback surface exclusive presentation ownership, and restores the
  prior host on unmount. The presenter—not a remounted banner—owns presentation
  start time plus the one-time haptic and VoiceOver claim, so host changes
  preserve the remaining 3.5-second lifetime and cannot repeat effects. Only the
  front banner accepts hit testing.
- The feedback modifier obtains `AppRouteCoordinator` from the SwiftUI
  environment for achievement and Field-trip taps. It must not route through
  `AppDIContainer.shared`; preview and test containers own isolated route queues
  as well as isolated milestone presenters.
- `SupabaseManager` binds `ScanMilestoneCoordinator` as the account-session
  controller. Runtime sign-in/sign-out/account replacement advances its account
  generation; a five-minute foreground timeout advances its session generation.
  The coordinator forwards the transition to the presenter, cancels retained
  retry tasks and preferred-goal retry state, scopes in-flight ownership by
  account/session generation, and checks the captured token after every resolver
  suspension. Account replacement clears recent-scan history; a same-account
  timeout retains completed/released deduplication. Late callbacks cannot block
  current work, schedule a new retry, or enqueue visual items for another
  session.
- Do not add another global milestone presenter or let this visual queue become
  domain authority.
- Completed Field Naturalist cards and unlock toasts carry a typed
  `CaptureGoalDestination` and open the outing or Seasonal Challenge that earned
  the award. Its locked card continues to open the requirement sheet.

### `ToastPayload` and `MerianSystemFeedbackModifier`

- `ToastPayload` lives at `Core/UI/Feedback/ToastPayload.swift`. It is a small
  value containing a unique presentation ID, title, optional body,
  `ToastSeverity`, and optional typed `ToastActionDescriptor`. It never stores
  images, models, scan arrays, or executable closures.
- Feature view models bind `ToastPayload?` into `MerianSystemFeedbackModifier`.
  The modifier owns one identity-keyed, cancellable three-second task and clears
  a separately view-owned action closure with the matching payload. Replacing a
  payload cancels the prior task, so an old timer cannot remove a newer message.
- Passive banners render no controls, and passive banners plus visual backing
  layers disable hit testing. An action toast receives input only when its typed
  descriptor and view-owned handler are both present, and only inside the
  compact banner; an incomplete pairing remains pass-through. Feedback
  animations are scoped to the overlay rather than the host screen. Ordinary
  feedback waits while the milestone stack owns the same alignment, preventing
  Z-index overlap; different top/bottom alignments remain independently visible
  and interactive.
- Message text is display copy, not an event or action protocol. Never infer
  severity, navigation, or retry behavior from substrings; add a typed case or
  descriptor instead.

### `ConsentManager` required-consent restoration

- `ensureCloudConsentForInference()` is the new-account and returning-account
  provider gate. It resolves the current Supabase account, pushes pending
  adult/Terms/Gemini evidence, performs a fresh remote fetch, and opens its
  process-local cloud-ready marker only when that fetched state contains the
  same account's current adult and Terms rows plus a current granted all-version
  Gemini stream head. Persisted `syncedUserId` fields are never sufficient by
  themselves.
- `requireCurrentConsentReapprovalAfterServerRejection()` converts an exact
  server `403 ai_consent_required` into durable account state. It closes the
  process-local gate before persistence, stores the affected user ID, resets the
  three required derived booleans, invalidates synchronization work, and routes
  a completed user through restoration to Ready. The marker is per-account,
  survives relaunch, decodes absent from a legacy ledger as empty, and rebinds
  during a confirmed ghost-account merge.
- Reapproval cannot replay cached evidence. It creates new adult, Terms, and
  Gemini rows, and the Gemini grant uses the authoritative provider head fetched
  after rejection as its causal parent. A fresh authoritative merge must then
  succeed before inference. The queue retains the original scan/media and does
  not automatically redispatch the policy-rejected request.
- Root presentation distinguishes unknown account evidence from authoritative
  absence with `.awaitingInitialSession`, `.reconciling`, `.waitingToRetry`,
  `.retryRequired`, and `.resolved`.
- A cached session whose access token is expired enters `.reconciling` under its
  known user ID while Supabase refreshes it; token expiry alone never resolves
  restoration as unauthenticated.
- Once an authenticated account enters restoration because local required
  evidence is missing, only `merge(_:for:generation:)`, after identity
  validation and a verified ledger write, may resolve it. A successful empty
  merge is authoritative absence; network, decoding, pending-row push, and
  persistence errors are not. An account that already has current local required
  evidence bypasses this restoration state.
- Failures receive three outer retries after 5, 10, and 20 seconds. The neutral
  root exposes **Try Again** during the wait and after exhaustion; manual retry
  resets the automatic budget.
- Every failure transition and timer verifies the synchronization generation,
  observed account, synchronous Supabase SDK account, and missing local required
  evidence. An account switch cancels stale work. Same-account invalidation
  returns a canceled retry to `.reconciling`, so the new generation starts from
  a coherent state.
- Duplicate same-account auth events preserve a pending retry and do not reopen
  a resolved restoration. A successful authoritative merge from foreground or
  Realtime synchronization may resolve while retry UI is visible.

### `PostHogManager`

- Not `@MainActor` — `PostHogSDK` is thread-safe, and the wrapper uses an
  `NSLock` around configuration and pending identity state.
- Required contract: `ConsentManager` is the sole configuration authority. It
  may configure and identify PostHog only after resolving a current-disclosure
  grant that is also the active account's all-version provider head; startup,
  absence, withdrawal, and account transitions must keep it off without starting
  a new request.
- `ConsentManager` models analytics cloud authority separately from cached
  ledger choice: local-only, awaiting the active account's remote state, or a
  resolved remote grant/revocation. Session restoration enters the awaiting
  state before cached values are refreshed. Only a successfully persisted,
  identity-fenced authoritative grant can reach `PostHogManager`; remote
  absence, revocation, fetch failure, and persistence failure stay closed.
- AI and analytics actions record the provider event observed at creation.
  `ConsentManager` sends them only through the authenticated causal append RPC,
  persists its returned accepted parent and server-issued revision, marks stale
  grant rejections as superseded local evidence, and fetches the all-version
  stream head before a new action can extend it. The RPC rebases revocations to
  the locked head so withdrawal wins a concurrent grant. Local and remote
  permission checks also evaluate that all-version head first: any head
  revocation closes the provider regardless of disclosure version, and only the
  exact head grant may be checked against current policy. A fetch-before-push
  reorder is not an acceptable substitute for that atomic database decision.
- Tracks `isConfigured: Bool` set at the end of `configure()`. `identifyUser()`
  buffers only a consented pending user ID if a call races setup.
- PostHog's dedicated session carries a configured-host-only `URLProtocol`
  transport gate. It is closed by default, gives each SDK setup a unique
  transport ID, opens that ID immediately before consented setup, and closes
  after app capture is disabled but before `reset → optOut → close`. A newer
  grant cannot reopen an old session's ID, so PostHog 3.69.0's reset-time
  feature-flag reload is rejected locally even during an immediate account
  switch. Permission generations also invalidate stale overlapping setup work.
  An injected `PostHogSDKClient` verifies gate state and SDK call order. This
  closes `CONSENT-001`. `ConsentManager` also generation-fences true-account
  replacement: analytics and the prior consent Realtime channel close before
  OAuth installs another session, and only reconciliation of the newest actual
  SDK session may reopen them. This closes `CONSENT-007` in source. See
  [Production Consent Readiness](../legal/production-consent-readiness-2026-08-03.md).

## 2026-04 Hardening Updates

- `InferenceEngine` now treats pending background writes as generation-scoped
  work. Any scan reset or cancellation invalidates the old generation before the
  next scan can enqueue or drain background mutations.
- Auth transitions close the engine's write-admission fence synchronously,
  cancel all presentation producers, retain their task handles, and await even
  cancellation-ignoring work before an Auth SDK session change. The fence opens
  only when the owning transition finishes.
- Active and pending best-effort metadata writes each have a hard depth-eight
  ceiling. Rapid queue replay therefore retains at most sixteen write closures;
  overflow is dropped instead of creating an unbounded OOM backlog.
- `AudioCaptureManager` owns full startup failure cleanup. Cancellation after
  `AVAudioSession` activation now still removes the input tap, stops the engine,
  cancels DSP work, finishes the spectrogram stream, and clears pending temp
  files. Startup/resume handles and one shared generation fence prevent a late
  activation, DSP update, or countdown tick from publishing after mode change,
  backgrounding, reset, or replacement.
- `AudioSessionCoordinator` publishes a new one-shot lease only after complete
  configuration and activation succeeds. Failed replacement restores the prior
  configuration; failed rollback deactivates and invalidates the partial
  session, and failed first activation deactivates partial state without
  publishing ownership. Duplicate teardown cannot deactivate the same lease
  twice.
- `SpeechManager` now routes every startup failure and cancellation path through
  `teardownAudioEngine()`, leaving no live tap, task, or stale `audioLevel`
  state behind, and uses the same leased `AudioSessionCoordinator` teardown
  model as `AudioCaptureManager`.
- `SupabaseManager` now deduplicates external telemetry linking per user session
  via `ensureTelemetryLinkedIfNeeded(for:)`, preventing cold-start and
  session-restore churn from re-triggering RevenueCat/PostHog link work
  repeatedly.
- `SupabaseManager` also deduplicates anonymous session creation itself via
  `ghostSessionTask`, preventing concurrent ghost-session re-entry while the
  first auth request is suspended.
