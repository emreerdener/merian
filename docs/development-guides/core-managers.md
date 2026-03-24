# Core Application Services & Managers

Merian relies heavily on a structured Singleton paradigm bound inside the strict `AppDIContainer.swift` file. These singletons control global application state efficiently without inducing excessive SwiftUI view rebuilding contexts.

## Hardware Domain

### `CameraManager`
- Direct AVFoundation abstraction explicitly tied to `.builtInLiDARDepthCamera` arrays on physical devices.
- Triggers strictly when `.handleActivePhase()` calls within `MerianApp.swift`.
- Governs `subjectDistanceInMeters`, auto-focus thresholds, thermal bounds, and frame drops safely natively inside a `DispatchQueue(label: "camera.session")`.
- Eradicates severe Accelerate `vImage` CPU starvation during paused contexts natively. It deploys an atomic `nonisolated(unsafe) private var activeInferencePaused` boolean structurally synced with the `@MainActor` preference boundary explicitly. This strictly forces an immediate short-circuit early return completely halting the massive hardware histogram allocation pipeline inside `captureOutput`, violently preserving extreme physical battery thermals efficiently whenever the Viewfinder AI is halted.
- **Leak-Proof Deferred Mutex Unlocks**: Directly mitigates implicit AVFoundation buffer leaks and device thread black-screen lockouts by injecting rigid `defer { device.unlockForConfiguration() }` and `defer { CVPixelBufferUnlockBaseAddress }` hooks across all logical hardware control workflows intuitively resolving physical boundary crashes inherently mapping safely.

### `EnvironmentContextManager`
- Explicit mapping for configuring dual properties natively inside the `EnvironmentContext` dependency graph without invoking UI rerenders:
  - **CoreLocation**: Caches and strictly updates precise physics logic (`CLLocationCoordinate2D`, `altitude`, `course`).
  - **WeatherKit**: Aggregates hyper-local edge metrics like `temperature` and `condition` instantaneously natively to supplement inference payloads.
- Intelligently locks variables globally to `cacheThreshold` boundaries directly shielding the device battery pool smoothly.

### `HapticManager`
- Governs `UIImpactFeedbackGenerator` tactile bumps.
- Generates `NotificationFeedback` natively tying into success/failure workflows across the core application safely bypassing standard `AudioToolbox` imports.

### `PushNotificationManager`
- Encapsulates isolated Apple `UNUserNotificationCenter` structures directly mapped inside the `@MainActor` thread.
- Resolves system `authorizationStatus` natively polling the iOS explicit boundary state directly to override local SwiftUI `@AppStorage("isPushNotificationsEnabled")` primitives asynchronously. If a user natively revokes permissions via the OS Settings pane, it securely aligns the local flag synchronously out of sync-loops bypassing redundant user friction seamlessly.
- Configured firmly as the `UNUserNotificationCenterDelegate`. It dynamically injects `scanId` representations physically into `.userInfo` payload arrays allowing silent background offline completions to pop visibly over the lockscreen.
- Hooks explicit Deep Link taps intercepting closures organically dropping the explicit UI directly onto an active `InsightSheet` smoothly avoiding generic app-launcher behavior constraints natively.
- Intercepts visual `completionHandler([])` active arrays physically masking inference banners automatically protecting in-app UX execution flows whenever the application resolves strictly `.active`.

## AI & Offline Synchronization

### `InferenceEngine`
- The core processing unit inside `merian/Core/AI/`.
- Dispatches securely decoupled sensor structures via `CaptureTelemetry`, explicitly forwarding `depthScaleText`, `deviceLocale`, `currentMonth`, and physical coordinate states natively out to the Supabase Node (`MerianNetworkClient.analyzeSubject`).
- Automatically filters natively against `gemini-2.5-flash` or `gemini-2.5-pro` (dynamically allocated based on user subscription tier) payloads binding the structural taxonomy strings mapped specifically right back down to native local properties.
- Strictly maps native ephemeral telemetry metadata (such as `gpsLatitude`, `gpsLongitude`, `gpsElevation`, `weatherCondition`, `weatherTemperatureF`, and `locationName`) directly back into the parsed `SpeciesData` model, completely abstracting it from the Edge runtime and securely establishing layout geometries seamlessly for the UI layer identically across Live and Offline sweeps.
- Responsible for mutating and triggering the "Graceful Degradation" UI bounds when network calls fail natively by dumping the payload explicitly down to `OfflineQueueManager`.
- **Multi-Image Concurrency & Swift 6 Actors**: Radically abstracts decoupled image transformations `InferenceProcessingActor` completely circumventing rigid `Task.detached` blocks that were explicitly avoiding iOS restrictions natively. Executing explicit `FileIOActor` filesystem validations and base64 parsing loops natively via asynchronous boundaries cleanly protects against data-races globally structurally.

### `OfflineQueueManager`
- Dictates completely silent `URLSession` background mappings dynamically allowing the app to seamlessly stash pending physical imagery natively into the local disk partition (Document Directory).
- Explicitly registers background handlers inside `AppDelegate` safely guaranteeing `URLSession` callbacks natively execute uploads seamlessly completely apart from the main user UI grid logic.
- Utilizes a unified static abstraction `BackgroundTaskWrapper.execute(name:operation:)` natively to rigidly encapsulate active memory environments binding OS threat loops securely to `UIBackgroundTaskIdentifier` instances gracefully preventing system leaks under suspension natively.
- **Array Execution Persistence**: Safely iterates arrays of image binaries (`[Data]`) asynchronously, writing each physical file sequentially directly to `.documentsDirectory` and appending discrete `localImagePaths` paths organically. This robust loop ensures aggressive iOS suspension constraints do not structurally corrupt multi-image queued bundles prior to resolving cell reception natively.
- **Recursive Queue Draining**: Structurally enforces automatic synchronization across massive off-grid captures. The underlying `URLSession` delegate recursively trips `syncPendingScans()` immediately when completed batches detect remaining `unsyncedItemsCount > 0`, completely preventing offline queues from seizing without manual user intervention.
- **`MerianConfig` Batch Limits**: Upload batch sizing and fetch limits are governed by `MerianConfig` constants (`uploadBatchSize = 5`, `pendingScanFetchLimit = 50`) rather than inline literals, ensuring policy changes require a single edit.
- **Sync Phase Transitions**: Drives the `SyncStateManager` state machine through `.uploading(count:)` → `.inferencing` → `.finalizing` → `.idle` as the pipeline progresses, giving UI components precise phase visibility.

### `SyncStateManager`
- `@MainActor @Observable` singleton that exposes the current sync phase to UI components.
- Driven exclusively by `OfflineQueueManager` — never mutate from anywhere else.
- Replaced original `isSyncing: Bool` + `pendingUploadCount: Int` properties with a `SyncPhase` enum:
  - `.idle` — no activity
  - `.uploading(count: Int)` — image files are being PUT to R2 staging
  - `.inferencing` — the Gemini Edge function is running
  - `.finalizing` — writing `LocalScanRecord` and cleaning up queue entries
- Backward-compatible computed shims (`isSyncing`, `pendingUploadCount`) are preserved for existing consumers.
- Exposes `beginSync(itemCount:)`, `beginInferencing()`, `beginFinalizing()`, `completeSync()` as the write API.

### `ScanRepository`
- `@MainActor` singleton facade over `OfflineQueueManager` and SwiftData, decoupling UI and ViewModels from `ModelContext` and queue internals.
- Injected at startup via `configure(with:)`, which also seeds the "Favorites" collection if absent.
- **`syncHistoricalScansDown`**: Fetches cloud scan and collection history with pagination (`MerianConfig.historicalSyncPageSize`, `MerianConfig.collectionsSyncPageSize`), then delegates all reconciliation to a single `HistoricalDatabaseActor.reconcileAllHistoricalData(responses:collections:)` call — eliminating the previous 3-call actor-boundary crossing pattern.
- **`eradicateScan`**: Commits database changes (delete record, insert cloud deletion task) before touching disk. File deletion via `FileIOActor.shared.deleteImages(at:)` runs only after a successful `modelContext.save()`, guaranteeing no partial-failure inconsistency.

### `ScansManager` (Search Indexing Isolation)
- Strictly bounds memory starvation globally across 5,000+ internal payloads seamlessly decoupling massive search iteration arrays from the main `.onChange()` thread cleanly.
- Overrides synchronous string rebuilds by explicitly enforcing an `O(1)` Delta Update pattern safely. It intercepts only the specific Swift Sets (`oldIds.subtracting(newIds)`) when a capture drops natively out of the array limit safely eliminating O(N) CPU thrashing!
- Safely delegates extraction generation exclusively inside `indexingTask = Task.detached` cleanly wrapping memory loops inherently inside a `SearchDatabaseActor` which evaluates identifiers statically without blowing out JetSam limitations.

### `ArchiveManager` (Archive Safety Protocol)
- Explicit background worker strictly mapped to protect the data of Free tier users against the Cloudflare R2 90-day global purge logic (`00004_storage_lifecycle_sync.sql`).
- Polls locally via `getAvailableDiskSpace()`. Storage threshold and rescue window are now driven by `MerianConfig` (`diskSpaceThreshold = 500 MB`, `archiveRescueWindowStartDays = 80`, `archiveRescueWindowEndDays = 88`) rather than inline literals.
- Dynamically `evaluateAndRescueAgingScans` queries SwiftData logs looking for `.isLocallyArchived == false` records older than 80 days strictly executed locally via `.handleActivePhase()` native UI lifecycle hooks once per day saving images directly into explicit bounds. To physically block RAM spikes triggering JetSam boundaries during batch rescues, the system completely bypasses massive `.data(from:)` array loadings. Instead, it securely cross-references the remote database edge for `image_storage_urls`, and safely streams the binary payload down securely via `URLSession.shared.download(from:)` explicitly piping the temp file cleanly over to the document partition via `FileManager.default.moveItem`. Crucially, the system structurally writes only the relative `filename` string into SwiftData rather than the `fileURL.path`. This correctly prevents Absolute Sandbox Path map breakages caused by iOS dynamically altering and randomizing container UUIDs on device reboots and physical app updates seamlessly avoiding broken image renders natively completely.
- **N+1 Query Eradication**: Completely skips sequential Supabase round-trips natively mapping the background dataset arrays. It preemptively extracts a complete array of `.identifier` strings, and sends a single `O(1)` `.in("id", ...)` PostgREST query payload cleanly pulling all storage relationships dynamically directly preventing worker starvation.

### `MerianConfig`
- Centralized enum (`Core/Utilities/MerianConfig.swift`) holding all policy constants for the data layer.
- Prevents silent divergence when tuning batch sizes, page sizes, thresholds, or retention windows — a policy change requires exactly one edit.
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
- Isolates physical Deno function endpoints mapping directly via `MerianEnvironment.supabaseUrl`.
- Inherently abstracts API invocations natively using a centralized `performAuthenticatedRequest` pipeline, effortlessly intercepting duplicated JWT validation layers sequentially securely mapping identity configurations locally over all 5 discrete public endpoints natively.
- Actively forces exact asynchronous REST calls (`/identify`, `/generate-upload-urls`, `/flag-issue`).
- Automatically extracts the `DeviceIdentityManager.shared.deviceId` strictly bypassing arbitrary session state dependencies smoothly executing Supabase payload pushes correctly mapped directly to the active iOS `ProcessInfo` environment.
- Safely traps `.401 Unauthorized` responses natively within `performAuthenticatedRequest`. Crucially, it completely abstracts JWT validation by delegating to `SupabaseManager.shared.getValidAuthHeaders()`, ensuring all network calls inherently benefit from the unified self-healing Ghost session fallback loops seamlessly securely.

### Edge Network Operations (`S3` & `PostgreSQL` Bulk Insertions)
To structurally execute database actions elegantly inside strict serverless Node limits safely maintaining global bounds:
- **Centralized Cloudflare R2 Executions (`_shared/aws.ts`)**: Instead of recursively deploying raw `aws.sign(...)` headers across the `moderation`, `export-dwca`, and `revenuecat-webhook` logic individually seamlessly multiplying security risks natively, operations uniformly bind dynamic `copyR2Object()` and `deleteR2Object()` structures entirely globally scaling identity bounds cleanly strictly via S3 signatures.
- **N+1 Query Exhaustion Prevention (`sync-collections`)**: Rather than physically fetching iteration loops binding Supabase inserts sequentially against identical tables natively dropping heavy payloads triggering connection exhaustion seamlessly the layer strictly abandons iterations explicitly generating an array organically passed directly into `.insert(allMappings)!` This natively allows the database to process the massive sync directly eliminating timeout limits unconditionally.

### `SupabaseManager`
- Completely delegates the secure API boundary parsing natively wrapped into GoTrue bindings.
- Exports a singular, unified `getValidAuthHeaders() async throws -> [String: String]` abstraction. This completely consolidates the OAuth conditional checks (`Merian_HasAuthenticatedOAuth`) and automatic Ghost Session regeneration logic (using `.identifierForVendor`), ensuring a 100% success rate on stateless REST requests across `MerianNetworkClient` and `SocialGuardManager` natively.
- **DRY OAuth Abstraction**: Explicitly abstracts Apple Sign In and Google Sign In fallback mapping networks securely isolating identical duplication directly into `private func finalizeOAuthLogin`. This securely maps `.linkIdentityWithIdToken` arrays against `.signInWithIdToken` bounds avoiding massive code redundancy mathematically.
- Executes `signInAnonymously()` exclusively mapped to `.uuidString` metrics inside `.identifierForVendor`.
- Maps native Apple/Google OAuth hooks seamlessly migrating Ghost User mappings cleanly explicitly calling `RevenueCatManager.shared.linkWithSupabase()` correctly aligning payment limits securely natively.

## Telemetry & Billing

### `RevenueCatManager`
- Integrates seamlessly handling `isProActive`.
- Resolves mapping safely preventing unhandled `.purchaserInfo()` exceptions internally hooking right into identical Ghost UI bounds locally securely mapping onto `revenuecat-webhook` Edge structures directly natively.

### `PostHogManager`
- Manages anonymous telemetry flows handling `.identifyUser()` logs globally preventing lost analytic strings seamlessly across all native iOS boundary state contexts cleanly.
