# Camera and Hardware Orchestration

The optical and physical layer of the Merian application wraps Apple's `AVFoundation` framework behind a thermal-aware orchestrator.

## The Core Pipeline

### `CameraManager`

The lowest-level integration, interfacing directly with the iPhone optics.

- Instantiates the `AVCaptureSession` via `AVCaptureDevice.DiscoverySession`, prioritizing `.builtInLiDARDepthCamera` for accurate physical scale.
- Configures parallel buffers routing to `AVCaptureVideoDataOutput`, `AVCaptureDepthDataOutput`, and `AVCapturePhotoOutput`. Sets `videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]` so that `ViewfinderIntelligence` can extract raw Luma brightness bounds from memory plane 0 without expensive CPU color-space conversions.
- Evaluates `photoOutput.isDepthDataDeliverySupported` during configuration, mapping `.isDepthDataDeliveryEnabled` downstream into `AVCapturePhotoSettings`. This validation prevents `SIGABRT` / `NSInvalidArgumentException` crashes in AVFoundation on non-LiDAR devices that attempt depth captures.
- Sets `photoOutput.isHighResolutionCaptureEnabled = true`, letting Apple's Image Signal Processor manage dynamic resolution, avoiding 48MP RAW byte crashes.
- Tracks `@Observable var isFlashEnabled`, driving hardware flash through `device.torchMode` under `.lockForConfiguration()` to handle dark environments. The flash mode is resolved at shutter execution. To satisfy Swift 6 concurrency constraints, this `@MainActor` property is copied before any `queue.async` background capture blocks. `toggleFlash()` executes on a background `queue.async`, pushing state changes back to the main thread on completion, keeping the UI thread free during rapid hardware-locking commands.
- Routes `setupSession()` initialization onto a background `queue.async` inside `init()`. All Image Signal Processor negotiations — `applyTargetFPS(_:)`, `throttleToIdleState()`, and `resetFocusAndExposure()` — wrap `device.lockForConfiguration()` inside this background queue. Dynamic framerate `CMTime` calculations clamping `device.activeFormat.videoSupportedFrameRateRanges` are factored into a shared `applyFrameRate(_:to:)` helper marked `nonisolated` so it can run off the `@MainActor` without concurrency warnings. This isolates `activeVideoMaxFrameDuration` logic in one place, keeps the `@MainActor` free during lens shifting, and publishes results back to SwiftUI safely.
- Throttles the 60fps LiDAR depth data loop (`depthDataOutput`) to 3fps using an `NSLock` throttler, reducing thermal pressure before any `@MainActor` context switch.
- Guards `AVFoundation` shutter callbacks against race conditions using `withCheckedThrowingContinuation`, synchronizing on the `@MainActor` before delegating `capturePhoto` to the background queue. `CameraViewModel.executeCapture` wraps an `@Published var isCapturing: Bool` lock to prevent rapid double-tap crashes. To prevent `.paywall` overrides from `AVCaptureEventInteraction` false positives during inference, `handleInferenceProcessingChange` defers `.insight` assignment into `DispatchQueue.main.async`, allowing the `UIWindow` to stabilize the hardware shutter button state.
- Reads the LiDAR depth vector `subjectDistanceInMeters` at the exact moment of shutter capture. Deferring this read to `handleCropCompletion` would return floor data or `nil` after the user pans away, so `capturedDistance` is extracted during shutter engagement to give Gemini accurate plant scale data.
- Throttles preview feeds between 15–60 FPS to conserve memory.
- **Native Hardware Interaction (`AVCaptureEventInteraction`)**: Uses the iOS 17.2 hardware API to intercept native volume buttons, the Action button, and the iPhone 16 Camera Control. Bound on the `.began` event phase for zero-latency capture parity with the system Camera app. Grabs a live `CLLocation` snapshot at capture time. Disables itself when UI sheets or modals are open to prevent volume hijacking.
- **Tap-to-Focus & Tap-to-Expose**: Uses `.captureDevicePointConverted` in `CameraPreviewView` to translate UI touches into hardware coordinates. Offloads `lockForConfiguration` adjustments to the background queue for `.autoFocus` and `.autoExpose` tracking without deadlocking. Enables `isSubjectAreaChangeMonitoringEnabled` and registers `AVCaptureDevice.subjectAreaDidChangeNotification` to reset focus back to continuous tracking when the device is panned away.
- **Zoom (`zoomFactor`, `maxZoomFactor`, `setZoom(factor:)`)**: `maxAvailableVideoZoomFactor` is read from the selected `AVCaptureDevice` immediately after `session.commitConfiguration()` — reading it before the commit returns 1.0 because the active format is not finalized until that point. The value is shipped to `@MainActor` via `Task { @MainActor [weak self] in }` (same pattern as `isSessionRunning`). `isZoomSupported` is `true` when `maxZoomFactor >= 2.0`, hiding the control entirely on single-lens hardware. `setZoom(factor:)` sets `zoomFactor` on `@MainActor` immediately for responsive UI, then applies `device.videoZoomFactor` on the background `queue` under `lockForConfiguration` — identical threading pattern to `toggleFlash()`. In simulator builds (`#if targetEnvironment(simulator)`), `maxZoomFactor` is stubbed to `5.0` because the simulated camera always reports `1.0`.
- **Thread-Safe Capture Operations**: Resolves data races and array bounds exceptions (`SIGABRT`) from overlapping hardware capture timeouts. Replaces the linear `activeCaptureRequests` array with a thread-safe `Dictionary<Int64, CaptureRequest>` keyed by `AVCapturePhotoSettings.uniqueID`, providing atomic O(1) removals via an `NSLock` that synchronizes `@MainActor` continuation callbacks with the asynchronous hardware delegates.

### `ZoomSliderView` (`Features/Camera/Components/ZoomSliderView.swift`)

A self-contained vertical zoom slider overlaid on the right side of the camera viewfinder. Reads `CameraManager` from the environment — no parameters are passed from `MainOverlayView`.

- Renders only when `CameraManager.isZoomSupported` is `true`. Returns `EmptyView` on single-lens hardware, keeping the viewfinder clean on devices where zoom would be purely digital.
- Hidden automatically when `activeScanImages` is non-empty (image staging mode), via the `activeScanImages.isEmpty` guard in `MainOverlayView`'s `.overlay(alignment: .trailing)`.
- **Thermometer track**: 200pt `Capsule` with `.ultraThinMaterial` + `.dark` colorScheme (matching `FlashButton`). A white fill grows from the bottom as zoom increases. The thumb circle + zoom label pill (`"1×"`, `"2.1×"`) float above the fill.
- **DragGesture math**: Captures `dragStartFactor` at gesture start. Each frame: `deltaFactor = (-translation.y / trackHeight) * (maxZoomFactor - 1.0)`. Proposed = `dragStartFactor + delta`, clamped to `[1.0, maxZoomFactor]`. Accumulating from start rather than per-frame delta eliminates floating-point drift on long drags.
- **Haptic detents**: `UIImpactFeedbackGenerator(style: .rigid, intensity: 0.6)` fires when `zoomFactor` crosses within ±0.05 of 1×, 2×, or 3× (stops that exist within `maxZoomFactor`). A ±0.07 hysteresis band via `lastHapticStop` prevents chattering when hovering near a stop.
- Zoom changes propagate to all three input surfaces (slider, swipe, pinch) in real time because all call `CameraManager.shared.setZoom(factor:)`, which updates the `@Observable zoomFactor` property.

### `CameraPreviewView` — Viewfinder Gestures

Three `UIGestureRecognizer` instances are registered on the `AVCaptureVideoPreviewLayer` backing view, all with `cancelsTouchesInView = false` so SwiftUI overlay controls (shutter, flash, etc.) continue to receive touches:

| Gesture | Recognizer | Behaviour |
|---|---|---|
| Tap | `UITapGestureRecognizer` | Tap-to-focus & expose at the tapped point |
| Vertical swipe | `UIPanGestureRecognizer` | Zoom in (up) / zoom out (down) |
| Pinch | `UIPinchGestureRecognizer` | Zoom in / zoom out |
| Horizontal swipe left | `UIPanGestureRecognizer` (same instance) | Reserved — will open audio recording mode |

The single `UIPanGestureRecognizer` handles both vertical zoom and the future horizontal mode switch. Direction is locked on the first `.changed` frame where `abs(velocity.y) > abs(velocity.x)` (vertical) or vice versa, preventing diagonal drift from triggering both actions. The horizontal branch fires `onSwipeLeft?()` on gesture end when `velocity.x < -200 pt/s`; the closure defaults to `nil` until the audio recording view is built.

Pinch zoom captures `pinchStartZoom` at `.began` and computes `proposed = pinchStartZoom * sender.scale` on each `.changed` frame — `scale` is relative to gesture start, so multiplying by the start factor gives the correct absolute zoom without drift.

### `HapticManager`

Centralizes UI vibration feedback, keeping haptic engine initialization off the critical path.

- Pre-warms `.heavy`, `.light`, `.rigid`, `.medium` `UIImpactFeedbackGenerator` instances and a `success` `UINotificationFeedbackGenerator` sequentially inside `init()` using `.prepare()`.
- The shared `AppDIContainer.shared.hapticManager` instance is injected into `CameraViewModel` shutter callbacks and `ImageCropperView` crop confirmations, eliminating the 15+ ms stutter caused by cold-starting taptic engines at input time.
- **System Haptics Toggle (`isHapticsEnabled`)**: All motor triggers are guarded by a `UserDefaults.standard.bool(forKey: "isHapticsEnabled")` check. If the user disables haptics in Settings, `HapticManager` skips all `.impactOccurred()` calls.

### `MerianAppIntents` (Siri Shortcuts)

Integrates with the iOS App Intents framework to expose voice and springboard shortcuts outside the application.

- **Identify Nature (`IdentifyNatureIntent`)**: Exposes "Identify this with Merian" or "Open Merian camera" voice triggers to Siri, bringing the app to the foreground and executing `navigateTo("camera")` with a `HapticManager` focus callback.
- **Recall Last Find (`RecallLastFindIntent`)**: Handles "What was the last thing I scanned" queries, routing the OS to display the user's most recent `LocalScanRecord` with a sheet spring haptic.
- Registered via `AppShortcutsProvider`, presenting `.teal` action tiles in the iOS Shortcuts application.

### `HardwareOrchestrator`

Battery and thermal protection, monitoring device usage thresholds.

- An `@Observable` class that decouples rendering overhead from device thermals.
- Bridges `.thermalStateDidChangeNotification`, dropping graphic resolutions and Glassmorphism shaders on `.critical` or `.serious` states.
- Monitors `isLowPowerModeEnabled` and engages a 24fps `isExpeditionModeActive` pipeline on low-battery states.
- **Expedition Mode Override**: Users can set `HardwareOrchestrator.shared.isExpeditionModeActive = true` via Settings to force the 24fps framerate cap and drop iOS glass materials, trading UI fidelity for maximum battery life off-grid. This flag is also read by `OfflineQueueManager`, pausing background cellular uploads.

### `ViewfinderIntelligence` (VUI)

An asynchronous heuristic layer that prevents wasted network calls on poor-quality frames.

- Rate-limits concurrent inference using an `NSLock` and `CFAbsoluteTimeGetCurrent()` thresholds on the background memory queue, reducing 60fps frame callbacks to 3fps before any `@MainActor` context switch. To avoid GPU thermal pressure, it does not instantiate any `CIContext` or CoreImage pipelines and performs no `CGAffineTransform` work. It locks the base Luma plane address (`CVPixelBufferGetBaseAddressOfPlane`) on the CPU, iterating byte indices over a 10-step subsample to evaluate scene brightness. When publishing analysis states (`currentHint` and `isOptimal`) back to the app, Swift equality checks intercept redundant property updates to avoid continuous 3fps UI thrashing in `CameraRootView`.
- **Legacy Viewfinder Toggle (`isLiveInferencePaused`)**: Users can disable this engine via the "Legacy Viewfinder" toggle in Settings, cutting off background thread processing and running as a standard camera. This defaults to **ON** for modern iPhones (iPhone 14+) via `UIDevice.current.isModernIPhone` to avoid aggressive ambient mapping under thermal pressure. `throttleToIdleState()` caches the user's preference in a private tracker before locking the module; `restoreFromIdleState()` restores it, preventing system thermal overrides from permanently overwriting the user setting.
- **Initialization Suppression**: `CameraManager` suspends VUI evaluation (`pauseAnalysis(for: 2.5)`) for the first 2.5 seconds after camera start or restoration from idle, preventing the ISP's low-light boot sequence from triggering false-positive alerts.
- Triggers `VUIHint` prompts across the viewfinder without any network calls. Evaluates `brightness`, `distance`, and `lumaStdDev` per frame. Hint priority (highest to lowest): **Move closer** (distance > 3.0m) → **Move back** (distance < 0.12m) → **Too dark** (brightness < 0.20) → **Move to shade** (brightness > 0.88) → **Hold still** (lumaStdDev < 20.0 — low luma variance indicating motion blur or featureless framing) → **Optimal**.
- Blocks inference from querying cloud services unless the internal brightness buffer passes its threshold.

### `PhotoLibraryManager`

A dedicated `PHPhotoLibrary` handler.

- Uses `.opportunistic` `PHImageRequestOptions` to fetch the most recently added asset asynchronously for the camera gallery icon. Mutations to `latestThumbnail` are dispatched via `Task { @MainActor in }` to avoid iCloud data-fetch thread panics. Implements `deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }` to prevent dangling observer memory leaks from singleton `PHPhotoLibraryChangeObserver` registrations.
- **Camera Roll Opt-Out (`saveToCameraRoll`)**: Captures run through a `UserDefaults.standard.bool(forKey: "saveToCameraRoll")` check inside `saveImageToLibrary(...)`. Defaults to `true` to build the user's iCloud album; if toggled off, bytes go only to SQLite, bypassing Apple's `.performChanges` path.
- **DRY Authorization State (`executePhotoLibraryWrite`)**: The `PHPhotoLibrary.authorizationStatus` fallback logic and `PHPhotoLibrary.shared().performChanges` transaction blocks that were duplicated across `saveImageManual` and `saveImageToLibrary` are now consolidated into a single `executePhotoLibraryWrite` helper that handles both `.readWrite` and `.addOnly` access levels.
- Wraps `PHAssetCreationRequest.forAsset()` on a background task, saving the unmodified 12MP sensor buffer to the camera roll. Keeping the payload as raw bytes rather than casting to `UIImage` preserves EXIF GPS fields, LiDAR metadata, and Apple Deep Fusion data. The save is dispatched via `Task.detached { await saveImageToLibrary(...) }` inside `CameraViewModel.executeCapture`, decoupling the `performChanges` transaction from the UI thread while the image goes to the cropper immediately.
- **Historical Data Extraction**: When a user selects a library photo, the manager pulls the underlying `PHAsset` via its local identifier, extracting the original GPS coordinates and creation date to anchor AI context to the photo's actual capture timestamp. Before `submitActiveScan()` performs its state cleanup, it caches this EXIF telemetry and prioritizes it over the device's live location so library uploads map to their true locations.
- **OOM Prevention & UI Decoupling**: Live 12MP hardware buffers are passed through `ImageDownsampler.downsample()` immediately (capped at 4000px). For historical `PhotosPickerItem` bytes, the system uses `.loadFileRepresentation(for: .image)` to write bytes to a temporary sandboxed URL rather than `loadTransferable(type: Data.self)`, avoiding the uncompressed 48MP HEIC/ProRAW expansion that triggers iOS JetSam OOM crashes. `ImageDownsampler` consumes the on-disk URL without loading it into RAM. GPS stripping (`stripGPS(from:)`) via ImageIO runs in a `Task.detached` context to protect the 120Hz scroll rate during historical imports.
- **Instant Scan Mode vs Multi-Image Mode (`multiImageScanMode`)**: The default experience (`multiImageScanMode = false`) auto-submits after a single capture or photo library pick via an `onChange(of: activeScanImages.count)` observer in `CameraRootView`. With "Multi-image scans" enabled, users get the staging experience. `MainOverlayView` reads `@AppStorage("multiImageScanMode")` and caps the `PhotosPicker` `maxSelectionCount` to `1` in instant mode, or `max(1, 2 - activeScanImages.count)` in multi-image mode.
- **Multi-Image AI Context Appending**: Users can stage up to 2 images into the inference pipeline to broaden the AI's understanding of subject morphology and environment (e.g., a macro leaf shot plus a tree bark photo). `CameraViewModel` buffers `activeScanImages` and handles `PhotosPickerItem` interactions via `handlePhotoPickerSelection`, appending into `activeScannedDatas` and supporting mixed optical captures and library imports. On hitting "X" (cancel) or the submit arrow on the Active Scan Toolbar, `activeOriginals.removeAll()` is enforced alongside the UI thumbnail array clear — omitting this step orphans index lookups and causes out-of-bounds corruption on subsequent scans. `submitActiveScan()` extracts `historicalContext` from the first element of `activeOriginals` before the `removeAll()` to preserve EXIF location data from library uploads.
- **Scanning Overlay Phase Rotation**: `submitActiveScan()` concurrently fires `classifySubjectLocally(from:)` alongside the network inference call. See [AI Engineering → On-Device Pre-Classification](../system-architecture/17-ai-engineering.md) for the full qualification logic, confidence thresholds, and 3-second delay behaviour.
- **Accelerate Histogram Memory Isolation (`CameraManager.swift`)**: During 60fps hardware execution, the histogram buffer is now allocated as a local variable (`var histogram = [vImagePixelCount](repeating: 0, count: 256)`) inside the `captureOutput(_:)` scope instead of a single global `nonisolated(unsafe)` instance. This gives each frame isolated memory without thermal cost and satisfies Swift 6 strict concurrency rules.

### `EnvironmentContext`

A plain data struct extracted from `EnvironmentContextManager`. Lives in `merian/Core/Hardware/EnvironmentContext.swift`.

Fields: `location: CLLocation?`, `locationName: String?`, `weatherCondition: String?`, `weatherTemperature: Double?`.

### `EnvironmentContextManager`

Follows a continuous background tracking philosophy during the camera lifecycle.

- Starts `locationManager.startUpdatingLocation()` and `locationManager.startUpdatingHeading()` whenever the camera viewport is visible, terminating updates on disappearance to save battery. `cachedLocation` is read at the moment `CameraViewModel.executeCapture` fires, binding coordinates directly into the `PhotoLibraryManager` payload with zero latency.
- Resolves `CLLocation` and passes it to Apple's `WeatherKit` `WeatherService.shared`, capturing `weatherCondition`, `weatherTemperatureF`, and `gpsElevation`. Concurrently runs an `MKReverseGeocodingRequest` to derive `locationName`. During the Crop UI phase, an asynchronous `fetchDeferredContext` mutates `@Published var preFetchedContext`, hiding network latency from the user behind the crop interaction.
- The environment snapshot feeds Gemini with regional context for identification and invasive species logic, and persists UI metrics in the offline Scans library. (Requires the `com.apple.developer.weatherkit` entitlement set to `true` in `project.yml`; otherwise it silently returns `nil` for all fields.)
- **Historical Weather & Location Backfilling**: `fetchHistoricalContext` queries WeatherKit using `.hourly(startDate: date, endDate: date.addingTimeInterval(3600))` and runs a historical `MKReverseGeocodingRequest`, allowing library uploads to reconstruct environment conditions without external servers. If a scan was captured offline and lacks `weatherCondition`, `OfflineQueueManager` calls `fetchHistoricalContext` retroactively using the stored GPS coordinates and capture timestamp before triggering inference.
- **GPS Accuracy Filter (<= 30m Horizontal)**: Coordinate fetching waits behind a 2.0-second `Task.sleep` to let the GPS settle. Incoming location updates are filtered to `horizontalAccuracy < 30m`; if that threshold is met, the method exits early with high-fidelity telemetry. If the device cannot achieve that accuracy (indoors or under heavy canopy), the timeout falls back to the strongest `cachedLocation` available. The timeout is managed via a `timeoutTask: Task<Void, Never>?` that is checked with `!Task.isCancelled` and cancelled immediately on a successful `didUpdateLocations` callback, preventing stalled camera pipelines.
