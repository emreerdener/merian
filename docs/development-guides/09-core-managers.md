# Core Application Services & Managers

Merian uses a structured singleton pattern managed through `AppDIContainer.swift`. These singletons own global application state without triggering excessive SwiftUI view rebuilds.

## Hardware Domain

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
- **Safe Deep Linking**: Intercepts deep link taps from notification actions and routes the UI directly to the relevant `InsightSheet`. It rigorously filters out `UNNotificationDismissActionIdentifier` to ensure users who simply swipe away a notification are not forcefully navigated when they next open the app.
- **Context-Aware Suppression**: Evaluates the `suppressInferenceBanners` UserDefaults flag within `completionHandler` to conditionally suppress "Analysis Complete" banners when the user is actively viewing the insight sheet (including while it is in analyzing mode). Achievement notifications bypass this suppression and are unconditionally displayed.
- **App Icon Badge Synchronization**: Exposes `setBadgeCount(_:)` to mirror the application's `hasUnseenScan` state into the OS-level app icon badge count, seamlessly providing a visual indicator on the Home screen. This cleanly branches between modern `UNUserNotificationCenter` APIs (iOS 16+) and standard `UIApplication` fallbacks, keeping inference alerts directly coupled to the user's scan-viewing behavior.

## AI & Offline Synchronization

### `InferenceEngine`
- The core processing unit in `merian/Core/AI/`.
- Dispatches sensor data via `CaptureTelemetry` — forwarding `depthScaleText`, `deviceLocale`, `currentMonth`, and coordinate state — to the Supabase Edge Node (`MerianNetworkClient.analyzeSubject`).
- Selects between `gemini-2.5-flash` and `gemini-2.5-pro` based on the user's subscription tier, then maps the taxonomy strings from the response back to local model properties.
- Maps ephemeral telemetry metadata (`gpsLatitude`, `gpsLongitude`, `gpsElevation`, `weatherCondition`, `weatherTemperatureF`, `locationName`) into the parsed `SpeciesData` model, abstracting this detail from the Edge runtime and making it consistent across live and offline inference paths.
- On network failure, routes the payload to `OfflineQueueManager` and triggers the Graceful Degradation UI state.
- **Post-inference carousel handoff**: On a successful result, `validHistoricImagePaths` is set from the on-disk paths returned by `InferenceProcessingActor.parseAndSave` *before* `speciesData` is assigned. This ensures the insight sheet carousel always has the user's saved image available on first render — the reference image is never the only visible page when the sheet opens. After `speciesData` is set, `activeDisplayDatas` is cleared to release the 2048 px display images (potentially several MB per multi-shot capture).
- **TaskGroup Retain Cycles (`InferenceEngine`)**: Replaced implicit, strong `[self]` captures across `withTaskGroup` blocks with robust `@MainActor [weak self]` guard unwrapping. If network tasks stall, the engine immediately releases all in-flight state, enabling dynamic RAM scavenging and eliminating implicit zombie executions bounding the `InferenceEngine` layer.
- **Unconditional Local Notifications**: Dispatches a local "Analysis Complete" push notification upon successful inference regardless of application state. The `PushNotificationManager` delegate is responsible for evaluating the user's active UI context to intelligently suppress the banner if they are already looking at the result.

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
- Write API: `beginSync(itemCount:)`, `beginInferencing()`, `beginFinalizing()`, `completeSync()`.

### `ScanRepository`
- `@MainActor` singleton facade over `OfflineQueueManager` and SwiftData, decoupling UI and ViewModels from `ModelContext` and queue internals.
- Injected at startup via `configure(with:)`, which also seeds the "Favorites" collection if absent.
- **`configure(with:)` — non-blocking launch**: The Favorites collection seed is deferred to `Task { @MainActor in }` so `configure` returns immediately without performing any SQLite I/O on the synchronous launch path. On large libraries, the original synchronous `FetchDescriptor<ScanCollection>()` blocked the main thread before the first frame rendered. The deferred fetch also uses `fetchCount` with `#Predicate { $0.name == "Favorites" }` + `fetchLimit = 1` — O(1) regardless of collection count.
- **`syncHistoricalScansDown`**: Before fetching cloud collections, calls `BackgroundDatabaseActor.pushCollectionsToEdge()` to upload all local collections first. This push-before-pull ordering prevents the reconciliation delete pass from wiping collections created offline or before authentication. After the push, fetches cloud scan and collection history with pagination (`MerianConfig.historicalSyncPageSize`, `MerianConfig.collectionsSyncPageSize`), then delegates all reconciliation to a single `HistoricalDatabaseActor.reconcileAllHistoricalData(responses:collections:)` call. **Never reorder the push and pull** — reversing them causes unsynced local collections to be treated as obsolete and deleted on the next app launch.
- **`eradicateScan`**: Commits database changes (delete record, insert cloud deletion task) before touching disk. File deletion via `FileIOActor.shared.deleteImages(at:)` runs only after a successful `modelContext.save()`, preventing partial-failure inconsistency.

### `ScansManager` (Search Indexing)
- Offloads search index rebuilds from the main `.onChange()` thread to avoid stalls on large scan lists.
- Uses an O(1) delta update pattern: computes `oldIds.subtracting(newIds)` and `newIds.subtracting(oldIds)` via Swift Set operations, updating only the affected entries rather than rebuilding the full index on every change.
- **Dynamic Hot-Swapping**: To prevent stale caches when users mutate inner properties of existing scans (e.g., adding `customTags`), `ScansManager` listens for `NSNotification.Name("ScanRequiresSearchIndexUpdate")`. This explicitly triggers a targeted isolated re-evaluation via `SearchDatabaseActor`, updating the string index in under 10ms without an app reboot.
- Runs extraction inside `indexingTask = Task.detached`, delegating to `SearchDatabaseActor` so identifier evaluation stays off the main thread and within JetSam memory limits. To avoid ViewModel string retentions and persistent cycles, these task boundaries actively isolate strong class captures across task suspensions.
- **Strict O(1) Fetching Rule**: Prohibits generic `try? modelContext.fetch(FetchDescriptor<LocalScanRecord>())` loads during live update batches. Instead, `SearchDatabaseActor.extractSearchablePayloads` expressly limits memory structures by mapping exact incoming delta indices through `.model(for: id)`, keeping database reads bounded sequentially.
- **`searchString` composition**: Each scan's search index string is a robust concatenation of `commonName + scientificName + ecologyType + semanticTags + taxonomyClass + taxonomyOrder + taxonomyFamily + commonGroupName + aiReasoning + locationName + habitatDescription + weatherCondition + lifeStage + reproductiveCondition + similarSpecies.joined() + iucnRedListStatus + hazardType + ecologicalInteractions`. The `commonGroupName` is derived by `SearchDatabaseActor.commonGroupName(for:)`, which maps Latin class names to plain-English synonyms (e.g. `"aves"` → `"bird birds avian"`). Combined with the AI's natural language reasoning and specific telemetry (weather, ecosystem variables, and locations), casual semantic queries like "small bird", "rainy day", "juvenile", or textual habitat traits effortlessly filter the index without strict taxonomy matches.
- **`semanticTags` composition**: Assembled at write time in `BackgroundDatabaseActor` and `ScanRepository` as `[commonName, scientificName] + colors + groupTags`. `groupTags` are the 1–5 broad-to-specific categorical labels (e.g. `["animal", "bird", "songbird"]`) sourced from `species_dictionary.group_tags` — generated once per species by a background Gemini Flash call and returned in the `/identify` response on cache hit. `group_tags` is a `TEXT[]` column on `species_dictionary`, not `scans`.
- **Detached Primitive Sort Engine**: `ScansManager` maps pure `@Model` objects into struct-based arrays `ScanSortPrimitive` to evaluate large sequence sorts across `Task.detached`. This cleanly overcomes the `Sendable` boundary required by Swift 6 inside `searchTask` execution.

### `ArchiveManager` (Archive Safety Protocol)
- Background worker that protects Free tier user data against the targeted 90-day Cloudflare R2 domesticated purge (`00008_auto_purge_domesticated_cron.sql`).
- Polls available disk space via `getAvailableDiskSpace()`. Storage threshold and rescue window are driven by `MerianConfig` (`diskSpaceThreshold = 500 MB`, `archiveRescueWindowStartDays = 80`, `archiveRescueWindowEndDays = 88`).
- `evaluateAndRescueAgingScans` queries SwiftData for `.isLocallyArchived == false` records older than 80 days. It runs once per day via `.handleActivePhase()` lifecycle hooks. To avoid RAM spikes during batch rescues, the system skips `.data(from:)` array loading. Instead, it queries the remote database for `image_storage_urls`, then streams each binary via `URLSession.shared.download(from:)`, moving the temp file to the Documents directory with `FileManager.default.moveItem`. SwiftData stores only the relative `filename` string rather than the full `fileURL.path`, preventing path breakage caused by iOS randomizing container UUIDs across reboots and app updates.
- **N+1 Query Prevention**: Extracts all `.identifier` strings upfront and sends a single `.in("id", ...)` PostgREST query, pulling all storage relationships in one round-trip.

### `MerianConfig`
- Centralized enum (`Core/Utilities/MerianConfig.swift`) holding all policy constants for the data and AI layers.
- A policy change requires exactly one edit, with no risk of values diverging across files.
- Referenced by `OfflineQueueManager`, `ScanRepository` (`HistoricalDatabaseActor`), `ArchiveManager`, `CameraViewModel`, and `InferenceEngine`.

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
| `imageCompressionQuality` | 0.85 | `Capture`, `CameraViewModel` |
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
| `suppressInferenceBanners` | `"suppressInferenceBanners"` | `CameraViewModel` (write), `PushNotificationManager` (read) |
| `isLiveInferencePaused` | `"isLiveInferencePaused"` | `CameraSettingsView`, `CameraManager` |
| `invertZoomDirection` | `"invertZoomDirection"` | `ZoomSliderView`, `CameraPreviewView` (pan gesture), `CameraSettingsView` |
| `zoomSideLeft` | `"zoomSideLeft"` | `ZoomSliderView`, `MainOverlayView`, `CameraSettingsView` |
| `zoomSliderVisible` | `"zoomSliderVisible"` | `ZoomSliderView`, `CameraSettingsView` |

## Media & Image Processing

### `LocalImageLoader`
- A Zero-OOM actor governing remote image fetches, APFS extraction, and thundering-herd cache coalescing.
- Prevents redundant remote fetches using tracked `Task` closures off the `@MainActor`.
- **Detached Task Bounds**: Wraps core OS disk and network execution through a strictly limited `DispatchSemaphore(value: 4)` pipeline constraint. This ensures excessive detached closures do not cause ImageIO over-subscription JetSam panics during high-speed multi-item view grid scrolls. 
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
- **Dedicated `URLSession`**: A private `lazy var session` replaces all `URLSession.shared` call sites. Configuration: `timeoutIntervalForRequest = 30`, `timeoutIntervalForResource = 90` (hard cap — Gemini cannot bypass this regardless of the per-request timeout), `httpMaximumConnectionsPerHost = 6`, `httpShouldSetCookies = false`, `urlCache = nil`. Both Edge function calls and R2 PUT uploads go through this session.
- **TLS certificate pinning (`MerianTLSDelegate`)**: A private `URLSessionDelegate` validates the server certificate for `*.supabase.co` against a SHA-256 hash of the leaf certificate DER. Other hosts (e.g. R2's `*.r2.cloudflarestorage.com`) fall through to default ATS validation. Pinning is skipped in `DEBUG` builds to allow MITM proxies. When `pinnedCertHashes` is empty (initial state), default ATS validation applies — populate the set using `openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64`. Include a primary hash and a backup to enable zero-downtime rotation.

### Edge Network Operations (`S3` & `PostgreSQL` Bulk Insertions)
- **Centralized Cloudflare R2 Operations (`_shared/aws.ts`)**: `copyR2Object()` and `deleteR2Object()` are defined once and shared across `moderation`, `export-dwca`, and `revenuecat-webhook`, rather than duplicating `aws.sign(...)` headers in each.
- **Shared Diagnostic Prompts (`_shared/diagnostic.ts`)**: The AI prompting logic for `fetchDiagnosticComparison` is extracted into a shared utility, preventing 1:1 duplication between the `identify` and `enrich-scan` Edge functions.
- **N+1 Query Prevention (`sync-collections`)**: Instead of issuing sequential Supabase inserts per record, the layer collects all mappings into an array and issues a single `.insert(allMappings)` call, eliminating connection exhaustion under high collection counts.

### `SupabaseManager`
- Wraps GoTrue bindings and exports a unified `getValidAuthHeaders() async throws -> [String: String]` method that consolidates OAuth conditional checks (`Merian_HasAuthenticatedOAuth`) and Ghost Session regeneration (via `.identifierForVendor`).
- **DRY OAuth Abstraction**: Apple Sign In and Google Sign In share a single `private func finalizeOAuthLogin` path, removing the duplicate `.linkIdentityWithIdToken` / `.signInWithIdToken` logic that previously existed in both flows.
- **`keyWindowAnchor()` helper**: A private `keyWindowAnchor() -> ASPresentationAnchor` method was extracted to remove the identical implementation that was previously copy-pasted into two separate `presentationAnchor` methods.
- **Deduplicated anonymous sign-in**: The two identical anonymous sign-in code paths were collapsed into a single `isSessionMissing` check, removing the duplicate `signInAnonymously()` block.
- Maps Apple and Google OAuth hooks to migrate Ghost User accounts, calling `RevenueCatManager.shared.linkWithSupabase()` to align payment state.

### `KeychainManager`
- **`baseQuery(for:)` helper**: A private `baseQuery(for key: String) -> [String: Any]` method builds the base `[kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]` dictionary. This was previously duplicated verbatim in all three methods (`set`, `bool`, `removeObject`).
- **`migrateFromUserDefaults()`**: The `init` migration logic was extracted into a named method for clarity.

## Telemetry & Billing

### `RevenueCatManager`
- Manages `isProActive` state.
- Handles `.purchaserInfo()` callbacks and connects to the `revenuecat-webhook` Edge function.

### `PostHogManager`
- Not `@MainActor` — `PostHogSDK` is thread-safe, so `configure()` genuinely runs on the background thread pool when dispatched via `Task.detached` in `MerianApp.init()`.
- Tracks `isConfigured: Bool` set at the end of `configure()`. `identifyUser()` guards on this flag and logs a warning rather than calling `PostHogSDK.shared.identify()` before setup completes — guards against a race where auth state restores before the background configure task finishes.
- Calls `reset()` on sign-out to clear the PostHog session.
