# Core Application Services & Managers

Merian uses a structured singleton pattern managed through
`AppDIContainer.swift`. These singletons own global application state without
triggering excessive SwiftUI view rebuilds.

## Hardware Domain

### `SpeechManager`

- `@MainActor @Observable final class` living at
  `apps/ios/Merian/Features/Capture/Describe/Managers/SpeechManager.swift`,
  registered in `AppDIContainer` and distributed to the view hierarchy via
  `DIContainerModifier`.
- Owns the full `AVAudioEngine` + `SFSpeechRecognizer` pipeline for live voice
  dictation on the Describe page.
- **`isRecording: Bool`** — the single source of truth for dictation state.
  `DescribeInputLifecycleObserver` mirrors it into
  `CaptureActionCoordinator.isDictationRequested`, which drives the capture-bar
  pulse. Never set to `true` until
  `audioEngine.start()` succeeds; reset to `false` in all failure and teardown
  paths.
- **`isStarting: Bool`** — prevents overlapping permission/session startup and
  lets the lifecycle observer tear down a dictation request that is still
  negotiating permissions or audio hardware.
- **`startDictation(onResult: @MainActor @escaping (String) -> Void) async throws`**:
  - Requests speech authorization, then retries recognizer availability five
    times at 200 ms intervals. If no recognizer becomes available, throws
    `DictationUnavailableError` instead of leaving the button in a starting
    state.
  - Requests microphone permission with
    `AVAudioApplication.requestRecordPermission()`. Throws `PermissionError` on
    denial; the lifecycle observer clears the requested-recording state so the
    control returns idle.
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
- **`stopDictation()`** — delegates entirely to `teardownAudioEngine()` then
  sets `isRecording = false`. Safe to call when the engine was never started.
- **`teardownAudioEngine()` (private)** — calls `audioEngine.stop()` and
  `audioEngine.inputNode.removeTap(onBus: 0)` **unconditionally** (both are
  no-ops if not running / no tap installed). This prevents an orphaned tap crash
  when `start()` throws after `installTap` has already been called. Ends and
  nils the recognition request and task, then releases the leased audio session
  through `AudioSessionCoordinator.shared.deactivate(ifCurrent:)`.
- **Auto-termination**: The `SFSpeechRecognitionTask` result handler dispatches
  back to `@MainActor` via `Task { @MainActor [weak self] in ... }`. When
  `error != nil || result.isFinal == true`, it calls `stopDictation()`
  internally — the user does not need to tap the mic again to stop a session
  that the system ended (e.g. 60-second silence timeout).
- **`PermissionError`** — a `LocalizedError` struct defined in the same file.
  Thrown on permission denial or an unusable zero-Hz input format. The lifecycle
  observer catches startup failures and clears the requested-recording flag so
  the control returns idle; no mode-specific error handling lives inside the
  paged Describe view.

### `AudioCaptureManager`

- `@MainActor @Observable final class` at
  `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift`, registered as
  `var audioCaptureManager = AudioCaptureManager()` in `AppDIContainer` and
  distributed via `DIContainerModifier`.
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
- **`snrLevel: SNRLevel`** — most recent SNR classification from
  `SpectrogramActor.snrLevel(from:)`.
- **`pendingPlaybackPath: String?`** — non-nil after recording finishes, before
  the user confirms or discards. Drives the review state UI.
- **`playbackProgress: Double`** — 0.0 → 1.0 playhead position; preserved across
  play/stop cycles so `playPendingRecording()` resumes from the scrubbed
  position.
- **`audioFilePath: String?`** — set to the WAV filename only when the user
  confirms via review UI; consumed and cleared by
  `CaptureWorkspaceView.onChange`, which either stages the clip into
  `stagedCapture.audios` for the shared mixed-media toolbar flow or routes it
  through `submitAudio` for the audio-only flow, then calls `reset()`.
- **`startRecording() async throws`**: guards with
  `!isRecording && !isStartingRecording` (the `isStartingRecording` flag is set
  before any `await` to prevent a second call from slipping through the guard
  during the async permission + engine-setup window — this was the source of the
  `nullptr == Tap()` AVAudioEngine crash). Session activation now flows through
  the shared `AudioSessionCoordinator`, which returns a lease token stored on
  `AudioCaptureManager`; teardown deactivates only if that lease is still
  current, eliminating stale stop-work from interrupting a newer record/playback
  cycle. Writes **Int16 PCM WAV** via an explicit
  `AVAudioFormat(commonFormat: .pcmFormatInt16, ...)` to avoid the
  WAVEFORMATEXTENSIBLE (`audioFormat = 0xFFFE`) variant that the edge audio
  parsers do not support. The tap now copies each `AVAudioPCMBuffer`
  synchronously into a bounded `AsyncStream(bufferingNewest: 2)` before handing
  it to `SpectrogramActor`, preventing tap-owned buffers from crossing the async
  boundary and capping DSP backlog.
- **Camera handoff contract** — `CaptureControlBar` owns one cancellable audio
  startup task and awaits `CameraManager.stopSessionAndWait()` before calling
  `startRecording()`. Leaving Audio cancels that task without a toast. This
  prevents rapid Camera → Audio → Record and Audio → Camera reversals from
  overlapping camera and audio hardware ownership. Cancellation is explicitly
  forwarded to the detached AVFoundation setup task, which checks it after
  session activation and before engine start so normal failure cleanup can
  release any partially acquired resources.
- **Transient input-route recovery** — after the recording audio session is
  active, a zero-rate or zero-channel input format is retried four times at
  75 ms intervals with `audioEngine.reset()`. A route that remains invalid
  after the bounded 300 ms window still throws
  `AudioCaptureError.hardwareSampleRateZero`.
- **`pauseRecording()`** — cancels countdown, calls `audioEngine.pause()`, sets
  `isPaused = true`.
- **`resumeRecording()`** — reacquires a fresh `AudioSessionCoordinator.Lease`,
  calls `audioEngine.start()`, and rebuilds the countdown from current
  `recordingProgress`.
- **`stopRecordingEarly()`** — cancels countdown, calls `finishRecording()` —
  same end state as timer completion.
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
  `CaptureWorkspaceView.onChange` handoff (stage-or-submit), or when
  `CaptureWorkspaceView` disappears.
- **Playback finalization**: `playbackCompletionTask` is now a stored handle,
  cancelled by `stopPlayback()` and `reset()`. This prevents an orphaned sleep
  task from retaining `AVAudioPlayer` and from clearing a newer playback session
  after the user has already stopped or restarted audio.
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
  s). Thresholds: `.clipping` (peak > 0.95), `.warning` (SNR < 10 dB),
  `.caution` (10–20 dB), `.clear` (≥ 20 dB).
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
- **Recorded Video Stabilization Boundary**: `AVCaptureMovieFileOutput` may be
  pre-attached during visual camera setup so the hold-to-record path feels
  immediate, but its video connection keeps stabilization off until
  `recordVideo(...)` is actually starting a clip. The start path requests
  AVFoundation `.auto` stabilization only when the connection reports support,
  logs the requested and active mode through `MerianLog.hardware`, and resets
  the connection to `.off` on finish, cancellation, or failure so still-photo
  captures do not inherit stabilization crop, latency, or resolution changes.

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
- On network failure, routes the payload to `OfflineQueueManager` and triggers
  the Graceful Degradation UI state.
- **First-result critical path**: visual analysis receives the original
  Analyze-tap timestamp, commits persisted media and parsed `speciesData`
  immediately, and measures the response-to-state boundary. A one-shot UIKit
  draw probe in `InsightSheetView` closes tap-to-first-render timing on the first
  actual result frame. `ScanMilestoneCoordinator` runs in follow-up work, polls
  `/check-scan-status` before retrieving the server-applied Field trip progress
  receipt, then calculates awards and batches standard outings, Events-visible Seasonal Challenges,
  achievements, and
  **New to Naturebook**. Tools requiring server persistence stay disabled until
  the existing ingestion ledger confirms the final scan ID. The progress call
  may carry the durable camera-only selected-goal hint, and its completion
  publishes a scan-specific contribution invalidation so an open historical
  Insight reloads without replaying milestone celebrations.
- **Inline/background upload handoff**: `analyze()` installs a two-second
  fail-safe, then asks `MerianNetworkClient` to release the live scan's deferred
  queue row when request-body upload completes. Network failure releases the row
  immediately. The callback is idempotent, so progress, response fallback,
  failure, and timer races cannot dispatch duplicate queue ownership.
  A separate foreground-inference claim lets recovery media stage without
  allowing staged replay to dispatch a duplicate primary identification.
- **Post-inference carousel handoff**: On a successful result, the saved user
  media is rebuilt into `ActiveScanMedia` _before_ `speciesData` is assigned.
  This ensures the insight sheet carousel always has the user's saved
  image/audio/description pages available on first render — the reference image
  is never the only visible page when the sheet opens. After `speciesData` is
  set, the transient live image frame is cleared.
- **Shared live-success finalization**: `analyze()` and `analyzeNonVisual()`
  share private finalization helpers for new-discovery marking, achievement
  notification refresh, reanalysis metadata transfer (`customTags`, collections,
  field notes), queued-scan flush/delete handoff, completion notification
  delivery, and reference URL normalization. The helpers stay inside
  `InferenceEngine` so they preserve `@MainActor` state ordering and the
  `AppDIContainer` singleton boundaries while removing duplicated success-path
  logic.
- **Non-biological correction reanalysis**: Correction from the Non-biological
  collection is a scoped refinement entry point, not a record mutation. The old
  non-biological record stays unchanged until a replacement result succeeds.
  This entry point bypasses only the Pro reanalysis feature gate; the submitted
  replacement still goes through normal free-tier inference settings and daily
  scan accounting.
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
- **`activeScanId` lifecycle**: `activeScanId` is set at `analyze()` start to
  the caller-supplied scan ID, and is cleared in the inference task's `defer`
  block alongside `isProcessing = false`. Clearing it on pipeline exit (success,
  failure, or cancellation) ensures the background offline path cannot hydrate a
  stale engine after the live pipeline has exited. For the success path this is
  a no-op (the background path skips when `speciesData.scanId != nil`). For the
  failure path it bounds the hydration window to the interval when
  `isProcessing == true`.
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
- `InferenceEdgeDTOs.swift` — contains `APIError`, `EdgeResponseWrapper`,
  `EdgeResponse`, and nested types (`Taxonomy`, `Insight`, `Diagnostic`). These
  were previously nested inside `InferenceEngine`.

### `OfflineQueueManager`

- Manages background `URLSession` uploads, queuing scan media to the local
  Documents Directory when the device is off-grid.
- **Durable live-scan suppression**: `enqueueCapture(...,
  startSyncImmediately: false)` persists eligible online live-camera still scans without immediately
  consuming the uplink twice. `syncPendingScans()` filters the process-local
  deferred-ID set until `releaseDeferredLiveUpload(scanId:)` is called by inline
  request progress, its two-second fail-safe, request failure, connectivity
  loss, or app backgrounding. Relaunch starts with an empty set, so durable rows
  are never stranded after termination; live success still cancels tasks and
  removes the queue row through the existing cleanup path.
  Gallery, audio-bearing, and video submissions continue using immediate
  background sync.
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
  user-attention state. Automatic scan upload, inference, cloud deletion, and
  collection-sync retries all share `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`;
  after that ceiling the job moves to `needsAttention` instead of rescheduling.
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
  for inference replay rather than displayed as separate audio pages. The
  queue/database layers derive legacy arrays (`localImagePaths`,
  `localVideoPaths`, `audioFilePaths`, `observationContextsJSON`) from that same
  timeline at the edges. For video, `thumbnailImagePaths` includes the poster
  for thumbnails and upload previews, while `activeScanMedia` emits the video
  page itself so Insight does not show a duplicate image before the clip.
  Cloud-backed scan refreshes prefer `scans.captured_media`; older rows with
  video URLs are normalized into playback video items so sampled inference
  frames do not appear as standalone carousel media.
- **Recursive Queue Draining**: The `URLSession` delegate calls
  `syncPendingScans()` recursively when a completed batch detects
  `unsyncedItemsCount > 0`, draining the queue automatically without user
  intervention.
- **Orphaned `.uploading` Reconciliation**: `markScansAsUploading` runs before
  `generateUploadURLs`, returns the scan IDs whose `.pending → .uploading`
  transition actually committed, and `syncPendingScans` signs/dispatches only
  those claimed files. If the claim save fails, the actor rolls back and no
  URLSession tasks are launched. If the URL-generation request fails after a
  successful claim (e.g. task cancelled when the user backgrounds), any scans
  already transitioned to `.uploading` are reset to `.pending`, then each
  affected scan records durable retry metadata through `OfflineQueueRetryPolicy`.
  When the shared automatic retry budget is exhausted, those rows move to
  `queueNeedsAttention` rather than scheduling another in-memory retry.
  Additionally,
  `replayInferenceForUploadedScans` cross-references live URLSession tasks on
  every call to catch orphans that bypass the catch block.
- **Server-Owned Inference Recovery**: Before replay resets an orphaned
  `.inferencing` scan, it polls `/check-scan-status` with the queued scan's
  required video count. `found` scans are synced down and the queue row is
  deleted, `processing` / `finalizing` / `retrying` server jobs keep the local
  row in `.inferencing` and schedule another poll, `failed_retryable` respects
  the server `retry_after` before retreating to `.staged`, and terminal failures
  mark the queue row as needing attention. The server job was claimed with the
  same media counts, staged object keys, upload-session ids, and manifest
  checksum that the queue submitted, and the paired `scan_ingestion_intents` row
  stores the sanitized replay request for staged media/audio/video and text-only
  scans. The scheduled `replay-scan-ingestion` worker may complete that
  authoritative server attempt before the app wakes again, so local replay waits
  on status polling instead of guessing from process-local retry state. This
  keeps video playback finalization from being mistaken for a local inference
  failure after app suspension or restart. Server-side replay is also capped at
  10 claims per sanitized intent; over-budget jobs are marked
  `failed_terminal` at `server_replay_limit_reached`.
- **`MerianConfig` Batch Limits**: `uploadBatchSize` (5),
  `pendingScanFetchLimit` (50), `mediaStagingMaxFilesPerRequest` (6),
  `mediaStagingMaxAudioFilesPerRequest` (2), `stagedImagePayloadMaxBytes` (5
  MB), and `audioPayloadMaxBytes` (2.7 MB) are governed by `MerianConfig`
  constants rather than inline literals.
- **`MediaStagingContract`**: Owns the canonical R2 staging manifest for queued
  images, audio, and video: sanitized filename, deterministic
  `staging/{userId}/...` key, media kind, content type, `sizeBytes`,
  `clientScanId`, `mediaRole`, upload task description, audio-file count, and
  byte-budget validation before `.pending → .uploading`. The same manifest is
  sent to `/generate-upload-urls`, whose Edge parser validates
  kind/type/size/role before signing and creates staged media-asset session rows
  for scan uploads. Swift and Deno tests both load
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
- **Quota Enforcement at Enqueue Time**: `insertAndPersistRecord` calls
  `UsageManager.shared.canPerformScan(isProActive: false)` before inserting a
  new `OfflineQueuedScan`. If the quota is exhausted the scan is rejected and
  any files written to disk are cleaned up atomically —
  `AppTelemetry.trackOfflineQueued()` is **not** fired on rejection. If the
  check passes, `UsageManager.shared.consumeScan()` reserves the token before
  the record enters SwiftData; if `modelContext.save()` fails, the queue
  rollback path calls `UsageManager.shared.refundScan()` before deleting staged
  files. `syncPendingScans` has no quota checks or `consumeScan` calls — every
  scan in the queue at upload time is already paid for and uploads
  unconditionally regardless of `freeScansRemaining`. Non-biological results
  count as successful scan attempts and are not refunded. A correction
  reanalysis for a non-biological result can bypass the Pro feature gate, but
  not daily free-scan accounting.
- **Sync Phase Transitions**: Drives `SyncStateManager` through
  `.uploading(count:)` → `.inferencing` → `.finalizing` → `.idle` as the
  pipeline progresses.
- **Diagnostics export**: `writeQueueDiagnosticsExport(eventLimit:)` writes
  support JSON containing job rows, redacted queued-scan metadata, and queue
  events only. It intentionally omits raw media paths, descriptions, GPS, and
  private media bytes.

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
- **Write API** — three completion methods with distinct semantics:
  - `beginSync(itemCount:)` / `beginInferencing()` / `beginFinalizing()` — phase
    transitions
  - `completeSync()` — inference pipeline completion; decrements
    `activeInferenceCount`, transitions to `.idle` only when count reaches zero.
    Use exclusively from `processInferenceDownloadResult`.
  - `completeUploadPhase()` — upload-path completion (empty queue, URL
    generation failure, etc.); transitions to `.idle` only if no inference is in
    flight, without touching the count. Use from all `syncPendingScans`
    early-exit paths and upload task settlement.
  - `forceIdle()` — hard reset; zeros `activeInferenceCount` and sets
    `phase = .idle` immediately. Use on connectivity loss where all in-flight
    tasks are cancelled.

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
  `MerianConfig.collectionsSyncPageSize`), then delegates all reconciliation to
  a single
  `HistoricalDatabaseActor.reconcileAllHistoricalData(responses:collections:)`
  call. **Never reorder the push and pull** — reversing them causes unsynced
  local collections to be treated as obsolete and deleted on the next app
  launch.
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

### `ScansManager` (Search Indexing)

- Offloads search index rebuilds from the main `.onChange()` thread to avoid
  stalls on large scan lists.
- Uses an O(1) delta update pattern: computes `oldIds.subtracting(newIds)` and
  `newIds.subtracting(oldIds)` via Swift Set operations, updating only the
  affected entries rather than rebuilding the full index on every change.
- **Dynamic Hot-Swapping**: To prevent stale caches when users mutate inner
  properties of existing scans (e.g., adding `customTags`), `ScansManager`
  listens for `NSNotification.Name("ScanRequiresSearchIndexUpdate")`. This
  explicitly triggers a targeted isolated re-evaluation via
  `SearchDatabaseActor`, updating the string index in under 10ms without an app
  reboot.
- **Dual-path indexing**: Full rebuilds cooperatively extract `RawScanSnapshot`
  values from the already-resident `allScans` array on `@MainActor` in
  128-record chunks with `Task.yield()` between chunks, then build both
  `SearchableScan` payloads and a detached `SearchIndexSnapshot`. Incremental
  inserts stay on `SearchDatabaseActor`, but fetch their delta through one batch
  `FetchDescriptor` (`WHERE id IN (...)`) rather than faulting records
  one-by-one; the main actor then upserts only the changed documents into the
  existing snapshot.
- **O(1) lookup caches**: `ScansManager` keeps `[String: Int]` index positions,
  a `[String: LocalScanRecord]` live-reference fallback map,
  `[String: ScanSortPrimitive]` sort snapshots, and a `sortedAllScanIDsCache`
  keyed by `ScanSortOption.rawValue`. The record map is rebuilt from the
  existing `@Query` array only; it must not trigger a second SwiftData fetch or
  copy model data. `record(for:)` resolves through the index first and falls
  back to the map if an index is stale during a snapshot transition.
- **Generation-guarded commits**: `searchCacheGeneration` increments whenever
  `allScans` changes. Full-rebuild snapshot extraction and incremental actor
  fetches both verify the generation before committing, so a cancelled/stale
  indexing task cannot overwrite a newer library snapshot.
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
- **Debug completion hook**: In `DEBUG`, `ScansManager` exposes internal
  `SearchDebugEvent` callbacks for `indexingCompleted` and `searchCompleted`.
  The test suite uses these events to await real background completion instead
  of sleeping for guessed debounce/indexing windows, which makes search
  regressions deterministic without changing the production control flow.
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
- **Detached Primitive Sort Engine**: `ScansManager` maps pure `@Model` objects
  into `ScanSortPrimitive` arrays before offloading large sorts to
  `Task.detached`. The "no query / all categories" path caches sorted ID arrays
  per sort option, so repeated sort changes and query clears do not rebuild the
  same full-library sort every time.

### `ProfileDatabaseActor` (Profile Stats)

- `@ModelActor` living with `UserStats` in
  `apps/ios/Merian/Features/Profile/UserProfile/Components/UserStats.swift`.
- Owns the off-main projection pipeline for `ProfileTabView`: species count,
  streak, 52-week heatmap, and award payloads.
- **Shared stats projection**: `calculateProfileStats()`, `calculateAll()`,
  `calculateHeatmapData()`, and `calculateAwardsProjection()` all load the same
  cached `ProfileStatsProjection` instead of issuing separate SwiftData fetches.
  The projection is built from `propertiesToFetch` scalar columns and contains
  only `Sendable` values (`ProfileAnalyticsProjection`, timestamps, and a
  precomputed unique-species count).
- **Cache fingerprint**: The actor validates cached projections with
  `recordCount`, latest scan ID, and latest timestamp before reuse.
  Inserts/deletes naturally invalidate the cache without reloading full rows
  just to check freshness. If a future long-lived caller edits existing scan
  fields in place, call `invalidateCachedProfileProjections()` before asking for
  updated profile stats.
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

| Constant                          | Value  | Consumer                                                                         |
| --------------------------------- | ------ | -------------------------------------------------------------------------------- |
| `uploadBatchSize`                 | 5      | `OfflineQueueManager+Sync`                                                       |
| `pendingScanFetchLimit`           | 50     | `OfflineQueueManager+Sync`                                                       |
| `mediaStagingMaxFilesPerRequest`  | 6      | `MediaStagingContract`                                                           |
| `stagedImagePayloadMaxBytes`      | 5 MB   | `MediaStagingContract`, Edge image fetch contract                                |
| `audioPayloadMaxBytes`            | 2.7 MB | `MediaStagingContract`, `MerianNetworkClient`                                    |
| `historicalSyncPageSize`          | 200    | `ScanRepository`                                                                 |
| `collectionsSyncPageSize`         | 100    | `ScanRepository`                                                                 |
| `ingestCheckpointInterval`        | 50     | `HistoricalDatabaseActor`                                                        |
| `imageCompressionQuality`         | 0.85   | `Capture`, `CaptureWorkspaceViewModel`                                           |
| `visionConfidenceThreshold`       | 0.65   | `InferenceEngine` (Vision pre-classifier)                                        |
| `visionConfidenceMargin`          | 0.15   | `InferenceEngine` (margin guard vs. second-best)                                 |
| `scanningPhaseSubjectDelayNs`     | 1.5 s  | `InferenceEngine` (delay before subject-specific phrases replace generic series) |
| `scanningPhaseRotationIntervalNs` | 2.3 s  | `InferenceEngine` (between phase phrases)                                        |

### `UserDefaultsKeys`

- Centralized enum (`Core/Utilities/UserDefaultsKeys.swift`) holding all
  persisted key strings.
- Prevents silent key mismatches between storage sites. UI-facing state should
  normally flow through `AppSettings`, not local `@AppStorage` wrappers.
- **Do not inline string literals for these keys anywhere in the codebase.**
  Always reference the constant.

| Constant                               | Key string                               | Sites                                                                                                                                                                               |
| -------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hasUnseenScan`                        | `"hasUnseenScan"`                        | `AppSettings` typed property. Read by `MainTabBar`; written by live/background inference completion; cleared by `InsightSheetView`, `CameraSheetRouter`, and `ScansSheetView`.      |
| `hasCompletedOnboarding`               | `"hasCompletedOnboarding"`               | `AppSettings` typed property. `MerianApp` and `AppLifecycleManager` gate root/lifecycle behavior through the injected settings instance.                                            |
| `themeMode`                            | `"themeMode"`                            | `MerianApp`, theme bootstrap                                                                                                                                                        |
| `opensExploreOnLaunch`                 | `"opensExploreOnLaunch"`                 | Default-off `AppSettings` preference sampled once by `MerianApp`; after onboarding, an ordinary cold launch may initialize the Capture workspace with Explore presented. Registered during settings initialization and reloaded by `AppSettings.reloadFromDefaults()`. |
| `isPushNotificationsEnabled`           | `"isPushNotificationsEnabled"`           | `AppSettings` typed property. Notification settings, inference completion, and offline failure/completion paths read/write through settings except low-level authorization mirrors. |
| `isMultiCaptureEnabled`                | `"isMultiCaptureEnabled"`                | `CaptureWorkspaceViewModel`, `DescribeAnalysis`, onboarding migration                                                                                                               |
| `showsCaptureGoalProgress`             | `"showsCaptureGoalProgress"`             | `AppSettings` typed property. The **Field trip goals** setting controls whether `CaptureWorkspaceView` presents the active outing target capsule and may forward its camera-only selected-goal hint; default `true`. Server progress remains enabled with deterministic fallback when off.                    |
| `legacyMultiImageScanMode`             | `"multiImageScanMode"`                   | one-time migration in `MerianApp`                                                                                                                                                   |
| `hasPromptedForNotificationsPostIdent` | `"hasPromptedForNotificationsPostIdent"` | `AppSettings` typed property. `CameraSheetRouter` uses it to present the post-identification notification prompt only once.                                                         |
| `hasSeenExploreOnboarding`             | `"hasSeenExploreOnboarding"`             | `AppSettings` typed property. `InsightSheetViewModel` uses it for the one-time Explore sharing prompt.                                                                              |
| `hasSeenExploreNewChip`                | `"hasSeenExploreNewChip"`                | `AppSettings` typed property. `MainTabBar` uses it for the one-time Explore "NEW" chip.                                                                                             |
| `hasUnseenExplorePost`                 | `"hasUnseenExplorePost"`                 | `AppSettings` typed property. Set after local share, cleared when the Recent Explore feed is loaded, and read by `MainTabBar`.                                                      |
| `lastSeenExplorePostSharedAt`          | `"lastSeenExplorePostSharedAt"`          | `AppSettings` typed property. Updated by `ExploreFeedViewModel` after the Recent feed loads and used by `MainTabBar` badge refresh.                                                 |
| `suppressInferenceBanners`             | `"suppressInferenceBanners"`             | `AppSettings` typed property for mutation; `PushNotificationManager.willPresent` performs a direct synchronous key read because the delegate method is nonisolated.                 |
| `lastBackgroundedDate`                 | `"lastBackgroundedDate"`                 | `AppLifecycleManager`                                                                                                                                                               |
| `lastHistoricalSyncDate`               | `"lastHistoricalSyncDate"`               | `AppLifecycleManager`, `SupabaseManager`                                                                                                                                            |
| `enrichedSpeciesTimestamps`            | `"enrichedSpeciesTimestamps"`            | `InferenceEngine`                                                                                                                                                                   |
| `isLiveInferencePaused`                | `"isLiveInferencePaused"`                | `CameraSettingsView`, `CameraManager`                                                                                                                                               |
| `invertZoomDirection`                  | `"invertZoomDirection"`                  | `ZoomSliderView`, `CameraPreviewView` (pan gesture), `CameraSettingsView`                                                                                                           |
| `zoomSideLeft`                         | `"zoomSideLeft"`                         | `ZoomSliderView`, `MainOverlayView`, `CameraSettingsView`                                                                                                                           |
| `zoomSliderVisible`                    | `"zoomSliderVisible"`                    | `ZoomSliderView`, `CameraSettingsView`                                                                                                                                              |
| `needsCollectionSync`                  | `"needsCollectionSync"`                  | Legacy one-release bridge only. `ScanRepository.configure(with:)` imports it into `OfflineJobRecord(id: "collection-sync")`; active scheduling should use the job record.           |
| `hiddenSmartCollectionIDs`             | `"hiddenSmartCollectionIDs"`             | `SmartCollectionPreferences` stores locally hidden smart collection ids; these are UI-only and are not synced through `/sync-collections`.                                          |
| `speciesPreferredNamePrefix`           | `"speciesPreferredName_"`                | `SpeciesPreferredNameStore` bridge for per-species display-name overrides used by Insights and Explore.                                                                             |

`KeychainKeys.hasAuthenticatedOAuth` is the single source of truth for the
authenticated-session marker used by `SupabaseManager`, `MerianNetworkClient`,
and `KeychainManager` migration logic. Do not inline
`"Merian_HasAuthenticatedOAuth"`.

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
- UI code in Insights and Explore should call this repository instead of
  directly mutating `LocalScanRecord.fieldNotes` or `FieldNotesStore`.

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
  `showsCaptureGoalProgress`, `gridColumns`, `saveToCameraRoll`, and notification
  toggles.
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
  callers without blocking threads. Admitted synchronous ImageIO work runs on
  an explicitly QoS-tagged concurrent queue, preventing both decode
  over-subscription JetSam panics and priority-inversion hang warnings.
- **Isolated media session**: `mediaSession` uses
  `httpMaximumConnectionsPerHost = 4`, `httpShouldSetCookies = false`,
  `requestCachePolicy = .reloadIgnoringLocalCacheData`, and `urlCache = nil`.
  This prevents remote thumbnail fetches from bloating the shared URL cache or
  starving the decode pool with a wider connection fan-out than the
  downsampler can sustain.
- Supports fallback fetching: loops natively through comma-separated URLs via
  Zero-OOM `ImageDownsampler` bounds.
- I/O helpers (`loadLocal`, `fetchRemote`) are `static nonisolated` — prevents
  `Task.detached` from re-entering the actor executor mid-operation and keeps
  network orchestration off the actor executor; synchronous decode work is
  isolated on the dedicated decode queue.

### `SimilarSpeciesImageFetcher`

- `@Observable` decoupled worker for resolving Wikipedia and GBIF encyclopedic
  image assets.
- Explicitly delegates stream rendering to `LocalImageLoader` using standard
  string URLs, rather than directly inflating raw `UIImage(data:)` blobs,
  protecting the JetSam boundaries and unifying the global caching layer.

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
  `SimilarSpeciesImageFetcher`, `InferenceEngine`, and `GBIFHeatmapMapView`
  declare a `private static let externalAPISession` (10 s / 30 s timeouts) for
  Wikipedia/GBIF best-effort enrichment fetches.
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

### Edge Network Operations (`S3` & `PostgreSQL` Bulk Insertions)

- **Centralized Cloudflare R2 Operations (`_shared/aws.ts`)**: `copyR2Object()`
  and `deleteR2Object()` are defined once and shared across `moderation`,
  `export-dwca`, and `revenuecat-webhook`, rather than duplicating
  `aws.sign(...)` headers in each.
- **Shared Diagnostic Prompts (`_shared/diagnostic.ts`)**: The AI prompting
  logic for `fetchDiagnosticComparison` is extracted into a shared utility,
  preventing 1:1 duplication between the `identify` and `enrich-scan` Edge
  functions.
- **N+1 Query Prevention (`sync-collections`)**: Instead of issuing sequential
  Supabase inserts per record, the layer collects all mappings into an array and
  issues a single `.insert(allMappings)` call, eliminating connection exhaustion
  under high collection counts.
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
- **`lastLinkedUserId` dedup guard**: `private var lastLinkedUserId: String?` —
  prevents double RevenueCat login and double PostHog identify on cold start.
  The Supabase SDK emits two auth events per session restore (local cache read +
  server validation); this guard skips the second event for the same user ID so
  external identity systems are only notified once per session.
- **RevenueCat identity attributes**: `linkExternalTelemetry(user:)` performs a
  best-effort read of the user's `public.users` row before calling
  `RevenueCatManager.shared.linkWithSupabase(...)`. The RevenueCat customer keeps
  the Supabase Auth UUID as the App User ID and also receives subscriber
  attributes such as `supabase_user_id`, `auth_email`, `public_username`,
  `public_author_name`, `public_identity_source`, and `account_kind` so Test
  Store customers can be matched back to Merian accounts.
  The lookup decodes a bounded array and uses its first row rather than requiring
  PostgREST singular-object semantics. A newly authenticated user may not have a
  `public.users` projection yet; an empty result is a normal best-effort fallback,
  not a `406` auth failure, and telemetry linking continues with Auth metadata.
- **`ghostSessionTask` single-flight**:
  `@ObservationIgnored private var ghostSessionTask: Task<Void, Never>?` —
  serializes anonymous session creation across all callers. This closes the
  suspension-window race where multiple `getValidAuthHeaders()` calls could each
  enter `initializeGhostSession()` and perform overlapping `signInAnonymously()`
  requests.
- **DRY OAuth Abstraction**: Apple Sign In and Google Sign In share a single
  `private func finalizeOAuthLogin` path, removing the duplicate
  `.linkIdentityWithIdToken` / `.signInWithIdToken` logic that previously
  existed in both flows. The existing-account fallback is entered only for
  Supabase Auth code `identity_already_exists`; network, timeout, configuration,
  and other linking errors preserve the active guest session.
- **Durable Ghost merge completion**: Before switching sessions,
  `SupabaseManager` stores each source-issued, provider-bound proof in a
  versioned `WhenUnlockedThisDeviceOnly` Keychain queue. Completion is
  single-flight per active task generation, so an older cancelled task cannot
  clear a newer handle after sign-out/re-login. Successful and terminal
  invalid/expired entries are removed individually; transient,
  wrong-destination, and Auth-cleanup failures remain queued for session-restore
  retries.
- **`keyWindowAnchor()` helper**: A private
  `keyWindowAnchor() -> ASPresentationAnchor` method was extracted to remove the
  identical implementation that was previously copy-pasted into two separate
  `presentationAnchor` methods.
- **Deduplicated anonymous sign-in**: The two identical anonymous sign-in code
  paths were collapsed into a single `isSessionMissing` check, removing the
  duplicate `signInAnonymously()` block.
- Maps Apple and Google OAuth hooks to migrate Ghost User accounts, calling
  `RevenueCatManager.shared.linkWithSupabase()` to align payment state.
- Normal sign-out uses Supabase `.local` scope, then clears RevenueCat and
  PostHog state for the current device. Do not use global sign-out for ordinary
  in-app logout because it revokes the account's other active devices too.

### `DetachedWork`

- Small shared executor-escape helper defined alongside app-wide DI primitives.
- Sanctioned use cases: background SDK bootstrap, sendable image preparation,
  bounded file cleanup, and narrow background database bridges.
- `DetachedWork.fireAndForget(...)` replaces ad hoc `Task.detached` in
  high-level app flows so the exceptional escape from structured concurrency
  remains explicit and lintable.
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
- **`migrateFromUserDefaults()`**: The `init` migration logic was extracted into
  a named method for clarity.

## Events & Circuit Breaking

### `AppEventPublisher`

- Lives at `Core/Utilities/AppEventPublisher.swift`. `@MainActor final class`
  with a `PassthroughSubject<AppEvent, Never>` publisher and a
  `static let shared` singleton.
- Replaces `NotificationCenter` broadcasts with strongly-typed `AppEvent` cases:
  - `.triggerPaywall` — dispatched when the scan quota is exhausted;
    `CaptureWorkspaceViewModel` listens and sets `activeSheet = .paywall`, which
    `CameraSheetRouter` presents as `PaywallView`.
  - `.appDidEnterActivePhaseWithScan(scanId:)` — dispatched from a push
    notification tap to deep-link to a specific scan's insight sheet.
  - `.appDidEnterActivePhaseWithExplorePost(postId:)` — dispatched from Explore
    push taps and widget URLs to open `ExploreView` and route to a post detail.
  - `.appDidResumeAfterTimeout` — dispatched when
    `AppLifecycleManager.handleActivePhase()` detects that the app was
    backgrounded for more than 5 minutes; `CaptureWorkspaceViewModel` clears
    stale modal state unless a fresh external route has just been opened.
  - `.requestIdentifyNatureIntent` — dispatched by Siri/OS App Intents to jump
    to the camera viewfinder.
  - `.requestRecallLastFindIntent` — dispatched by Siri/OS App Intents to open
    the last scan's insight sheet.
  - `.triggerRefinement(record:)` — dispatched from insight views when the user
    requests re-inference on an existing scan with supplementary images;
    `CaptureWorkspaceViewModel` listens via
    `AppEventPublisher.shared.publisher.sink`.
  - `.explorePostNeedsRefresh(postId:)` and
    `.exploreShareStateChanged(scanId:postId:)` — dispatched after local scan
    review or Explore publication state changes so Explore surfaces can refresh
    without global notification names.
- Registered in `AppDIContainer` as
  `var appEventPublisher = AppEventPublisher.shared`. **Not
  environment-injected** — call sites access it via
  `AppDIContainer.shared.appEventPublisher` or `AppEventPublisher.shared`
  directly.

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

- Manages `isProActive` state.
- Handles RevenueCat `CustomerInfo` refreshes, evaluates standard Pro
  entitlements, and treats `pro_week` as a detached non-subscription
  purchase that is active for seven days from its purchase date.
- Connects authenticated users to RevenueCat; the `revenuecat-webhook` Edge
  function remains the server-side purchase authority and writes timed pass
  expiry into Supabase.
- `RevenueCatOfferingPolicy` defines the paywall's required App Store product
  identifiers: `pro_week` and `pro_annual`. `fetchOfferings()` logs an error when
  there is no current offering, no available packages, or either required
  product is absent. These diagnostics do not create products or repair package
  mapping; App Store Connect product readiness and RevenueCat dashboard mapping
  remain release prerequisites.

### `UsageManager`

- Lives at `Core/Analytics/UsageManager.swift`. Enforces the daily free-tier
  scan quota.
- `canPerformScan(isProActive:) -> Bool` — returns
  `isProActive || freeScansRemaining > 0`. Checked at two pre-scan gates only:
  `Capture.swift` (camera shutter) and `handlePhotoPickerSelection` (photo
  library picker). Network failures in `InferenceEngine` never trigger the
  paywall — they surface an error state and refund the token.
- `consumeScan()` — called once at enqueue time inside
  `OfflineQueueManager.insertAndPersistRecord` / `enqueueNonVisualCapture`,
  before the `OfflineQueuedScan` record is committed. Every scan that enters the
  queue is already paid for; `syncPendingScans` has no quota checks.
- `refundScan()` — restores the consumed token if inference fails unrecoverably
  (task cancellation, JSON decoding failure, network error) or if queue
  insertion fails after a token was reserved.
- Grants 1 free daily scan via `UserDefaults` keyed against
  `DeviceIdentityManager.shared.deviceId`. Resets limits at calendar day
  boundaries via `evaluateDailyRefresh()`, called from
  `AppDIContainer.handleActivePhase()` on foreground transitions.
- **Prelaunch override**:
  `FeatureFlag.unlimitedFreeScans.defaultValue` is intentionally `true` in
  every current build, including Release/TestFlight, so testers are not
  constrained by the daily free quota. Before the public App Store release,
  change its central default to `false`, rerun `UsageManagerTests`, and verify
  the standard Pro/free quota path on a physical release-candidate build.
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
- `evaluateAchievementsForNotifications(awards:enqueueToasts:)` — called after
  `ProfileDatabaseActor.calculateAwards()` completes after every inference.
  Checks for newly completed awards, persists `unlockedAchievements`, returns
  toast-eligible awards, and queues native local push notifications via
  `PushNotificationManager` when the achievement notification setting allows
  it. `enqueueToasts` defaults to `true` for existing callers; scan completion
  passes `false` so the coordinator can batch the returned awards after Field
  trip progress. Cat and dog achievements use a July 4, 2026 notification cutoff
  so historical qualifying scans are seeded silently instead of showing
  retroactive unlock banners.
- **The Field Naturalist** is the server-authoritative exception to the local
  scan calculator. `ScanMilestoneCoordinator` merges the typed earliest standard
  outing for every user and a Seasonal Challenge payload only when
  `FieldTripEventsAvailability` is enabled, saves only visible results in an
  account-scoped `UserDefaults` cache, and passes it to
  `GamificationManager` only when the current server mutation reports a new
  unlock. There is no rollout cutoff because Field trips had no prior user
  engagement.
- Full architecture documented in
  [06-profile-and-gamification.md](../features-and-hardware/06-profile-and-gamification.md).

### `MilestoneToastPresenter`

- Lives at `Core/UI/Feedback/AchievementToastPresenter.swift` and is kept under
  the legacy filename for Xcode/project continuity. It is an
  `@MainActor @Observable` singleton that owns a FIFO bottom in-app milestone
  queue.
- Supports `.achievement(AwardPayload)` for achievement unlocks and
  `.dictionary(.newToMerian)` for species-dictionary contribution milestones,
  plus `.fieldTrip(FieldTripMilestonePayload)` for standard outing and Seasonal
  Challenge progress.
- `ScanMilestoneCoordinator` is the production scan-completion boundary shared
  by foreground `InferenceEngine` and background `OfflineQueueManager` paths.
  It deduplicates by final scan ID, awaits the existing persistence/progress
  attempt, gathers achievements without presenting them immediately, evaluates
  `SpeciesData.isNewToMerianDictionary`, and synchronously enqueues standard
  Field trips, visible Seasonal Challenges, achievements, then **New to Naturebook**.
  When Events are disabled, the coordinator removes challenge progress before
  caching, refresh publication, destination construction, or toast presentation.
  Identification corrections reapply progress through the same coordinator but
  do not replay the original scan-achievement/dictionary batch. When Field trips
  are disabled, the coordinator skips its progress resolver while ordinary scan
  achievements and dictionary milestones continue normally.
  `.fieldTrips` is currently enabled in the central `FeatureFlags` registry;
  availability injection remains as a test seam and future emergency
  client-build control. The
  independent Events gate does not suppress standard outing progress.
  Retryable failures keep the selected-goal SwiftData row as a durable outbox,
  release ordinary milestones through a separate once-per-scan guard, and use
  bounded in-process retries. `OfflineJobScheduler` replays leftover hints after
  relaunch; only success, terminal ingestion failure, or disabled Field trips
  acknowledges and removes the hint.
- The presenter controls only in-app banner presentation. It does not mutate
  Field trip progress, achievement progress, dictionary state, analytics, or
  native notification authorization. DEBUG Settings preview entry points
  enqueue representative achievement, dictionary, and Field trip payloads
  through the same queue while bypassing persistence and OS notifications.
- Completed Field Naturalist cards and unlock toasts carry a typed
  `CaptureGoalDestination` and open the outing or Seasonal Challenge that earned
  the award. Its locked card continues to open the requirement sheet.

### `PostHogManager`

- Not `@MainActor` — `PostHogSDK` is thread-safe, and the wrapper uses an
  `NSLock` around configuration and pending identity state.
- `SupabaseManager` configures PostHog before it constructs the auth listener,
  so restored-session identity events usually arrive after `setup()` has
  completed. `configure()` is idempotent for secondary startup callsites.
- Tracks `isConfigured: Bool` set at the end of `configure()`. `identifyUser()`
  still buffers a pending user ID if a future call races setup, but this is an
  expected debug path rather than a warning.
- Calls `reset()` on sign-out to clear the PostHog session.

## 2026-04 Hardening Updates

- `InferenceEngine` now treats pending background writes as generation-scoped
  work. Any scan reset or cancellation invalidates the old generation before the
  next scan can enqueue or drain background mutations.
- `AudioCaptureManager` owns full startup failure cleanup. Cancellation after
  `AVAudioSession` activation now still removes the input tap, stops the engine,
  cancels DSP work, finishes the spectrogram stream, and clears pending temp
  files.
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
