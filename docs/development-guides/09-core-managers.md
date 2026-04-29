# Core Application Services & Managers

Merian uses a structured singleton pattern managed through `AppDIContainer.swift`. These singletons own global application state without triggering excessive SwiftUI view rebuilds.

## Hardware Domain

### `SpeechManager`
- `@MainActor @Observable final class` living at `merian/Features/Describe/Managers/SpeechManager.swift`, registered in `AppDIContainer` and distributed to the view hierarchy via `DIContainerModifier`.
- Owns the full `AVAudioEngine` + `SFSpeechRecognizer` pipeline for live voice dictation on the Describe page.
- **`isRecording: Bool`** — the single source of truth for dictation state. Drives the `CaptureButton` pulse animation and the `onTranscribe` stop-path guard in `CaptureWorkspaceView`. Never set to `true` until `audioEngine.start()` succeeds; reset to `false` in all failure and teardown paths.
- **`startDictation(onResult: @MainActor @escaping (String) -> Void) async throws`**:
  - Initializes `SFSpeechRecognizer()` and silently no-ops if the recognizer is `nil` or `!isAvailable` (unsupported locale — no user-visible error).
  - Requests `SFSpeechRecognizer` authorization and microphone permission (`AVAudioApplication.requestRecordPermission()`) via `withCheckedContinuation`. Throws `PermissionError` on denial; caller surfaces this via `viewModel.offlineToastMessage`.
  - Checks `Task.isCancelled` after each `await` suspension point. If cancelled after the `AVAudioSession` was already activated, releases the current `AudioSessionCoordinator.Lease` before returning — preventing stale deactivation work from killing a newer audio session.
  - Configures `AVAudioSession` as `.record` / `.measurement` through `AudioSessionCoordinator.shared.activate(.recordMeasurement(...))`, not by calling `AVAudioSession.sharedInstance()` directly on the main actor. This serializes dictation with `AudioCaptureManager` and makes teardown token-aware.
  - `isRecording = true` is assigned as the **absolute final line** — only after `try audioEngine.start()` confirms the engine is live.
- **`stopDictation()`** — delegates entirely to `teardownAudioEngine()` then sets `isRecording = false`. Safe to call when the engine was never started.
- **`teardownAudioEngine()` (private)** — calls `audioEngine.stop()` and `audioEngine.inputNode.removeTap(onBus: 0)` **unconditionally** (both are no-ops if not running / no tap installed). This prevents an orphaned tap crash when `start()` throws after `installTap` has already been called. Ends and nils the recognition request and task, then releases the leased audio session through `AudioSessionCoordinator.shared.deactivate(ifCurrent:)`.
- **Auto-termination**: The `SFSpeechRecognitionTask` result handler dispatches back to `@MainActor` via `Task { @MainActor [weak self] in ... }`. When `error != nil || result.isFinal == true`, it calls `stopDictation()` internally — the user does not need to tap the mic again to stop a session that the system ended (e.g. 60-second silence timeout).
- **`PermissionError`** — a `LocalizedError` struct defined in the same file. Thrown exclusively on permission denial, caught by `catch is PermissionError` at the `CaptureWorkspaceView` call site for toast display. All other throws (hardware faults, `AVAudioEngine` start failure) are silently swallowed at the call site since no user-actionable recovery path exists.

### `AudioCaptureManager`
- `@MainActor @Observable final class` at `merian/Core/Hardware/AudioCaptureManager.swift`, registered as `var audioCaptureManager = AudioCaptureManager()` in `AppDIContainer` and distributed via `DIContainerModifier`.
- Owns the full `AVAudioEngine` bioacoustic recording pipeline for the `.audio` capture page.
- **`isRecording: Bool`** — single source of truth for recording state. Set to `true` only after `audioEngine.start()` succeeds.
- **`isPaused: Bool`** — engine is paused mid-recording (tap preserved, countdown halted). Can only be `true` when `isRecording` is also `true`.
- **`recordingProgress: Double`** — 0.0 → 1.0 over 15 seconds, driven by a 100-tick countdown Task (150 ms per tick).
- **`spectrogramColumns: [SpectrogramColumn]`** — rolling 180-column display buffer fed by `SpectrogramActor` on each tap callback.
- **`snrLevel: SNRLevel`** — most recent SNR classification from `SpectrogramActor.snrLevel(from:)`.
- **`pendingPlaybackPath: String?`** — non-nil after recording finishes, before the user confirms or discards. Drives the review state UI.
- **`playbackProgress: Double`** — 0.0 → 1.0 playhead position; preserved across play/stop cycles so `playPendingRecording()` resumes from the scrubbed position.
- **`audioFilePath: String?`** — set to the WAV filename only when the user confirms via review UI; consumed and cleared by `CaptureWorkspaceView.onChange` → `submitAudio` → `reset()`.
- **`startRecording() async throws`**: guards with `!isRecording && !isStartingRecording` (the `isStartingRecording` flag is set before any `await` to prevent a second call from slipping through the guard during the async permission + engine-setup window — this was the source of the `nullptr == Tap()` AVAudioEngine crash). Session activation now flows through the shared `AudioSessionCoordinator`, which returns a lease token stored on `AudioCaptureManager`; teardown deactivates only if that lease is still current, eliminating stale stop-work from interrupting a newer record/playback cycle. Writes **Int16 PCM WAV** via an explicit `AVAudioFormat(commonFormat: .pcmFormatInt16, ...)` to avoid the WAVEFORMATEXTENSIBLE (`audioFormat = 0xFFFE`) variant that the edge audio parsers do not support. The tap now copies each `AVAudioPCMBuffer` synchronously into a bounded `AsyncStream(bufferingNewest: 2)` before handing it to `SpectrogramActor`, preventing tap-owned buffers from crossing the async boundary and capping DSP backlog.
- **`pauseRecording()`** — cancels countdown, calls `audioEngine.pause()`, sets `isPaused = true`.
- **`resumeRecording()`** — reacquires a fresh `AudioSessionCoordinator.Lease`, calls `audioEngine.start()`, and rebuilds the countdown from current `recordingProgress`.
- **`stopRecordingEarly()`** — cancels countdown, calls `finishRecording()` — same end state as timer completion.
- **`seekPlayback(to:)`** — seeks `AVAudioPlayer.currentTime` and updates `playbackProgress`; works while playing or stopped.
- **`cancelRecording()`** — cancels countdown task, tears down engine, deletes partial file from `tmp/`, calls `discardPending()`.
- **`discardPending()`** — deletes pending file if present, **always** clears `spectrogramColumns`, `snrLevel`, `snrHoldTicks` — display state is cleared unconditionally (not gated on `pendingPlaybackPath`) so calling it before `startRecording()` also wipes the previous session's columns.
- **`reset()`** — clears all state for the next session; call after `audioFilePath` has been consumed by `submitAudio`.
- **Playback finalization**: `playbackCompletionTask` is now a stored handle, cancelled by `stopPlayback()` and `reset()`. This prevents an orphaned sleep task from retaining `AVAudioPlayer` and from clearing a newer playback session after the user has already stopped or restarted audio.
- **Strict Requirement**: Never call `AVAudioSession.sharedInstance()` directly on `@MainActor`. Route all activation/deactivation through `AudioSessionCoordinator`.

### `SpectrogramActor`
- Swift `actor` at `merian/Core/Hardware/SpectrogramActor.swift`. All FFT and mel-scale arithmetic runs on a background actor thread, keeping `@MainActor` free for 60fps rendering.
- **2048-point real FFT** via Accelerate `vDSP_fft_zrip` with `vDSP_hann_window`. Wrapped in `autoreleasepool` per buffer to prevent `AVAudioPCMBuffer` Obj-C object accumulation.
- **64-bin mel scale**, 80 Hz – 16 kHz: covers the bioacoustically relevant range for bird, insect, and frog ID.
- **`process(buffer:) -> SpectrogramColumn?`** — main entry point from the tap callback; returns `nil` if FFT setup unavailable or buffer empty.
- **`snrLevel(from:) -> SNRLevel`** — rolling 96-entry noise floor history (~2 s). Thresholds: `.clipping` (peak > 0.95), `.warning` (SNR < 10 dB), `.caution` (10–20 dB), `.clear` (≥ 20 dB).
- **`reset()`** — clears the noise floor history. Called by `AudioCaptureManager.reset()` between sessions.

### `CameraManager`
- Abstracts AVFoundation via `AVCaptureDevice.DiscoverySession`, preferring `.builtInTripleCamera` on Pro devices for optical zoom support, falling back to `.builtInLiDARDepthCamera`, `.builtInDualCamera`, `.builtInDualWideCamera`, and `.builtInWideAngleCamera` in that order. Depth data via `AVCaptureDepthDataOutput` is attached conditionally and works with any device in the list that supports it.
- Activated via `.handleActivePhase()` calls in `MerianApp.swift`.
- Governs `subjectDistanceInMeters`, auto-focus thresholds, thermal bounds, and frame drops on a dedicated `DispatchQueue(label: "camera.session")`.
- Avoids Accelerate `vImage` CPU starvation during paused states via an atomic `nonisolated(unsafe) private var activeInferencePaused` boolean, synchronized with the `@MainActor` preference boundary. When set, this triggers an early return in `captureOutput`, halting the histogram allocation pipeline and preserving battery and thermals whenever the Viewfinder AI is paused.
- **Deferred Mutex Unlocks**: Mitigates AVFoundation buffer leaks and device thread lockouts by placing `defer { device.unlockForConfiguration() }` and `defer { CVPixelBufferUnlockBaseAddress }` guards across all hardware control paths.

### `EnvironmentContextManager`
- Manages the `EnvironmentContext` struct, which is defined in `merian/Core/Hardware/EnvironmentContext.swift` as a plain data model with `location`, `locationName`, `weatherCondition`, and `weatherTemperature` fields.
- Maintains two data sources without triggering UI rerenders:
  - **CoreLocation**: Caches and updates `CLLocationCoordinate2D`, `altitude`, and `course`.
  - **WeatherKit**: Fetches hyper-local `temperature` and `condition` to supplement inference payloads.
- Updates are gated by a `cacheThreshold` to limit unnecessary location and weather polling.
- **Concurrent geocode + weather**: In `fetchDeferredContext`, `reverseGeocode(location:)` is launched as an `async let` child task before the `weatherService.weather(for:)` call begins. Both I/O operations — typically 300–800 ms each — run in parallel, cutting total context-fetch latency by 300–1000 ms per shutter press.

### `HapticManager`
- Governs `UIImpactFeedbackGenerator` tactile feedback.
- Generates `NotificationFeedback` for success/failure workflows without requiring `AudioToolbox` imports.
- **Strict Requirement**: Never use `UIImpactFeedbackGenerator` or `.sensoryFeedback` modifiers directly in views. Always route haptic feedback through `HapticManager.shared` API methods (e.g., `triggerSheetSpring()`, `triggerLightImpact()`) to ensure the user's `isHapticsEnabled` preference is respected globally.
- **Analysis-phase haptic map**: Four strategic touchpoints span the analyzing experience in `InferenceEngine` and `InsightHeader`:
  - `triggerLightImpact(intensity: 0.3)` — fires when `isVisionStreaming` flips to `true` (Vision pipeline onset).
  - `triggerSelectionPulse()` — fires on every badge phrase rotation tick after the first (every 2.3 s).
  - `triggerLightImpact(intensity: 0.5)` — fires in `InsightHeader.onAppear` when the common name title animates in from the analyzing state (peak reveal moment).
  - `triggerSelectionPulse()` — fires after the 700 ms Vision→Gemini paragraph crossfade delay, marking the hand-off from local to cloud reasoning.

### `PushNotificationManager`
- Encapsulates `UNUserNotificationCenter` operations on the `@MainActor` thread.
- Polls `authorizationStatus` to keep the local `@AppStorage(UserDefaultsKeys.isPushNotificationsEnabled)` flag in sync with the OS Settings state. If a user revokes permissions externally, the local flag is corrected asynchronously via `Task { @MainActor in }` (not `DispatchQueue.main.async`) to maintain Swift 6 strict concurrency compliance.
- Configured as the `UNUserNotificationCenterDelegate`. Injects `scanId` values into `.userInfo` payloads so background offline completions can surface notifications over the lock screen.
- **Rich Media & Categorization**: Registers custom categories (`INFERENCE_COMPLETE`) with Interactive Actions ("View Details", "Share Discovery") and natively attaches species thumbnail images for premium lock-screen previews.
- **Delivery Control**: Uses `threadIdentifier` (`inference_complete_thread`) to prevent lock-screen explosion when sequentially scanning subjects, and elevates deliveries to `.timeSensitive` automatically (iOS 15+) for priority pass-through during field-use.
- **Deduplication**: `sendInferenceCompleteNotification` guards against duplicate notifications using a session-scoped `notifiedScanIds: Set<String>`. The first call for a given scan ID proceeds and inserts the ID; subsequent calls for the same scan return immediately. The `UNNotificationRequest` uses `"inference_\(scanId)"` as its identifier rather than a fresh `UUID`, so even if two requests reach `UNUserNotificationCenter` concurrently (not possible on `@MainActor` but defensive), the OS deduplicates them. This prevents the user receiving two "Analysis complete" alerts when both the live inference path and the background URLSession path complete for the same scan in close succession.
- **Safe Deep Linking**: Intercepts deep link taps from notification actions and routes the UI directly to the relevant `InsightSheet`. It rigorously filters out `UNNotificationDismissActionIdentifier` to ensure users who simply swipe away a notification are not forcefully navigated when they next open the app.
- **Context-Aware Foreground Suppression**: `willPresent(_:withCompletionHandler:)` reads the `suppressInferenceBanners` UserDefaults flag to decide foreground banner delivery. When `true` (the insight sheet is visible), inference notifications are delivered silently via `completionHandler([])` — the user can already see the result in the sheet. When `false` (the user is in the library, camera, profile, or elsewhere), the banner is allowed: `completionHandler([.banner, .sound, .list])`. Achievement notifications bypass this flag and are always displayed. `InsightSheetView` sets `suppressInferenceBanners = true` on `onAppear` and clears it on `onDisappear`, so the flag precisely tracks insight sheet visibility. **Both notification call sites (`InferenceEngine` and `OfflineQueueManager+URLSession`) schedule notifications unconditionally — without any `applicationState != .active` guard.** Foreground suppression is delegated entirely to this `willPresent` path; background delivery bypasses the delegate and is shown automatically by the OS.
- **App Icon Badge Synchronization**: Exposes `setBadgeCount(_:)` to mirror the application's `hasUnseenScan` state into the OS-level app icon badge count, seamlessly providing a visual indicator on the Home screen. This cleanly branches between modern `UNUserNotificationCenter` APIs (iOS 16+) and standard `UIApplication` fallbacks, keeping inference alerts directly coupled to the user's scan-viewing behavior.

## AI & Offline Synchronization

### `InferenceEngine`
- The core processing unit in `merian/Core/AI/`.
- Dispatches sensor data via `CaptureTelemetry` — forwarding `depthScaleText`, `deviceLocale`, `currentMonth`, and coordinate state — to the active Supabase Edge path (`MerianNetworkClient.identifyMultiModal` / `buildMultiModalRequest(...)`).
- Selects between `gemini-2.5-flash` and `gemini-2.5-pro` based on the user's subscription tier, then maps the taxonomy strings from the response back to local model properties.
- Maps ephemeral telemetry metadata (`gpsLatitude`, `gpsLongitude`, `gpsElevation`, `weatherCondition`, `weatherTemperatureF`, `locationName`) into the parsed `SpeciesData` model, abstracting this detail from the Edge runtime and making it consistent across live and offline inference paths.
- On network failure, routes the payload to `OfflineQueueManager` and triggers the Graceful Degradation UI state.
- **Post-inference carousel handoff**: On a successful result, `validHistoricImagePaths` is set from the on-disk paths returned by `InferenceProcessingActor.parseAndSave` *before* `speciesData` is assigned. This ensures the insight sheet carousel always has the user's saved image available on first render — the reference image is never the only visible page when the sheet opens. After `speciesData` is set, `activeImageData` is cleared to release the single in-memory display frame.
- **TaskGroup Retain Cycles (`InferenceEngine`)**: Replaced implicit, strong `[self]` captures across `withTaskGroup` blocks with robust `@MainActor [weak self]` guard unwrapping. If network tasks stall, the engine immediately releases all in-flight state, enabling dynamic RAM scavenging and eliminating implicit zombie executions bounding the `InferenceEngine` layer.
- **Unconditional Local Notifications**: Dispatches a local "Analysis Complete" push notification upon successful inference without any `applicationState != .active` guard. `PushNotificationManager.willPresent` handles foreground suppression by reading `suppressInferenceBanners` — set to `true` by `InsightSheetView` while visible. This ensures notifications fire when the user is in the library grid (and the banner is shown), but are silently delivered when the user is already on the insight sheet viewing results.
- **`activeScanId` lifecycle**: `activeScanId` is set at `analyze()` start to the caller-supplied scan ID, and is cleared in the inference task's `defer` block alongside `isProcessing = false`. Clearing it on pipeline exit (success, failure, or cancellation) ensures the background offline path cannot hydrate a stale engine after the live pipeline has exited. For the success path this is a no-op (the background path skips when `speciesData.scanId != nil`). For the failure path it bounds the hydration window to the interval when `isProcessing == true`.
- **Dedicated external API session (`externalAPISession`)**: Wikipedia and GBIF hydration calls use a `private static let externalAPISession` with its own `URLSessionConfiguration` (`timeoutIntervalForRequest = 5`, `timeoutIntervalForResource = 10`, `httpShouldSetCookies = false`, `urlCache = nil`). This session is isolated from the Supabase session so TLS pinning for `*.supabase.co` is never applied to public third-party endpoints, and the connection pool is independent from the Supabase auth pool.

**Multi-File Structure**: The engine is split across three files:
- `InferenceEngine.swift` — the main engine with its public API unchanged.
- `InferenceProcessingActor.swift` — a dedicated actor for base64 encoding and response parsing/persistence. It receives all data as parameters and has no access to `InferenceEngine`'s private state. It exposes two methods: `encodeBase64(compressedDatas:)` and `parseAndSave(resultData:telemetry:modelContext:compressedDatas:)`. `parseAndSave` returns a `ParseAndSaveResult` struct with `mappedData: SpeciesData?`, `isNewDiscovery: Bool`, and `savedPaths: [String]` — the saved paths are local file paths written by `FileIOActor.shared.writeTemporaryImages`, surfaced so `InferenceEngine` can populate `validHistoricImagePaths` immediately without a separate round-trip.
- `InferenceEdgeDTOs.swift` — contains `APIError`, `EdgeResponseWrapper`, `EdgeResponse`, and nested types (`Taxonomy`, `Insight`, `Diagnostic`). These were previously nested inside `InferenceEngine`.

### `OfflineQueueManager`
- Manages background `URLSession` uploads, queuing imagery to the local Documents Directory when the device is off-grid.
- Registers background handlers in `AppDelegate` so `URLSession` callbacks complete independently from the main UI thread.
- Uses `BackgroundTaskWrapper.execute(name:operation:)` to wrap operations in `UIBackgroundTaskIdentifier` windows, preventing system suspension mid-flight.
- **Multi-Capture Persistence**: Iterates `[Data]` arrays asynchronously, writing each file to `.documentsDirectory` via `FileIOActor` and appending paths to `localImagePaths`. This ensures multi-capture bundles are not corrupted by iOS suspension before connectivity is restored.
- **Recursive Queue Draining**: The `URLSession` delegate calls `syncPendingScans()` recursively when a completed batch detects `unsyncedItemsCount > 0`, draining the queue automatically without user intervention.
- **Orphaned `.uploading` Reconciliation**: `markScansAsUploading` runs before `generateUploadURLs`. If the URL-generation request fails (e.g. task cancelled when the user backgrounds), any scans already transitioned to `.uploading` are reset to `.pending` before the retry is scheduled — `syncPendingScans` only fetches `.pending` records, so without this reset they would be stuck. Additionally, `replayInferenceForUploadedScans` cross-references live URLSession tasks on every call to catch orphans that bypass the catch block.
- **`MerianConfig` Batch Limits**: `uploadBatchSize` (5) and `pendingScanFetchLimit` (50) are governed by `MerianConfig` constants rather than inline literals.
- **Concurrent upload staging (`withTaskGroup`)**: File copy and `URLSession.uploadTask` creation for each image in a batch are fanned out via `withTaskGroup`. Pre-flight guards (URL validation, file existence, tombstoning) remain serial; only the NVMe write (`FileManager.copyItem`) and task creation are concurrent. For a 3-image scan this eliminates 500 ms–2 s of head-of-line blocking before the OS background session takes over.
- **Quota Enforcement at Enqueue Time**: `insertAndPersistRecord` calls `UsageManager.shared.canPerformScan(isProActive: false)` before inserting a new `OfflineQueuedScan`. If the quota is exhausted the scan is rejected and any files written to disk are cleaned up atomically — `AppTelemetry.trackOfflineQueued()` is **not** fired on rejection. If the check passes, `UsageManager.shared.consumeScan()` is called immediately so the token is consumed before the record enters SwiftData. `syncPendingScans` has no quota checks or `consumeScan` calls — every scan in the queue at upload time is already paid for and uploads unconditionally regardless of `freeScansRemaining`.
- **Sync Phase Transitions**: Drives `SyncStateManager` through `.uploading(count:)` → `.inferencing` → `.finalizing` → `.idle` as the pipeline progresses.

### `SyncStateManager`
- `@MainActor @Observable` singleton exposing the current sync phase to UI components.
- Driven exclusively by `OfflineQueueManager` — no other code should write to it.
- Replaced the original `isSyncing: Bool` + `pendingUploadCount: Int` properties with a `SyncPhase` enum:
  - `.idle` — no activity
  - `.uploading(count: Int)` — image files are being PUT to R2 staging
  - `.inferencing` — the Gemini Edge function is running
  - `.finalizing` — writing `LocalScanRecord` and cleaning up queue entries
- Backward-compatible computed shims (`isSyncing`, `pendingUploadCount`) are preserved for existing consumers.
- **Write API** — three completion methods with distinct semantics:
  - `beginSync(itemCount:)` / `beginInferencing()` / `beginFinalizing()` — phase transitions
  - `completeSync()` — inference pipeline completion; decrements `activeInferenceCount`, transitions to `.idle` only when count reaches zero. Use exclusively from `processInferenceDownloadResult`.
  - `completeUploadPhase()` — upload-path completion (empty queue, URL generation failure, etc.); transitions to `.idle` only if no inference is in flight, without touching the count. Use from all `syncPendingScans` early-exit paths and upload task settlement.
  - `forceIdle()` — hard reset; zeros `activeInferenceCount` and sets `phase = .idle` immediately. Use on connectivity loss where all in-flight tasks are cancelled.

### `ScanRepository`
- `@MainActor` singleton facade over `OfflineQueueManager` and SwiftData, decoupling UI and ViewModels from `ModelContext` and queue internals.
- Injected at startup via `configure(with:)`, which also seeds the "Favorites" collection if absent.
- **`configure(with:)` — non-blocking launch**: The Favorites collection seed is deferred to `Task { @MainActor in }` so `configure` returns immediately without performing any SQLite I/O on the synchronous launch path. On large libraries, the original synchronous `FetchDescriptor<ScanCollection>()` blocked the main thread before the first frame rendered. The deferred fetch also uses `fetchCount` with `#Predicate { $0.name == "Favorites" }` + `fetchLimit = 1` — O(1) regardless of collection count.
- **`syncHistoricalScansDown`**: Before fetching cloud collections, calls `BackgroundDatabaseActor.pushCollectionsToEdge()` to upload all local collections first. This push-before-pull ordering prevents the reconciliation delete pass from wiping collections created offline or before authentication. After the push, fetches cloud scan and collection history with pagination (`MerianConfig.historicalSyncPageSize`, `MerianConfig.collectionsSyncPageSize`), then delegates all reconciliation to a single `HistoricalDatabaseActor.reconcileAllHistoricalData(responses:collections:)` call. **Never reorder the push and pull** — reversing them causes unsynced local collections to be treated as obsolete and deleted on the next app launch.
- **`eradicateScan`**: Commits database changes (delete record, insert cloud deletion task) before touching disk. File deletion via `FileIOActor.shared.deleteImages(at:)` runs only after a successful `modelContext.save()`, preventing partial-failure inconsistency.
- **`ingestScans` timestamp guard**: During historical cloud sync, each scan's `timestamp` string is parsed via `DateUtilities.iso8601FractionalFormatter` (with whole-second fallback). If both formatters fail on a malformed timestamp, the scan record is **skipped with a logged error** rather than defaulting to `Date()` (which would fabricate a current timestamp and make the scan appear as "Today", corrupting sort order). Caller sees a `MerianLog.data.error("ingestScans: unparseable timestamp ...")` in the logs for affected scan IDs.

### `ScansManager` (Search Indexing)
- Offloads search index rebuilds from the main `.onChange()` thread to avoid stalls on large scan lists.
- Uses an O(1) delta update pattern: computes `oldIds.subtracting(newIds)` and `newIds.subtracting(oldIds)` via Swift Set operations, updating only the affected entries rather than rebuilding the full index on every change.
- **Dynamic Hot-Swapping**: To prevent stale caches when users mutate inner properties of existing scans (e.g., adding `customTags`), `ScansManager` listens for `NSNotification.Name("ScanRequiresSearchIndexUpdate")`. This explicitly triggers a targeted isolated re-evaluation via `SearchDatabaseActor`, updating the string index in under 10ms without an app reboot.
- **Dual-path indexing**: Full rebuilds extract `RawScanSnapshot` values from the already-resident `allScans` array on `@MainActor`, then build both `SearchableScan` payloads and a detached `SearchIndexSnapshot`. Incremental inserts stay on `SearchDatabaseActor`, but fetch their delta through one batch `FetchDescriptor` (`WHERE id IN (...)`) rather than faulting records one-by-one; the main actor then upserts only the changed documents into the existing snapshot.
- **Lightweight lookup caches only**: `ScansManager` keeps `[String: Int]` index positions, `[String: ScanSortPrimitive]` sort snapshots, and a `sortedAllScanIDsCache` keyed by `ScanSortOption.rawValue`. It deliberately does **not** retain a parallel `[String: LocalScanRecord]` dictionary, so SwiftData remains free to fault heavyweight model state as memory pressure rises.
- **`searchString` composition**: Each scan's search index string is a robust concatenation of `commonName + scientificName + ecologyType + semanticTags + taxonomyClass + taxonomyOrder + taxonomyFamily + commonGroupName + aiReasoning + locationName + habitatDescription + weatherCondition + lifeStage + reproductiveCondition + similarSpecies.joined() + iucnRedListStatus + hazardType + ecologicalInteractions`. The `commonGroupName` is derived by `SearchDatabaseActor.commonGroupName(for:)`, which maps Latin class names to plain-English synonyms (e.g. `"aves"` → `"bird birds avian"`). Combined with the AI's natural language reasoning and specific telemetry (weather, ecosystem variables, and locations), casual semantic queries like "small bird", "rainy day", "juvenile", or textual habitat traits effortlessly filter the index without strict taxonomy matches.
- **Indexed query path**: `SearchIndexSnapshot` maintains three bounded in-memory indexes: exact word terms, bigrams, and trigrams. Query tokens are normalized through `SearchIndexTokenizer`, then `SearchFilterActor` intersects posting lists to narrow candidates before performing the final `searchString.contains(...)` verification. This keeps substring semantics intact (`"yard"` still matches `"backyard"`) without scanning the entire library for every keystroke.
- **Category bucketing**: Category filters (`Plants`, `Fungi`, `Birds`, etc.) are precomputed into `SearchCategoryBucket` posting lists inside the snapshot, so category-only searches never re-evaluate taxonomy on every document.
- **`semanticTags` composition**: Assembled at write time in `BackgroundDatabaseActor` and `ScanRepository` as `[commonName, scientificName] + colors + groupTags`. `groupTags` are the 1–5 broad-to-specific categorical labels (e.g. `["animal", "bird", "songbird"]`) sourced from `species_dictionary.group_tags` — generated once per species by a background Gemini Flash call and returned in the `/identify` response on cache hit. `group_tags` is a `TEXT[]` column on `species_dictionary`, not `scans`.
- **Detached Primitive Sort Engine**: `ScansManager` maps pure `@Model` objects into `ScanSortPrimitive` arrays before offloading large sorts to `Task.detached`. The "no query / all categories" path caches sorted ID arrays per sort option, so repeated sort changes and query clears do not rebuild the same full-library sort every time.

### `ArchiveManager` (Archive Safety Protocol)
- Background worker that protects Free tier user data against the targeted 90-day Cloudflare R2 domesticated purge (`00008_auto_purge_domesticated_cron.sql`).
- Polls available disk space via `getAvailableDiskSpace()`. Storage threshold and rescue window are driven by `MerianConfig` (`diskSpaceThreshold = 500 MB`, `archiveRescueWindowStartDays = 80`, `archiveRescueWindowEndDays = 88`).
- `evaluateAndRescueAgingScans` queries SwiftData for `.isLocallyArchived == false` records older than 80 days. It runs once per day via `.handleActivePhase()` lifecycle hooks. To avoid RAM spikes during batch rescues, the system skips `.data(from:)` array loading. Instead, it queries the remote database for `image_storage_urls`, then streams each binary via `URLSession.shared.download(from:)`, moving the temp file to the Documents directory with `FileManager.default.moveItem`. SwiftData stores only the relative `filename` string rather than the full `fileURL.path`, preventing path breakage caused by iOS randomizing container UUIDs across reboots and app updates.
- **N+1 Query Prevention**: Extracts all `.identifier` strings upfront and sends a single `.in("id", ...)` PostgREST query, pulling all storage relationships in one round-trip.

### `MerianConfig`
- Centralized enum (`Core/Utilities/MerianConfig.swift`) holding all policy constants for the data and AI layers.
- A policy change requires exactly one edit, with no risk of values diverging across files.
- Referenced by `OfflineQueueManager`, `ScanRepository` (`HistoricalDatabaseActor`), `ArchiveManager`, `CaptureWorkspaceViewModel`, and `InferenceEngine`.

| Constant | Value | Consumer |
|---|---|---|
| `uploadBatchSize` | 5 | `OfflineQueueManager+Sync` |
| `pendingScanFetchLimit` | 50 | `OfflineQueueManager+Sync` |
| `historicalSyncPageSize` | 200 | `ScanRepository` |
| `collectionsSyncPageSize` | 100 | `ScanRepository` |
| `ingestCheckpointInterval` | 50 | `HistoricalDatabaseActor` |
| `diskSpaceThreshold` | 500 MB | `ArchiveManager` |
| `archiveRescueWindowStartDays` | 80 | `ArchiveManager` |
| `archiveRescueWindowEndDays` | 88 | `ArchiveManager` |
| `imageCompressionQuality` | 0.85 | `Capture`, `CaptureWorkspaceViewModel` |
| `visionConfidenceThreshold` | 0.65 | `InferenceEngine` (Vision pre-classifier) |
| `visionConfidenceMargin` | 0.15 | `InferenceEngine` (margin guard vs. second-best) |
| `scanningPhaseSubjectDelayNs` | 1.5 s | `InferenceEngine` (delay before subject-specific phrases replace generic series) |
| `scanningPhaseRotationIntervalNs` | 2.3 s | `InferenceEngine` (between phase phrases) |

### `UserDefaultsKeys`
- Centralized enum (`Core/Utilities/UserDefaultsKeys.swift`) holding all `UserDefaults` / `@AppStorage` key strings.
- Prevents silent key mismatches between write sites (`UserDefaults.standard.set`) and read sites (`@AppStorage`, `UserDefaults.standard.bool(forKey:)`).
- **Do not inline string literals for these keys anywhere in the codebase.** Always reference the constant.

| Constant | Key string | Sites |
|---|---|---|
| `hasUnseenScan` | `"hasUnseenScan"` | `MainTabBar` (read), `Analysis` (write — guarded: only written when `activeSheet != .insight`, preventing a false-positive indicator while the user is actively viewing the result), `CameraSheetRouter` (clear) |
| `isPushNotificationsEnabled` | `"isPushNotificationsEnabled"` | `NotificationSettingsView`, `PushNotificationManager`, `InferenceEngine`, `OfflineQueueManager+URLSession` |
| `suppressInferenceBanners` | `"suppressInferenceBanners"` | `CaptureWorkspaceViewModel` (write), `PushNotificationManager` (read) |
| `isLiveInferencePaused` | `"isLiveInferencePaused"` | `CameraSettingsView`, `CameraManager` |
| `invertZoomDirection` | `"invertZoomDirection"` | `ZoomSliderView`, `CameraPreviewView` (pan gesture), `CameraSettingsView` |
| `zoomSideLeft` | `"zoomSideLeft"` | `ZoomSliderView`, `MainOverlayView`, `CameraSettingsView` |
| `zoomSliderVisible` | `"zoomSliderVisible"` | `ZoomSliderView`, `CameraSettingsView` |
| `needsCollectionSync` | `"needsCollectionSync"` | `OfflineQueueManager+Sync` (write on enqueue, clear on success), `ScanRepository` (read/clear during historical sync) |

## Media & Image Processing

### `LocalImageLoader`
- A Zero-OOM actor governing remote image fetches, APFS extraction, and thundering-herd cache coalescing.
- Prevents redundant remote fetches using tracked `Task` closures off the `@MainActor`.
- **Detached Task Bounds**: Wraps core OS disk and network execution through a strictly limited `DispatchSemaphore(value: 4)` pipeline constraint. This ensures excessive detached closures do not cause ImageIO over-subscription JetSam panics during high-speed multi-item view grid scrolls. 
- **Isolated media session**: `mediaSession` uses `httpMaximumConnectionsPerHost = 4`, `httpShouldSetCookies = false`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, and `urlCache = nil`. This prevents remote thumbnail fetches from bloating the shared URL cache or starving the decode semaphore with a wider connection fan-out than the downsampler can sustain.
- Supports fallback fetching: loops natively through comma-separated URLs via Zero-OOM `ImageDownsampler` bounds.
- I/O helpers (`loadLocal`, `fetchRemote`) are `static nonisolated` — prevents `Task.detached` from re-entering the actor executor mid-operation and keeps all file/network work on the background thread pool.

### `SimilarSpeciesImageFetcher`
- `@Observable` decoupled worker for resolving Wikipedia and GBIF encyclopedic image assets.
- Explicitly delegates stream rendering to `LocalImageLoader` using standard string URLs, rather than directly inflating raw `UIImage(data:)` blobs, protecting the JetSam boundaries and unifying the global caching layer.


## Networking

### `MerianNetworkClient`
- Routes all Deno function endpoints via `MerianEnvironment.supabaseUrl`.
- Centralizes JWT validation in `performAuthenticatedRequest`, which handles authentication for all five public endpoints.
- Calls `getValidAuthHeaders()` with `try` (not `try?`) so authentication errors propagate to callers rather than being silently dropped. Previously, using `try?` made network failures impossible to diagnose.
- Extracts `DeviceIdentityManager.shared.deviceId` without depending on arbitrary session state.
- Traps `.401 Unauthorized` responses in `performAuthenticatedRequest` by delegating to `SupabaseManager.shared.getValidAuthHeaders()`, which handles Ghost session refresh.
- **`endpointURL(_:) throws -> URL`**: All Edge function URL construction goes through this private helper. It throws `MerianError.invalidURL` if `supabaseUrl` is misconfigured, rather than crashing the process with a force-unwrap (`URL(string: "...")!`). All 9 endpoint call sites (`identify`, `enrich-scan`, `generate-upload-urls`, `delete-scan`, `safe-delete`, `request-export-dwca`, `flag-issue`, `block-user`) use this helper.
- **Dedicated Supabase `URLSession`**: A private `lazy var session` handles all Supabase Edge and R2 calls. Configuration: `timeoutIntervalForRequest = 30`, `timeoutIntervalForResource = 90` (hard cap — Gemini cannot bypass this regardless of the per-request timeout), `httpMaximumConnectionsPerHost = 6`, `httpShouldSetCookies = false`, `urlCache = nil`. TLS pinning via `MerianTLSDelegate` is applied to `*.supabase.co` only. **Media and external API calls use their own isolated sessions** (never `URLSession.shared`): `LocalImageLoader`, `ArchiveManager`, `ArchiveDatabaseActor`, and `InsightMediaExportManager`/`ExportProcessingActor` each declare a `private static let mediaSession` (30 s / 300 s timeouts); `SimilarSpeciesImageFetcher`, `InferenceEngine`, and `GBIFHeatmapMapView` declare a `private static let externalAPISession` (10 s / 30 s timeouts) for Wikipedia/GBIF best-effort enrichment fetches.
- **TLS certificate pinning (`MerianTLSDelegate`)**: A private `URLSessionDelegate` validates the server certificate chain for `*.supabase.co`. The check walks the full chain (leaf → intermediate → root): a connection is accepted if **any** certificate in the chain matches a pinned hash. This means the intermediate CA hash acts as a genuine fallback across leaf rotations, not just a backup placeholder. `pinnedCertHashes` contains two active hashes: the leaf cert (`OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=`) and the intermediate CA (`HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=`). Other hosts (e.g. R2) fall through to default ATS validation. Pinning is skipped in `DEBUG` builds. **Rotation runbook**: before the leaf expires, compute the new hash with `openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64`, add it to the set alongside the current one, ship the update. Remove the stale hash after the old cert has expired everywhere. The intermediate CA hash only needs updating if Supabase migrates CAs.

### Edge Network Operations (`S3` & `PostgreSQL` Bulk Insertions)
- **Centralized Cloudflare R2 Operations (`_shared/aws.ts`)**: `copyR2Object()` and `deleteR2Object()` are defined once and shared across `moderation`, `export-dwca`, and `revenuecat-webhook`, rather than duplicating `aws.sign(...)` headers in each.
- **Shared Diagnostic Prompts (`_shared/diagnostic.ts`)**: The AI prompting logic for `fetchDiagnosticComparison` is extracted into a shared utility, preventing 1:1 duplication between the `identify` and `enrich-scan` Edge functions.
- **N+1 Query Prevention (`sync-collections`)**: Instead of issuing sequential Supabase inserts per record, the layer collects all mappings into an array and issues a single `.insert(allMappings)` call, eliminating connection exhaustion under high collection counts.
- **Explore request guards**: Explore write endpoints now share `_shared/http.ts.parseJsonBody(...)` for object-body validation and `_shared/explore.ts.assertCanInteractWithExplorePost(...)` for the identical "post still shareable + no mutual block" gate used by comment and like flows. `syncPublicAuthorIdentity(...)` remains the single author-sync path for public writes.

### `SupabaseManager`
- Wraps GoTrue bindings and exports a unified `getValidAuthHeaders() async throws -> [String: String]` method that consolidates OAuth conditional checks (`Merian_HasAuthenticatedOAuth`) and Ghost Session regeneration (via `.identifierForVendor`).
- **`authListenerTask` handle**: `@ObservationIgnored private var authListenerTask: Task<Void, Never>?` — the auth state listener task is stored rather than fire-and-forget, consistent with the task handle pattern used across the engine layer. This allows the task to be cancelled on deinit and prevents duplicate listener registration.
- **`lastLinkedUserId` dedup guard**: `private var lastLinkedUserId: String?` — prevents double RevenueCat login and double PostHog identify on cold start. The Supabase SDK emits two auth events per session restore (local cache read + server validation); this guard skips the second event for the same user ID so external identity systems are only notified once per session.
- **`ghostSessionTask` single-flight**: `@ObservationIgnored private var ghostSessionTask: Task<Void, Never>?` — serializes anonymous session creation across all callers. This closes the suspension-window race where multiple `getValidAuthHeaders()` calls could each enter `initializeGhostSession()` and perform overlapping `signInAnonymously()` requests.
- **DRY OAuth Abstraction**: Apple Sign In and Google Sign In share a single `private func finalizeOAuthLogin` path, removing the duplicate `.linkIdentityWithIdToken` / `.signInWithIdToken` logic that previously existed in both flows.
- **`keyWindowAnchor()` helper**: A private `keyWindowAnchor() -> ASPresentationAnchor` method was extracted to remove the identical implementation that was previously copy-pasted into two separate `presentationAnchor` methods.
- **Deduplicated anonymous sign-in**: The two identical anonymous sign-in code paths were collapsed into a single `isSessionMissing` check, removing the duplicate `signInAnonymously()` block.
- Maps Apple and Google OAuth hooks to migrate Ghost User accounts, calling `RevenueCatManager.shared.linkWithSupabase()` to align payment state.

### `KeychainManager`
- **`baseQuery(for:)` helper**: A private `baseQuery(for key: String) -> [String: Any]` method builds the base `[kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]` dictionary. This was previously duplicated verbatim in all three methods (`set`, `bool`, `removeObject`).
- **`migrateFromUserDefaults()`**: The `init` migration logic was extracted into a named method for clarity.

## Events & Circuit Breaking

### `AppEventPublisher`
- Lives at `Core/Utilities/AppEventPublisher.swift`. `@MainActor final class` with a `PassthroughSubject<AppEvent, Never>` publisher and a `static let shared` singleton.
- Replaces `NotificationCenter` broadcasts with strongly-typed `AppEvent` cases:
  - `.triggerPaywall` — dispatched when the scan quota is exhausted; `CaptureWorkspaceView` listens and presents `PaywallView`.
  - `.appDidEnterActivePhaseWithScan(scanId:)` — dispatched from a push notification tap to deep-link to a specific scan's insight sheet.
  - `.appDidEnterBackgroundPhase` — dispatched when the app enters the background phase; insight sheet dismissal and inference teardown listen here. Fires on background (not inactive) so system overlays (e.g. the photo library access prompt) do not inadvertently close the sheet.
  - `.requestIdentifyNatureIntent` — dispatched by Siri/OS App Intents to jump to the camera viewfinder.
  - `.requestRecallLastFindIntent` — dispatched by Siri/OS App Intents to open the last scan's insight sheet.
  - `.triggerRefinement(record:)` — dispatched from `BiologicalView` when the user requests re-inference on an existing scan with supplementary images; `CaptureWorkspaceView` listens via `AppEventPublisher.shared.publisher.sink`.
- Registered in `AppDIContainer` as `var appEventPublisher = AppEventPublisher()`. **Not environment-injected** — call sites access it via `AppDIContainer.shared.appEventPublisher` or `AppEventPublisher.shared` directly.

### `CircuitBreakerManager`
- Lives at `Core/Security/CircuitBreakerManager.swift`. `@MainActor @Observable final class` with a `static let shared` singleton registered in `AppDIContainer`.
- Exposes `isCircuitTripped: Bool` — when `true`, outbound inference requests should be skipped to avoid hammering a failing edge endpoint.
- **Trip logic**: `recordFailure()` increments a consecutive-failure counter. After 3 consecutive failures (`failureThreshold`), `tripCircuit()` sets `isCircuitTripped = true` and starts a 15-minute cooldown `Timer`. On cooldown expiry, `resetCircuit()` clears the trip and the counter.
- **Reset logic**: `recordSuccess()` zeroes the counter and resets the circuit if it was tripped, allowing the next request to proceed normally.
- **Usage**: Callers in `InferenceEngine` and `OfflineQueueManager` should call `recordFailure()` on unrecoverable network errors and `recordSuccess()` on a successful inference response. Gate new inference attempts behind `!circuitBreakerManager.isCircuitTripped`.

## Telemetry & Billing

### `RevenueCatManager`
- Manages `isProActive` state.
- Handles `.purchaserInfo()` callbacks and connects to the `revenuecat-webhook` Edge function.

### `UsageManager`
- Lives at `Core/Analytics/UsageManager.swift`. Enforces the daily free-tier scan quota.
- `canPerformScan(isProActive:) -> Bool` — returns `isProActive || freeScansRemaining > 0`. Checked at two pre-scan gates only: `Capture.swift` (camera shutter) and `handlePhotoPickerSelection` (photo library picker). Network failures in `InferenceEngine` never trigger the paywall — they surface an error state and refund the token.
- `consumeScan()` — called once at enqueue time inside `OfflineQueueManager.insertAndPersistRecord`, before the `OfflineQueuedScan` record is inserted. Every scan that enters the queue is already paid for; `syncPendingScans` has no quota checks.
- `refundScan()` — restores the consumed token if inference fails unrecoverably (task cancellation, JSON decoding failure, network error).
- Grants 2 free daily scans via `UserDefaults` keyed against `DeviceIdentityManager.shared.deviceId`. Resets limits at calendar day boundaries via `evaluateDailyRefresh()`, called from `AppDIContainer.handleActivePhase()` on foreground transitions.
- **Debug-only override**: In `DEBUG` builds, setting the `MERIAN_DISABLE_FREE_SCAN_LIMIT=1` scheme environment variable makes `canPerformScan()` always return `true`, skips quota mutation in `consumeScan()` / `refundScan()`, and emits a one-time `MerianLog.general.warning(...)` console message. This keeps local development unblocked without reintroducing a production hardcoded bypass.
- Full contract documented in [02-revenue-and-identity.md](../features-and-hardware/02-revenue-and-identity.md#usage-limits-usagemanager).

### `SocialGuardManager`
- Lives at `Core/Security/SocialGuardManager.swift`. Manages a persistent local `Set<String>` of blocked user UUIDs (`blockedUserIds`).
- Updates UI blocking state across Discovery feeds optimistically (immediately on the local set), then asynchronously flushes the UUID to the `/block-user` Edge node via `MerianNetworkClient`.
- Automatically reverts the block if the Edge API returns an error, restoring the previous set state.
- Full contract documented in [02-revenue-and-identity.md](../features-and-hardware/02-revenue-and-identity.md#trust--safety-socialguardmanager).

### `GamificationManager`
- Lives at `Core/Analytics/GamificationManager.swift`. `@MainActor @Observable` singleton that persists lightweight gamification state in `UserDefaults`.
- `unlockedSpeciesCount` — incremented each time `recordNewSpeciesDiscovered()` is called (by `InferenceEngine` when `isNewDiscovery == true`).
- `hasFireflyBadge` — unlocked when `unlockedSpeciesCount >= 5`; drives the Terrarium Rive model firefly animation.
- `unlockedAchievements: Set<String>` — type keys of all completed awards, persisted across sessions.
- `evaluateAchievementsForNotifications(awards:)` — called after `ProfileDatabaseActor.calculateAwards()` completes after every inference. Checks for newly completed awards and queues local push notifications via `PushNotificationManager`.
- Full architecture documented in [06-profile-and-gamification.md](../features-and-hardware/06-profile-and-gamification.md).

### `PostHogManager`
- Not `@MainActor` — `PostHogSDK` is thread-safe, so `configure()` genuinely runs on the background thread pool when dispatched via `Task.detached` in `MerianApp.init()`.
- Tracks `isConfigured: Bool` set at the end of `configure()`. `identifyUser()` guards on this flag and logs a warning rather than calling `PostHogSDK.shared.identify()` before setup completes — guards against a race where auth state restores before the background configure task finishes.
- Calls `reset()` on sign-out to clear the PostHog session.

## 2026-04 Hardening Updates

- `InferenceEngine` now treats pending background writes as generation-scoped work. Any scan reset or cancellation invalidates the old generation before the next scan can enqueue or drain background mutations.
- `AudioCaptureManager` owns full startup failure cleanup. Cancellation after `AVAudioSession` activation now still removes the input tap, stops the engine, cancels DSP work, finishes the spectrogram stream, and clears pending temp files.
- `SpeechManager` now routes every startup failure and cancellation path through `teardownAudioEngine()`, leaving no live tap, task, or stale `audioLevel` state behind, and uses the same leased `AudioSessionCoordinator` teardown model as `AudioCaptureManager`.
- `SupabaseManager` now deduplicates external telemetry linking per user session via `ensureTelemetryLinkedIfNeeded(for:)`, preventing cold-start and session-restore churn from re-triggering RevenueCat/PostHog link work repeatedly.
- `SupabaseManager` also deduplicates anonymous session creation itself via `ghostSessionTask`, preventing concurrent ghost-session re-entry while the first auth request is suspended.
