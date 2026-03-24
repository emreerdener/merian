# Core Application Services & Managers

Merian uses a structured singleton pattern managed through `AppDIContainer.swift`. These singletons own global application state without triggering excessive SwiftUI view rebuilds.

## Hardware Domain

### `CameraManager`
- Abstracts AVFoundation and binds to `.builtInLiDARDepthCamera` arrays on physical devices.
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

### `HapticManager`
- Governs `UIImpactFeedbackGenerator` tactile feedback.
- Generates `NotificationFeedback` for success/failure workflows without requiring `AudioToolbox` imports.

### `PushNotificationManager`
- Encapsulates `UNUserNotificationCenter` operations on the `@MainActor` thread.
- Polls `authorizationStatus` to keep the local `@AppStorage("isPushNotificationsEnabled")` flag in sync with the OS Settings state. If a user revokes permissions externally, the local flag is corrected asynchronously.
- Configured as the `UNUserNotificationCenterDelegate`. Injects `scanId` values into `.userInfo` payloads so background offline completions can surface notifications over the lock screen.
- Intercepts deep link taps from notification actions and routes the UI directly to the relevant `InsightSheet`.
- Calls `completionHandler([])` to suppress inference banners when the app is in the `.active` foreground state.

## AI & Offline Synchronization

### `InferenceEngine`
- The core processing unit in `merian/Core/AI/`.
- Dispatches sensor data via `CaptureTelemetry` — forwarding `depthScaleText`, `deviceLocale`, `currentMonth`, and coordinate state — to the Supabase Edge Node (`MerianNetworkClient.analyzeSubject`).
- Selects between `gemini-2.5-flash` and `gemini-2.5-pro` based on the user's subscription tier, then maps the taxonomy strings from the response back to local model properties.
- Maps ephemeral telemetry metadata (`gpsLatitude`, `gpsLongitude`, `gpsElevation`, `weatherCondition`, `weatherTemperatureF`, `locationName`) into the parsed `SpeciesData` model, abstracting this detail from the Edge runtime and making it consistent across live and offline inference paths.
- On network failure, routes the payload to `OfflineQueueManager` and triggers the Graceful Degradation UI state.

**Multi-File Structure**: The engine is split across three files:
- `InferenceEngine.swift` — the main engine with its public API unchanged.
- `InferenceProcessingActor.swift` — a dedicated actor for base64 encoding and response parsing/persistence. It receives all data as parameters and has no access to `InferenceEngine`'s private state. It exposes two methods: `encodeBase64(compressedDatas:)` and `parseAndSave(resultData:telemetry:modelContext:compressedDatas:)`.
- `InferenceEdgeDTOs.swift` — contains `APIError`, `EdgeResponseWrapper`, `EdgeResponse`, and nested types (`Taxonomy`, `Insight`, `Diagnostic`). These were previously nested inside `InferenceEngine`.

### `OfflineQueueManager`
- Manages background `URLSession` uploads, queuing imagery to the local Documents Directory when the device is off-grid.
- Registers background handlers in `AppDelegate` so `URLSession` callbacks complete independently from the main UI thread.
- Uses `BackgroundTaskWrapper.execute(name:operation:)` to wrap operations in `UIBackgroundTaskIdentifier` windows, preventing system suspension mid-flight.
- **Multi-Image Persistence**: Iterates `[Data]` arrays asynchronously, writing each file to `.documentsDirectory` via `FileIOActor` and appending paths to `localImagePaths`. This ensures multi-image bundles are not corrupted by iOS suspension before connectivity is restored.
- **Recursive Queue Draining**: The `URLSession` delegate calls `syncPendingScans()` recursively when a completed batch detects `unsyncedItemsCount > 0`, draining the queue automatically without user intervention.
- **`MerianConfig` Batch Limits**: `uploadBatchSize` (5) and `pendingScanFetchLimit` (50) are governed by `MerianConfig` constants rather than inline literals.
- **Free User Queue Cap & Quota Enforcement**: `enqueueCapture` enforces a hard cap of `UsageManager.shared.maxFreeScansPerDay` (2) queued items for free users. If the cap is reached, the new item is rejected and any files already written to disk are cleaned up atomically. `syncPendingScans` checks `canPerformScan` before starting a batch and calls `consumeScan()` once per submitted item, enforcing the daily quota through the background URLSession path. Pro users have no cap.
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
- **`syncHistoricalScansDown`**: Fetches cloud scan and collection history with pagination (`MerianConfig.historicalSyncPageSize`, `MerianConfig.collectionsSyncPageSize`), then delegates all reconciliation to a single `HistoricalDatabaseActor.reconcileAllHistoricalData(responses:collections:)` call, replacing the previous three-call actor-boundary crossing pattern.
- **`eradicateScan`**: Commits database changes (delete record, insert cloud deletion task) before touching disk. File deletion via `FileIOActor.shared.deleteImages(at:)` runs only after a successful `modelContext.save()`, preventing partial-failure inconsistency.

### `ScansManager` (Search Indexing)
- Offloads search index rebuilds from the main `.onChange()` thread to avoid stalls on large scan lists.
- Uses an O(1) delta update pattern: computes `oldIds.subtracting(newIds)` and `newIds.subtracting(oldIds)` via Swift Set operations, updating only the affected entries rather than rebuilding the full index on every change.
- Runs extraction inside `indexingTask = Task.detached`, delegating to `SearchDatabaseActor` so identifier evaluation stays off the main thread and within JetSam memory limits.

### `ArchiveManager` (Archive Safety Protocol)
- Background worker that protects Free tier user data against the Cloudflare R2 90-day purge (`00004_storage_lifecycle_sync.sql`).
- Polls available disk space via `getAvailableDiskSpace()`. Storage threshold and rescue window are driven by `MerianConfig` (`diskSpaceThreshold = 500 MB`, `archiveRescueWindowStartDays = 80`, `archiveRescueWindowEndDays = 88`).
- `evaluateAndRescueAgingScans` queries SwiftData for `.isLocallyArchived == false` records older than 80 days. It runs once per day via `.handleActivePhase()` lifecycle hooks. To avoid RAM spikes during batch rescues, the system skips `.data(from:)` array loading. Instead, it queries the remote database for `image_storage_urls`, then streams each binary via `URLSession.shared.download(from:)`, moving the temp file to the Documents directory with `FileManager.default.moveItem`. SwiftData stores only the relative `filename` string rather than the full `fileURL.path`, preventing path breakage caused by iOS randomizing container UUIDs across reboots and app updates.
- **N+1 Query Prevention**: Extracts all `.identifier` strings upfront and sends a single `.in("id", ...)` PostgREST query, pulling all storage relationships in one round-trip.

### `MerianConfig`
- Centralized enum (`Core/Utilities/MerianConfig.swift`) holding all policy constants for the data layer.
- A policy change requires exactly one edit, with no risk of values diverging across files.
- Referenced by `OfflineQueueManager`, `ScanRepository` (`HistoricalDatabaseActor`), and `ArchiveManager`.

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

## Networking

### `MerianNetworkClient`
- Routes all Deno function endpoints via `MerianEnvironment.supabaseUrl`.
- Centralizes JWT validation in `performAuthenticatedRequest`, which handles authentication for all five public endpoints.
- Calls `getValidAuthHeaders()` with `try` (not `try?`) so authentication errors propagate to callers rather than being silently dropped. Previously, using `try?` made network failures impossible to diagnose.
- Extracts `DeviceIdentityManager.shared.deviceId` without depending on arbitrary session state.
- Traps `.401 Unauthorized` responses in `performAuthenticatedRequest` by delegating to `SupabaseManager.shared.getValidAuthHeaders()`, which handles Ghost session refresh.

### Edge Network Operations (`S3` & `PostgreSQL` Bulk Insertions)
- **Centralized Cloudflare R2 Operations (`_shared/aws.ts`)**: `copyR2Object()` and `deleteR2Object()` are defined once and shared across `moderation`, `export-dwca`, and `revenuecat-webhook`, rather than duplicating `aws.sign(...)` headers in each.
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
- Manages anonymous telemetry via `.identifyUser()` across all app state transitions.
