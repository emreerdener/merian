# Zero-OOM & Concurrency Architecture

Merian enforces a "Zero-OOM" (Out-Of-Memory), offline-first, and highly concurrent philosophy across its iOS client and serverless Deno Edge backend. This document captures the architectural decisions implemented to satisfy these constraints.

## 1. iOS Concurrency & Memory Constraints (P0)

To prevent UI hangs, memory leaks, and OS-level Watchdog terminations, the iOS app architecture imposes strict limits on resource boundaries:

### Swift 6 Structured Concurrency & Task.detached Removal
Historically, background threading relied heavily on `Task.detached(priority:)`. While successful in offloading work from the `@MainActor`, unconstrained detached tasks evade Swift 6 Sendable boundaries and structured cancellation propagation. Merian abandoned `Task.detached` in favor of strict actor isolation. Features like `SearchFilterActor`, `FileIOActor`, `InferenceProcessingActor`, and `ExportProcessingActor` encapsulate heavy string matching, file system validations, and base64 encodes within their dedicated execution boundaries. Calls crossing these boundaries are mapped as standard `await` invocations off the UI thread via inheriting `Task { }` closures. This achieves background concurrency while inheriting global task cancellation trees.

### ImageIO, CoreVideo, & UIImage Autoreleasepool Memory Leaks
When performing bulk downsampling with CoreGraphics (`ImageDownsampler.downsample` and `ImageCropProcessor`), the C-level APIs (`CGImageSourceCreateThumbnailAtIndex`) allocate large transient buffers. In a standard Swift async function looping hundreds of times without yielding, Apple's Objective-C ARC delays flushing these buffers until the overarching task suspends, producing transient RAM spikes that triggered JetSam OOM terminations. Merian resolves this by wrapping the ImageIO rendering blocks inside `autoreleasepool { ... }` boundaries, clearing C-level `NSMutableData` instances immediately on each loop iteration and preserving a clean RAM ceiling.

This identical RAM ceiling violation exists during Apple Vision AI inferences, detached image decoding, manual cropping, and metadata scrubbing. Executing `VNImageRequestHandler` classifications (e.g., `Analysis.swift` and `SizeEstimator.swift`), uncompressing raw blobs via `UIImage(data:)` off the main thread (`ImagesCarousel.swift` and `CropSheetModifier.swift`), or actively parsing EXIF properties during GPS stripping (`PhotoLibraryManager.swift`'s `executePhotoLibraryWrite`) inside detached closures leaves enormous multi-megabyte allocations cached until the CPU rotates out the `Task.detached` context. Merian enforces `autoreleasepool { ... }` wrappers around these entire isolated blocks and explicitly deprecates raw `UIImage(data:)` inflations in favor of constrained `ImageDownsampler.downsample(data:maxSize:)` extractions. This guarantees that unmanaged ImageIO formats immediately relinquish memory back to the system, dropping transient spikes completely and averting JetSam OOM kills during rapid captures, exports, exports, or swipes.

### AVFoundation Deferred Stalling Avoidance
When interacting with AVFoundation hardware handles like `device.lockForConfiguration()`, invoking early `return` checks or throwing errors before calling `device.unlockForConfiguration()` permanently seized the underlying device bus, resulting in camera black-screens. Dropping CVPixelBuffer lock boundaries also crashed Accelerate vectors. Merian enforces Swift's `defer` closures (`defer { device.unlockForConfiguration() }` and `defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }`) to insulate hardware mutex constraints against unhandled failure states.

### SwiftData Memory Exhaustion (`InsightSheetView` & `BackgroundDatabaseActor`)
When querying records from large user-generated biological libraries in SwiftData, executing a generic `FetchDescriptor` and filtering the `records.first(where:)` array synchronously in memory triggers an OS JetSam crash for power users. Merian prevents this by injecting `#Predicate` constraints directly into the `FetchDescriptor`, forcing the underlying SQLite engine to isolate the single `targetId` without expanding full Swift collections into memory.

The same principle applies to `BackgroundDatabaseActor.pushCollectionsToEdge()`, which previously fetched every `ScanCollection` unconditionally including Favorites (which is never synced). The fetch now uses a `#Predicate { $0.name != "Favorites" }` to exclude Favorites at the SQLite layer. `propertiesToFetch` is intentionally absent: `ScanCollection` has only three stored attributes (`id`, `name`, `createdAt`) so there is nothing to skip, and partial-attribute mode can prevent the `scans` relationship fault from firing correctly, causing `scan_ids` to be serialised as `[]`.

### SwiftData Relationship Faults (OOM)
When managing many-to-many SwiftData relationships, mutating the "Many" side (e.g., `collection.scans.append(record)`) forces the underlying SQLite engine to synchronously fault the entire array — potentially thousands of heavy `LocalScanRecord` structures — into active RAM on the Main Thread. For power users, this causes an immediate JetSam Out-Of-Memory termination. To protect the RAM ceiling, inverted "One" side mutation was applied to `ScanCollection` in UI components like `ScanSelectionSheetView` and `CollectionDetailView`. Developers now mutate and read the "One" side of the relationship (e.g., `scan.collections?.append(collection)` and `scan.collections?.removeAll(...)`) rather than the "Many" side (e.g., `collection.scans?.append(record)`), preventing the SQLite engine from expanding massive data arrays into active RAM. Deleting a collection bypasses iterative child array loops entirely. By executing `modelContext.delete(collection)`, the system uses SwiftData's default `.nullify` behavior, severing connections without pulling individual heavy payloads into active memory.

### SwiftUI View Invalidation Thrashing (`@Observable` Macro Migration)
Under the legacy `ObservableObject` protocol, whenever a core engine like `InferenceEngine` or `HardwareOrchestrator` mutated a background tracking array or hardware metric via `@Published`, it broadcast a global `objectWillChange` event. This forced SwiftUI to recalculate the `body` of every view in the environment graph that injected the object (e.g., `CameraRootView`, `InsightSheetView`), even if those views only relied on isolated, unchanged properties like `isProcessing`. Merian eliminated `ObservableObject` from the codebase.

All environmental managers (`AppDIContainer`, `CameraManager`, `HardwareOrchestrator`, `InferenceEngine`, and `ScansManager`) were migrated to Swift `@Observable` classes. This drops CPU render overhead because SwiftUI tracks property access at runtime directly inside view closures. High-frequency background mutations (`subjectDistanceInMeters`) no longer thrash the global environment, preserving 120Hz refresh rates and reducing thermal loads. All `@EnvironmentObject`, `@StateObject`, and `@ObservedObject` injections were remapped to modern `@Environment()`, `@State`, and `@Bindable` constraints.

### Centralized AppEventPublisher Routing (`NotificationCenter` Migration)
Historically, implicit app state changes (e.g., crossing daily usage limits, handling active deep link phases) were broadcast globally via string-keyed `NotificationCenter.default.post` calls. This posed two architectural risks:
1. **Thread Hopping**: Notifications originating from detached backend tasks could inadvertently trigger UI modifications on a background thread if subscribers omitted `.receive(on: RunLoop.main)` guards.
2. **Type Safety & Retain Cycles**: String-keyed payloads (like `userInfo["scanId"]`) bypassed Swift compiler checks, and dangling `.sink` observer scopes without `[weak self]` caused invisible memory cycles.

**The Refactor**: The architecture deprecates internal string broadcasts globally. `AppDIContainer` now mounts a unified `@MainActor final class AppEventPublisher` exposing a constrained `AppEvent` enum (e.g., `.triggerPaywall`, `.appDidEnterActivePhaseWithScan(scanId: String)`). By wrapping these explicitly through `diContainer.appEventPublisher.publisher.sink`, the view models enforce hard memory constraints, type-checked payload unpacking, and guaranteed `@MainActor` thread-safety execution across the app boundary.

### SwiftUI 17 Environment Macros (`HapticManager`)
Injecting singleton managers into the view hierarchy via `.environment(container.hapticManager)` when those managers did not broadcast state (such as pure hardware execution wrappers with no `@Published` or `@State` variables) compiled cleanly in older Swift versions. Merian targets iOS 18/Swift 6, which requires every object passed into `.environment()` to be an `@Observable` macro instance so the SwiftUI engine can track rendering graphs uniformly. Classes like `HapticManager` adopt `@Observable` despite having no view bindings, satisfying the `AppDIContainer` expansion boundaries.

### SwiftUI Presentation Collisions (`CameraRootView`)
Apple's iOS 17 rendering engine throws fatal exceptions if the UI attempts to present multiple `.sheet` modifiers from concurrent background triggers (e.g. `isScansOpen = true` overlapping with `isInsightSheetOpen = true`). Merian prevents UI presentation overlaps by abandoning discrete `@Published` boolean switches in `CameraViewModel`. Navigation is mapped against a single unified `enum ActiveSheet: Identifiable` property routed through a `Group { switch sheet }`. This blocks the UI from issuing parallel presentation commands, guaranteeing stable 120Hz view transitions without iOS framework layer crashes.

### Swift 6 MainActor Initialization (`CaptureTelemetry`)
When mapping telemetry from the global `InferenceEngine` into a lightweight, `Sendable` `CaptureTelemetry` struct for network offloading, a standard struct initializer `init(from inferenceEngine:)` violates Swift 6 concurrency rules. Because the `InferenceEngine` tracks its properties on the `@MainActor`, a non-isolated initializer crosses execution boundaries, triggering a "Main actor-isolated property can not be referenced from a nonisolated context" compiler error. Merian tags `@MainActor` on the `CaptureTelemetry` initializer itself (`@MainActor init(from inferenceEngine: InferenceEngine)`), ensuring execution aligns with `AppDIContainer.handleBackgroundPhase()` on the UI thread.

### SwiftData Environment Tearing (`MerianApp`)
Attaching `.modelContainer(container)` to conditional child elements (like `.modelContainer` embedded on `CameraRootView` but not `OnboardingView` inside an `if/else` block) forces iOS to tear down and rebuild the SwiftData environment during runtime view swaps. This causes blank screens or crashed queries. Merian hoists all heavy `@Environment` injectables over the outer conditional `Group` shell, ensuring the database mounts from frame zero unconditionally.

### Eager Hardware Instantiation (`CameraManager` & `PhotoLibraryManager`)
Instantiating hardware layers (such as wiring `AVCaptureDeviceInput` inside `CameraManager.init()`) is prohibited. Because Merian uses `AppDIContainer.shared` to distribute managers via `.environmentObject`, these classes boot on cold launch. Executing hardware configuration inside an `init` defeats the Onboarding UI Permission Priming pipeline, triggering OS API modals before the welcome screen appears. The architecture defers hardware instantiation: locks like `.setupSession()` or `PHPhotoLibrary.requestAuthorization` are shifted to explicit `.startSession()` invocation blocks, orchestrating OS bindings behind UX gates.

### Lifecycle Initialization Leaks (`AppDIContainer`)
On a fresh cold-boot, SwiftUI evaluates the global `WindowGroup` environment and transitions `Environment(\.scenePhase)` from `.inactive` to `.active`. `MerianApp` observes this trigger and executes "wake-up" logic inside `AppDIContainer.handleActivePhase()` (bootstrapping `cameraManager.startSession()` and syncing offline records). Because this lifecycle hook fires milliseconds before the first `OnboardingView` renders, it previously bypassed Onboarding gating, forcing camera initialization and OS permission alerts onto the first Onboarding screen. To enforce bounded onboarding states, `AppDIContainer` evaluates `UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")` inline and aborts all hardware pings, sync requests, and background evaluations until onboarding completes.

### SwiftUI Render Loop CPU Thrashing (`ScansThumbnailView`)
When loading grid arrays from SwiftData entries, missing `imagePath` and `fallbackImageUrl` values previously mapped conditionally to `.task(id: ... ?? UUID().uuidString)`. SwiftUI cancels running `.task { }` executions whenever their tracked `id` parameter changes. By returning a dynamic UUID inline, SwiftUI aborted the task, forced a view invalidation, executed layout, and evaluated a new UUID, re-triggering the task recursively. This created infinite cancellation loops running at 120Hz, generating 100% CPU load and draining device battery. Merian fixes this by replacing UUID generation with a constant literal fallback: `?? "empty_thumbnail_state"`.

### SQLite Thread-Safety Violations (`ArchiveManager`)
Instantiating non-isolated `ModelContext` containers inside arbitrary `Task.detached` closures violates Swift 6 concurrency rules, generating data races and `EXC_BAD_ACCESS` crashes under load. Merian abandoned arbitrary detached SQLite threading. Background database ingestion (such as rescuing aging `.jpg` blobs off the S3 proxy) runs inside `@ModelActor` constructs (`ArchiveDatabaseActor`). This isolates SQL read/write operations inside a sequential concurrent thread pool, preventing memory access corruption. Duplicated object mapping logic across models (such as copying `SpeciesData` initialization dictionaries inside `OfflineQueueManager`) is consolidated back into `init(fromEdgeResponse:)` origins, isolating network JSON decoding and preventing data parity errors.

### Serial Upload Staging Head-of-Line Blocking (`OfflineQueueManager`)
Before upload tasks were handed to the OS background `URLSession`, each image in a batch was staged serially: `FileManager.copyItem` (a synchronous NVMe write) ran sequentially per file before the next began. For a 3-image scan on a busy NVMe controller this added 500 ms–2 s of dead time before any byte reached R2.

`syncPendingScans` now uses `withTaskGroup` to fan out the staging work. Pre-flight checks — URL parsing, file-existence guards, tombstoning — remain serial because they are fast and because tombstoning mutates `@MainActor` state. Only the `FileManager.copyItem` + `URLSession.uploadTask` pair is placed in a task group child. All captured types (`URL`, `String`, `Int`, `URLSession`) are `Sendable`, satisfying Swift 6 strict concurrency.

### Background Suspension Limits (`OfflineQueueManager`)
When evaluating inference payloads without cell service, the system requires `UIBackgroundTaskIdentifier` hooks to complete URLSession executions. In Merian, these handles are extracted outside of `@MainActor` task executions to avoid rapid synchronous delegate fire-and-return OS suspension traps.

A unified `BackgroundTaskWrapper` reference box secured with `NSLock` binds these background identifiers. To eliminate duplicated `#if os(iOS)` preprocessor macros and `endBackgroundTask` loops across `enqueueCapture`, `syncPendingScans`, and background URLSessions, the architecture uses a static abstraction: `BackgroundTaskWrapper.execute(name:operation:)`. This handles registering the active memory environment, tracking OS expiration callbacks, and invoking `.endBackgroundTask` inside a `defer` block, guaranteeing URLSession callbacks execute across thread boundaries safely.

If a user taps the capture button and immediately locks their phone before the NVMe controller finishes writing `.jpg` bytes to disk, iOS suspends the thread, producing a corrupted 0KB file. By wrapping the disk I/O inside this OS Background task hook, Merian grants iOS the additional time required to flush the data buffer and prevent payload corruption.

When bridging Swift 6 concurrency boundaries via `Task.detached`, these reference boxes are injected as `Sendable` captures tracking temporal OS states. By dropping optional limits and processing `.invalid` locks over the abstraction boundary, the system prevents iOS Watchdog panics.

To prevent iOS from suspending the application before background I/O queues tear down, Merian does not use `Task { ... }` blocks orphaned inside asynchronous `defer` closures. Inside the URLSession completion handler, active task evaluations (`session.allTasks`) are executed within the synchronous, awaited boundary of `BackgroundTaskWrapper.execute`, guaranteeing the queue lock releases before the `UIBackgroundTaskIdentifier` expires.

`urlSession(_:task:didCompleteWithError:)` extracts non-Sendable `task.taskDescription` and HTTP string properties into local immutable variables on the delegate context before crossing the background wrapper boundary.

Early function return paths in `OfflineQueueManager` that skipped inference on `504` error codes also unintentionally skipped `SyncStateManager.shared.completeSync()`, permanently deadlocking the offline queue. Merian enforces teardowns via a `defer` block that checks `session.allTasks.isEmpty` and runs the teardown unconditionally, overriding all possible abort paths.

When chunking pending offline scans into Edge Function payloads, Merian caps loop payloads via `.prefix(5)` on the `filteredScans` array. Previously, applying a secondary `.prefix(5)` limit on the flattened `fileNames`, `fileURLs`, and `scanIDs` arrays severed multi-capture payloads (since one offline scan can have up to 2 local captures). Removing the truncation on the flattened arrays and relying solely on the scan-level limit guarantees a partial payload is never pushed to Cloudflare R2, preventing silent `HTTP 400 Array Length` errors. To comply with Swift 6 concurrency, redundant `await` hooks preceding `session.uploadTask(with:fromFile:)` were removed. Since this URLSession factory creates a deferred upload object synchronously, calling `await` forced unnecessary thread hops and produced compiler concurrency faults.

### Background Delegate Deadlocks (`PushNotificationManager`)
When executing URLSession hooks via a background task identifier, the Merian application remains visually suspended but structurally active. When AI processing triggered completion alerts, `UNUserNotificationCenterDelegate` fired `willPresent` because the process was alive. Historically, attempting to asynchronously read `@MainActor UIApplication.shared.applicationState` inside `willPresent` to conditionally suppress foreground banners caused race conditions that led iOS to drop the notification entirely. Furthermore, conditionally omitting notifications from `InferenceEngine` when the app was in the foreground prevented users from receiving alerts if they navigated away from the camera to browse their library.

Now, `InferenceEngine` emits notifications unconditionally. The delegate executes purely synchronously by reading a pre-calculated `suppressInferenceBanners` `UserDefaults` flag. The UI (via `CameraViewModel`) updates this flag dynamically, instructing the delegate to suppress the banner only when the user is explicitly staring at the scanning overlay or insight sheet. This guarantees reliable 100% delivery for insight completions and achievements without triggering main-thread blocking or spamming the active viewfinder context.

### Hardware Rotation Defenses (`CameraManager`)
Historically, attempting to manually map `UIDevice.orientation` against `videoOrientation` triggered a double-rotation sequence because Apple's camera firmware independently injected EXIF `CGImagePropertyOrientation` into the output buffer. Merian resolves this using iOS 17's `AVCaptureDevice.RotationCoordinator`. By instantiating a hardware rotation coordinator against the active camera device, the app continuously monitors physical accelerometer data independent of the user's software Control Center orientation lock. The capture sequence synchronously injects `videoRotationAngleForHorizonLevelCapture` into the `photoConnection` prior to executing the shutter. This delegates the geometric rotation to the image signal processor without corrupting Apple's resulting EXIF headers, guaranteeing perfectly oriented portrait and landscape shots even while the device software rotation is locked.

### Hanging Continuations (`CameraManager`)
Apple's ISP (Image Signal Processor) can stall during extreme thermal saturation, failing to return an image frame via `AVCapturePhotoCaptureDelegate`. Rather than silently hanging the `isShutterActive` UI state, Merian wraps `withCheckedThrowingContinuation` patterns inside a `withTaskCancellationHandler`. To handle multiple overlapping captures on a single UI state, Merian associates an array tracking queue (`activeCaptureRequests`), isolating concurrent `timeoutTask?.cancel()` closures via unique UUID identifiers. This clears specific stalling entries from RAM and resolves dropped continuations via `CancellationError` without blocking subsequent captures.

### Post-Inference Image Buffer Leak (`InferenceEngine`)
After a successful inference round-trip, `activeImageData` and `activeLiveCaptureDatas` were left populated until the *next* scan started. For multi-shot captures, these arrays hold several MB of compressed JPEG bytes with no cleanup path on the success branch. The `cancelActiveRequest()` path already cleared them, but the success path did not.

`InferenceEngine.analyze` now clears both properties immediately after `speciesData` is assigned on success, releasing the buffers before the Wikipedia hydration task fires. The `defer { self.isProcessing = false }` block at the top of the task continues to cover the failure and cancellation paths.

A formerly-present third buffer, `activeCompressedImageData`, was an exact duplicate of `activeLiveCaptureDatas[0]` / `activeImageData` with zero external consumers. It has been removed entirely, eliminating a second copy of the compressed JPEG on the `@MainActor` heap.

### Historical Scan Hydration Task Proliferation (`InferenceEngine.load(from:)`)

When opening a historical scan, `load(from:)` previously spawned up to 4 independent untracked `Task { }` blocks (image path validation, JSON decode, Wikipedia hydration, enrichment/GBIF hydration). Navigating rapidly between scans left all prior tasks running — each decoding JSON, making network calls, and writing `@Observable` state for a scan no longer on screen.

`InferenceEngine` now owns a single `@ObservationIgnored private var historicHydrationTask: Task<Void, Never>?`. At the start of every `load(from:)` call, the previous task is cancelled. All async hydration work (image-path validation → JSON blob decode → override patch → Wikipedia → enrichment) runs sequentially inside this one task with `guard !Task.isCancelled` checks between stages. The JSON blobs are decoded inside a nested `Task.detached` to keep `JSONDecoder` off `@MainActor`.

### Unbounded GBIF Reference Image Accumulation (`InferenceEngine`)

`fetchGBIFImagesAndHydrate` previously appended up to 4 new GBIF image URLs to `speciesData?.referenceImageUrl` (a comma-separated string) on every open. GBIF URLs are now capped at **5 entries** (`Array(currentUrls.prefix(5))`). The redundant `await MainActor.run { }` hops inside this method have also been removed — `InferenceEngine` is a `@MainActor` class, so all methods resume on the main actor after every `await`; the explicit wrappers were a no-op.

### Enrichment Re-firing on Every Open (`InferenceEngine`)

For species that permanently lack GBIF data or habitat descriptions, the enrichment eligibility condition evaluated `true` on every open, firing an `enrich-scan` Edge Function call that returned the same empty result each time. `InferenceEngine` now maintains `@ObservationIgnored private var enrichmentAttemptedScanIds: Set<String>`. The gate is set **before** the call so even empty results prevent re-fires. Live inference scans (via `analyze()`) bypass this gate.

### `wikiFetchAttemptedIds` Full-Wipe Eviction (`InferenceEngine`)

When `wikiFetchAttemptedIds` hit the 500-entry cap, the entire set was wiped — causing immediate Wikipedia re-fetches for all 500 recently-seen species. Now **10% of entries** (`prefix(wikiFetchAttemptCap / 10)`) are evicted on cap hit, preserving 90% of recently-fetched entries.

### Reconnect Debounce Task Stacking (`OfflineQueueManager`)

On a flapping WiFi ↔ cellular handoff, `NWPathMonitor` fires multiple `pathUpdateHandler` callbacks. Each positive-connectivity callback previously created a new untracked 1-second debounce task, causing stacked `syncPendingScans()` calls. `OfflineQueueManager` now holds `@ObservationIgnored private var reconnectDebounceTask: Task<Void, Never>?`. Every positive event cancels the previous debounce task before creating a new one. Connectivity-loss also cancels the pending debounce alongside `syncTask` and `collectionSyncTask`.

### `AVCaptureSession.inputs` Thread Safety (`CameraManager`)

`applyTargetFPS` and `throttleToIdleState` previously read `session.inputs` on `@MainActor` before entering `queue.async`. `AVCaptureSession.inputs` must be accessed on the session queue. Both methods now capture the session reference and move the `inputs` lookup inside `queue.async { capturedSession.inputs... }`.

### Thread Starvation & Dropped Frames (`InferenceEngine`)
To prevent the Main Thread from stuttering during 120Hz `ScrollView` interactions, `JSONDecoder()` operations against large scientific dictionary responses run inside `Task.detached(priority: .userInitiated)`. To prevent Swift 6 race conditions causing `EXC_BAD_ACCESS` during rapid multithreading, SwiftData `.insert()` operations are decoupled from the raw `.detached` payload and routed through the `@ModelActor BackgroundDatabaseActor`, preserving isolated SQL boundaries.

If the user rapidly triggers the capture shutter, old execution loops are cancelled via `self.inferenceTask?.cancel()` at the top of `.analyze()`, immediately severing orphan tasks that leak memory, consume cellular data, and increment API limits.

When checking historic scans, local `FileManager` checks for sandbox paths evaluate asynchronously within `InferenceEngine`, binding to `@Published` values and guaranteeing smooth `InsightCarousel` rendering.

### Main Thread Disk I/O Blocking
Executing local `FileManager` disk sweeps and `URLSession` network downloads on the `@MainActor` thread blocks the 120Hz UI refresh rate during heavy operations. Functions like `saveUserPhotos()` inside `InsightMediaExportManager` and cache clearance loops in the User Profile are decoupled into `Task.detached(priority: .userInitiated)` and `Task.detached(priority: .utility)` blocks. The main thread is only re-entered via `await MainActor.run` to flip boolean states or trigger `HapticManager` responses.

### OOM-Safe Bulk Deletion (`NonBiologicalScansView`)
When executing bulk "Clear All" operations on potentially hundreds of non-biological scans, looping `FileManager.default.removeItem` and SwiftData row deletions sequentially on the `@MainActor` freezes the 120Hz UI and triggers a JetSam crash. Passing an array of `@Model` `[LocalScanRecord]` entities into a background thread violates Swift 6 Sendable constraints. `NonBiologicalScansView` decouples this operation by presenting a `@State` `ProgressView` loading overlay. The architecture iterates the UI array once on the Main Thread, mapping the dataset into lightweight `Sendable` primitives (`ScanErasurePayload`). These primitives bridge into a `Task.detached(priority: .userInitiated)` shell, initializing an isolated `@ModelActor` (`BackgroundDatabaseActor`). Inside the actor, raw `.jpg` bytes are deleted from the APFS layer, database records are removed, and `.save()` executes once at the end of the batch. The main thread then dismisses the UI overlay and syncs the pending offline deletion queue.

### Bulk Export OOM Exhaustion (`InsightMediaExportManager` & `PhotoLibraryManager`)
When executing `saveUserPhotos()` across the historical file cache and external Cloudflare URLs, loading via `Data(contentsOf: url)` placed multi-megabyte uncompressed JPEGs directly into active RAM. For power users running global bulk exports, this breached iOS memory ceilings and triggered JetSam terminations.

**The Refactor**: Temporarily offloading bytes via `saveImageManual(fileURL:)` shielded application RAM by bridging paths to the SSD, but exposed a native iOS `photod` daemon isolation bug. The Apple `PHAssetCreationRequest.performChanges` block silently drops payloads generated outside the permissioned `URL.documentsDirectory` app sandbox. Merian reverted this approach and re-adopted `Data(contentsOf:)`, loading bytes into application RAM iteratively. Because `ScansSearchView` caps selections at `maxBatchSelectionLimit = 20`, the export footprint is bounded at roughly 200 MB peak — safely within iOS limits while avoiding the sandbox bug.

This OOM boundary also affected `ScansSearchView` multi-select. Allowing "Select All" on 2,000 entries would map entirely uncompressed `UIImage` data into the `UIActivityViewController` sharing array, immediately exceeding available memory. To prevent this, selections are capped at 20 (`maxBatchSelectionLimit = 20`). Tapping "Select All" filters `searchManager.filteredScans.prefix(20)`, and manual taps beyond the limit trigger an `ErrorThump` alert.

### Swift 6 Sendable Violation Crash & Media Export RAM Spikes (`InsightMediaExportManager`)
When executing `batchSaveUserPhotos` and `batchShareDiscovery` iteratively, passing an array of `[LocalScanRecord]` (`@Model` / `@MainActor` bound) directly into a `Task.detached` closure violated Swift 6 Sendable boundaries, causing `EXC_BAD_ACCESS` crashes under high load.

**The Refactor**: The processing boundary decouples the `@MainActor` SQLite arrays. `.map` executes on the UI Thread to create lightweight, `Sendable` structs (`SavePhotosPayload` and `SharePayload`). These pure primitive strings cross the background detached boundary safely, resolving thread violations and eliminating crashes.

Loading local file bytes sequentially via `Data(contentsOf:)` and binding `UIImage(data:)` in batch share arrays bloated uncompressed files into active RAM. Loading 20 concurrent captures crushed iOS memory limits during `UIActivityViewController` presentation. Merian replaces this entirely with `ImageDownsampler.downsample(url: maxSize: 2048)` and `ImageDownsampler.downsample(data: maxSize: 2048)`, fetching bounded `CGImage` thumbnails that constrain the memory footprint and enable smooth sheet rendering wrapped perfectly inside `autoreleasepool`.

### SwiftData Observer Drop in Presentation Portals (`NonBiologicalScansView`)
When capturing `@Model` instances (`LocalScanRecord`) into SwiftUI presentation layers like `.alert` or `.confirmationDialog` button closures, SwiftData `@Query` observers routinely lose tracking. Modifying `scan.isBiological = true` and calling `modelContext.save()` inside these disconnected "portals" mutates SQLite correctly but fails to trigger SwiftUI reactive updates, leaving the UI in a stale state.

**The Refactor**: Merian resolves this by executing a re-fetch inside the `.alert` action via `modelContext.model(for: scan.persistentModelID)`. This retrieves the tracked `@MainActor` memory pointer from the active context. Operations executed from there propagate correctly, collapsing `NonBiologicalScansView` boundaries and routing the payload back into the central biological timeline.

### GCD Dispatch Mixed Into Swift Concurrency Contexts
Several sites used `DispatchQueue.main.async` or `DispatchQueue.main.asyncAfter(deadline:)` inside `@MainActor`-bound or SwiftUI view contexts, creating subtle ordering hazards:

- **`HapticManager.triggerErrorThump`** (a `@MainActor @Observable` class): The follow-up `error.notificationOccurred(.error)` was delayed with `DispatchQueue.main.asyncAfter(...+0.1)`. Because the class is already `@MainActor`, crossing back through GCD is redundant and can produce ordering races if the main run loop is busy. Replaced with `Task { @MainActor in try? await Task.sleep(nanoseconds: 100_000_000) ... }`.
- **`InsightSheetView.onAppear`**: The bottom-bar animation was triggered with `DispatchQueue.main.asyncAfter(...+0.35)` inside an `.onAppear` closure. This was converted to a standalone `.task` modifier. The `.task` version is automatically cancelled if the view disappears before the 350 ms delay fires — the `asyncAfter` version was not cancellable and would mutate state on a view that was no longer on screen.
- **System framework callbacks** (`UNUserNotificationCenter`, `AVCaptureDevice`, `PHPhotoLibrary`, `CLLocationManagerDelegate`, `AVCaptureEventInteraction`): These APIs call their completion handlers on arbitrary background threads. Crossing back to the main thread with `DispatchQueue.main.async { }` is replaced throughout with `Task { @MainActor in }`. This keeps all main-actor hops within the Swift concurrency runtime, enabling priority inheritance and avoiding the GCD/async interop pitfalls documented by SE-0297.
- **`BackgroundTaskWrapper.safeEnd()`**: `UIApplication.shared.endBackgroundTask()` requires the main actor. Previously used `DispatchQueue.main.async`; replaced with `Task { @MainActor in }` for the same reason.

**Rule:** Never use `DispatchQueue.main.async` or `DispatchQueue.main.asyncAfter` in new code. Use `Task { @MainActor in }` for one-shot hops from background callbacks, and `.task` modifiers or `await MainActor.run { }` for structured async contexts. All existing `DispatchQueue.main.*` sites have been migrated.

All replacements keep execution within the structured concurrency tree, making cancellation, ordering, and priority inheritance predictable.

### SwiftUI Task Cancellation Swallowing
When generating delays (like `toastMessage` banners) using SwiftUI's `.task(id:)` modifier, using `try? await Task.sleep()` swallows the native `CancellationError`. If the `id` changes rapidly, the swallowed error prevents the active task from aborting, creating race conditions where multiple toast timers overlap and prematurely clear the UI state. Merian enforces `try await Task.sleep()` without the optional coalescing inside `.task(id:)` structures, guaranteeing SwiftUI cancels previous suspended timers instantly.

### Incomplete Gamification UI Animation Thrashing (`AwardCard`)
When rendering large arrays of incomplete offline biological achievements (`AwardCard`), unconditionally executing `.overlay` `GeometryReader` linear gradient shaders alongside randomly generated `.task { while !Task.isCancelled }` animation loops locked `@MainActor` execution, wasting CPU cycles on badges the user had not unlocked. Merian bounds both the `.overlay` rendering and the stochastic task generators inside an explicit `guard award.isCompleted else { return }` check, stopping the OS from executing animation sweeps on unearned badges.

### UI Thread Blocking (`ProfileView` Exports)
Generating a global Darwin Core Archive (DwC-A) over the `/request-export-dwca` Edge node instantly kicks off a massive SQL/R2-copying workload on the background `/export-dwca` worker. While the request itself completes in sub-100ms with a `200 OK` queue confirmation, awaiting this POST payload blindly would still block the UI thread unnecessarily.

The `MerianNetworkClient.shared.exportDwcA` task is hoisted into an isolated `Task.detached(priority: .userInitiated)` shell, toggling an insulated `@MainActor` `isExporting` state. Only when the API returns the `200 OK` queue confirmation does execution jump back to the Main Thread to render a completion toast, notifying the user that the archive link has been securely dispatched to their email address.

### Main Thread Search Thrashing (`ScansManager`)
When mapping raw SwiftData query results across thousands of user records, extracting strings synchronously inside `@MainActor` property observers (like `allScans.map { ... }` inside `didSet`) causes UI freezes. The 20–50 ms delay produces visible stuttering on every keystroke. `ScansManager` resolves this by stripping the synchronous data structure immediately, extracting lightweight `PersistentIdentifier` ID arrays on the Main Thread and shipping them into an isolated `Task.detached(priority: .userInitiated)`. A dedicated `@ModelActor SearchDatabaseActor` then iterates through the ID array, using the efficient `model(for: id)` hook to fault specific database records into memory progressively, preserving O(1) resolution without violating memory limits. Results are transformed into `SearchableScan` structures, and `await MainActor.run` is called only once the search cache has finished building. To prevent CPU thrashing during rapid typing, the detached sequence is bound to an `indexingTask` reference; earlier task executions are cancelled via `indexingTask?.cancel()` and `Task.isCancelled` checks.

### SwiftData Fault Caching Thrash (`ScansManager`)
While `SearchDatabaseActor.extractSearchablePayloads` insulated the Main Thread, calling `modelContext.model(for: id)` inside a loop faulted large `LocalScanRecord` structures into the SQLite RAM graph, destroying JetSam caps for 10K+ element lists.

**The Refactor**: The background search abstraction creates localized `@ModelActor` contexts for mapping operations. Because the Swift runtime isolates and executes these mappings inside transient `Task.detached` boundaries, Apple's `ModelContext` deallocates without requiring an explicit `.reset()` hook, restoring the active memory footprint to O(1) scaling.

### O(N) CPU Indexing Thrash (`ScansManager`)
Updating or deleting a single record previously triggered the `allScans` observer to wipe the entire multi-index tracking string and pass the full array into `SearchDatabaseActor` for re-evaluation of 5,000+ elements sequentially, pegging the CPU.

**The Refactor**: The global array re-indexing loop was removed. `ScansManager.updateSearchableData` uses a `Set`-based delta update. Deleted records invoke `.removeAll { ... }` directly against the discrete array without touching the background processing thread. Newly captured records jump the background worker queue, incrementally appending only the new entries onto `@MainActor`.
* **Hot-Swap Updates (Custom Tags)**: Because `Set`-based ID diffing inherently ignores internal property mutations on existing scans, updates to fields like `customTags` are handled via an explicit `NSNotification.Name("ScanRequiresSearchIndexUpdate")`. The `ScansManager` catches this trigger, isolates the singular scan ID, and natively hot-swaps only its unigram payload via the background `SearchDatabaseActor` thread in under 10ms.

### UI Body Array Calculations (`UserStats` & Contribution Heatmap)
Executing heavy O(N) array manipulations (such as `Set(allRecords.map { ... }).count` or `Calendar` date-normalization for a 52-week heatmap) directly inside a SwiftUI `var body: some View` forces the Main Thread to re-evaluate the math on every `@Query` binding update. For Pro users with 5,000+ captures, this causes stuttering during Profile scrolls. Merian moves this work off-thread:

- `ProfileDatabaseActor` isolates unique species mapping and the 52-week `ProfileHeatmapData` generation inside `@ModelActor`, executing the calendar loops off-thread. `NumberFormatter` and `Calendar` loops are removed from `ScansHeatmap`'s body; `currentMonthCaptures` is processed inside `ProfileDatabaseActor`, producing an O(1) render value on the UI thread.
- Results are packaged as flat `Sendable` configurations before updating lightweight `@State` primitives on the `@MainActor`, insulating `ScansHeatmap` from any O(N) loop dependencies.
- **View Graph Explosion Protection**: Dense inner views evaluating 364+ element block grids in `ScansHeatmap` were migrated to `LazyHStack` bindings, preventing massive node instantiations across the `ScrollView` and limiting rendering to on-screen elements only.

### Edge Geometry Observers (`FadingScrollView`)
When masking a `ScrollView` with dynamic fade overlays that evaluate scroll position, combining `PreferenceKey` emission tracking with `.defaultScrollAnchor(.trailing)` layouts fails on iOS 17. The preference change resolution is silently dropped during the initial structural anchoring sweep, permanently freezing geometric tracking variables at `0`. In the `ScansHeatmap` contribution graph, Merian abandons all `PreferenceKey` protocol loops.

- `FadingScrollView` bypasses this by adopting `.onChange(of: geo.frame(in: .named("FadingScrollSpace")).minX, initial: true)`, observing geometric measurements directly inside the view-closure block rather than delegating across the UI bound tree.
- This triggers alongside the UI layout, allowing `offset` evaluations to mutate `LinearGradient` mask bounds correctly without dropping updates across the trailing anchor layout.

### Concurrent Environment Context Fetch (`EnvironmentContextManager`)
In `fetchDeferredContext`, reverse geocoding (`reverseGeocode(location:)`) and weather fetching (`weatherService.weather(for:)`) were previously sequential `await` calls. Since these are independent network I/O operations — typically 300–800 ms each — sequential execution added 300–1000 ms of unnecessary latency to every shutter press.

`reverseGeocode` is now launched as an `async let` child task before `weatherService.weather(for:)` begins on the main task. Both operations run in parallel. The geocode result is `await`-ed when constructing the `EnvironmentContext` return value — at which point it is almost always already resolved. The pattern also handles the failure case correctly: if weather throws, `await locationName` in the `catch` block retrieves the geocode result (which ran concurrently and is ready) without re-fetching.

### Apple Geocoder Rate Limiting (`EnvironmentContextManager`)
Invoking `CLGeocoder().reverseGeocodeLocation` on every historical index directly triggers Apple server rate limits. Rapid bulk photo imports fire `CLError.network` suspensions resulting in hours of stranded metadata. Merian abstracts the geocoder loop with a RAM-based LRU coordinate cache, rounding hash precision to 111 meters (`%.3f,%.3f`). Location patterns clustering on the same coordinates resolve from cache without touching the device radio, and offline synchronizations skip the server check entirely.

### Deferred Location Timeouts (`EnvironmentContextManager`)
Unconditionally calling `timeoutTask?.cancel()` in debounced functions like `requestSingleLocation()` caused starvation. If the user tapped the shutter rapidly, the timeout task was deferred indefinitely, growing the `activeContinuations` array and permanently hanging the camera shutter pipeline. Merian resolves this: the timeout task is now instantiated only if one is not already running, allowing existing tasks to fire and flush. Active continuations are cancelled inside `locationManager(_:didUpdateLocations:)` and `didFailWithError`, enforcing limits on resolution latency.

### Synchronous SQLite on the Launch Path (`ScanRepository`)
`ScanRepository.configure(with:)` was called synchronously during app setup and performed a `FetchDescriptor<ScanCollection>()` fetch — loading every `ScanCollection` record with every stored property — to check whether a "Favorites" collection existed. On large libraries with many collections, this blocked the main thread before the first frame rendered.

Two fixes were applied together:
1. **Async deferral**: `configure` now returns immediately after injecting the queue context. The Favorites check runs inside `Task { @MainActor in }`, yielding the current synchronous callsite and running on the next main actor iteration.
2. **O(1) fetch**: The full collection fetch was replaced with `modelContext.fetchCount(descriptor)` where `descriptor` uses `#Predicate { $0.name == "Favorites" }` and `fetchLimit = 1`. SQLite evaluates this as a `SELECT COUNT(*) WHERE name = 'Favorites' LIMIT 1` — constant time regardless of library size.

### Synchronous SQLite Blocking (`MerianApp`)
Wrapping the core `ModelContainer` SwiftData instantiation inside `MerianApp`'s `.init()` guaranteed a UI hitch. For power users booting thousands of scans, evaluating deep SQLite schema migrations synchronously before the `WindowGroup` rendered blocked the Main Thread and destroyed the camera's "Instant-On" latency. Merian removes this stutter by rendering `CameraRootView` without a local container, offloading `ModelContainer(for: schema)` initialization into an asynchronous `.task` lifecycle modifier that attaches the SQLite container in the background.

### App Boot SDK Stutter (`MerianApp`)
Deferring heavy external SDK boot sequences (like PostHog and Crashlytics) via `DispatchQueue.main.asyncAfter` caused a UI hitch milliseconds after `CameraRootView` finished rendering. Merian forces these SDK initializations off the iOS Main Thread by wrapping them within a `Task.detached(priority: .background)` combined with `try? await Task.sleep(nanoseconds: 500_000_000)`, guaranteeing zero stutter during app launch.

### Accelerate Vector Optimizations (`CameraManager`)
Calculating target Luma brightness by looping through `CVPixelBuffer` matrix addresses byte-by-byte (`totalLuma += UInt64(buffer[rowOffset + x])`) pegs the processor inside the 60fps capture loop, provoking thermal throttling in outdoor environments. Merian optimizes this calculation via Apple's Accelerate framework. Using `vImage_Buffer` alongside `vImageHistogramCalculation_Planar8`, execution drops from milliseconds to microseconds.

**The Refactor**: The previous `vImage` logic parked a single `nonisolated(unsafe)` buffer atop the class, violating Swift 6 memory bounds and causing pointer tearing inside the `captureOutput` loop. That global cache object was removed. The system now allocates a lightweight local array inside the inner loop scope: `var histogram = [vImagePixelCount](repeating: 0, count: 256)`. It instantiates locally 60 times per second and deallocates with ARC, enforcing thread-safe memory isolation and satisfying Swift 6 compilation checks.

The same histogram loop also derives `lumaStdDev` (standard deviation of the luma distribution, 0–255 scale) by accumulating `totalLumaSq` alongside `totalLuma` — `stdDev = sqrt(E[X²] - E[X]²)`. This adds no extra vImage passes and negligible CPU cost. `lumaStdDev` is forwarded to `ViewfinderIntelligence` as a sharpness proxy: low variance indicates motion blur or a featureless frame.

### Hardware Concurrency Defenses (`OSAllocatedUnfairLock`)
When tracking asynchronous camera shutter continuations across multiple thread boundaries sharing identical payload dictionaries, wrapping standard dictionaries in generic arrays violates Swift 6 memory protections.

**The Refactor**: Instead of using older Objective-C mechanisms like `NSLock()`, Merian adopts the low-overhead Swift `OSAllocatedUnfairLock` wrapper struct inside `CameraManager`. Wrapping tracking tuples (`let requestsLock = OSAllocatedUnfairLock()`) shields Apple hardware callbacks executing across thread boundaries, removing Thread-Sanitizer execution halts.

### Bridging RAM Leaks (`ImageCropProcessor` & `LocalImageLoader`)
When capturing full-resolution Apple ProRAW or high-megapixel `AVCapturePhoto` assets, translating view coordinates into geometric grid slices forces large temporary memory allocations. Drawing a 12–48 MP uncompressed bitmap into `UIGraphicsImageRenderer` to produce a 1024×1024 output causes memory spikes (~50 MB+) that trigger JetSam terminations on older hardware. Merian abandons intermediate bitmaps and uses Apple's C `ImageIO` framework (`CGImageDestination`). It writes the `cgImg.cropping(to: cropRect)` result directly into a binary WebP `Data` buffer using `kCGImageDestinationImageMaxPixelSize: 1024` and `kCGImagePropertyOrientation` option dictionaries, bypassing RAM bloat. This also enables `generateAutoCenterCrop(image:)`, a 1:1 auto-center square pipeline writing bytes off the Main Thread, preserving 60/120Hz viewfinder latency during rapid multi-capture bursts.

Extracting the binary payload back out of `autoreleasepool { ... return renderData }` previously caused bridging RAM leaks where Swift retained `NSMutableData` references indefinitely. The architecture resolves this by returning `Data(renderData)`, forcing an immutable copy that allows the mutable render buffer to deallocate immediately.

Using `image.jpegData(compressionQuality: 0.7)` as a fallback encoding path tied the uncompressed render operation to the SwiftUI `@MainActor` thread, generating UI stutters and OOM Watchdog terminations. Merian removes `.jpegData` hooks and routes the fallback encoding inside the `.detached` background closure, bounding the unscaled `cgImg` buffer via `CGImageDestination`.

Within `LocalImageLoader`, fetching raw binary buffers over the network previously used `UIImage(data: data)?.preparingThumbnail(...)` as a fallback if `ImageDownsampler` returned `nil`. This violates the Zero-OOM architecture because `UIImage` loaded directly from raw uncompressed data expands 48 MP byte payloads into active RAM instantly. Merian enforces CoreGraphics bounds: if `ImageDownsampler.downsample` returns `nil`, the pipeline returns `nil` and abandons the raw RAM instantiation.

### SSD Download Streaming (`LocalImageLoader`)
When grid interfaces ingest hundreds of locally un-cached remote images, `URLSession.shared.data(from:)` caused RAM inflation by loading multi-megabyte blobs directly into system memory. Merian replaces `.data(from:)` with `.download(from:)`. The network payload streams into an ephemeral file URL on the SSD, which is passed directly to `ImageDownsampler.downsample(url:maxSize:)`. The temporary URL is deleted inside a `defer` block, preventing JetSam memory spikes and ensuring no raw image data touches RAM before downsampling.

### Swift 6 Primitive Extraction (`ImageCropProcessor`)
Passing `UIImage` objects directly into `Task.detached` closures violates Swift 6 strict concurrency rules because `UIImage` is non-Sendable and unsafe to cross actor boundaries. Merian prevents these traps by extracting thread-safe primitives (`targetImage.cgImage` and `targetImage.imageOrientation`) on the `@MainActor` before the detached task. These primitives are passed into the background processing pool for downsampling without triggering compiler warnings or runtime data races.

### Sequential CPU Starvation (`Analysis.swift`)
When submitting a multi-capture payload (e.g. multiple 12 MP captures) sequentially, `await`-ing `ImageCropProcessor.generateAutoCenterCrop(image:)` inside a standard `for` loop forces iOS to compute each crop on a single core, multiplying UI analysis latency.

**The Refactor**: Multi-capture evaluation runs inside a concurrent `withTaskGroup`, scheduling individual media transformations across separate hardware cores simultaneously. Sequential latency is eliminated during critical capture bursts.

### Massive Payload RAM Bypass (`PhotosPickerItem`)
To avoid JetSam OOM terminations when parsing large 48 MP ProRAW/HEIC payloads from the Camera Roll, Merian drops standard `.loadTransferable(type: Data.self)` memory reads. Standard payload expansion crashes foreground apps because the OS dumps the entire raw array into the CPU cache. Instead, the application uses an internal Swift struct (`ImageFileWrapper: Transferable`) with `FileRepresentation`, instructing Apple's `PhotosUI` pipeline to write bytes into a sandboxed `temporaryDirectory`. Calling `loadTransferable(type: ImageFileWrapper.self)` streams the payload under the RAM layer, allowing `.downsample(url:)` to map memory directly from the SSD.

### File System Sandboxing Limits (`LocalImageLoader`)
When grid interfaces ingest hundreds of locally un-cached APFS identifiers, executing synchronous `FileManager` and `UIImage(contentsOfFile:)` loads stutters the main thread and trips OS memory caps. Merian abstracts this through the isolated `LocalImageLoader` actor. It manages multi-tier RAM lookups inside an isolated concurrent queue, offloading all file reads to `ImageDownsampler.downsample()` within an encapsulated `Task.detached(priority: .userInitiated)`. Uncached `CGImageSourceCreateWithURL` fallback loads are removed, forcing the OS to honor `[kCGImageSourceShouldCache: false]` and CGImageSource size scaling, protecting device RAM.

The loader also implements a recursive network fallback pipeline to handle expired cloud images (e.g. targeted 90-day Free Tier domesticated edge function purge) or failed local disk fetches. `LocalImageLoader` splits the aggregated `fallbackUrl` by commas and cascades through R2, Wikipedia, and GBIF URLs sequentially, swallowing 404 errors and falling back to displaying the "Visuals archived" icon. This runs without blocking the Main Thread or leaking RAM.

The loader protects against "thundering herd" memory leaks. If the UI queries a missing image URL before cache limits evaluate, it tracks in-flight executions inside an `[String: Task<UIImage?, Never>]` dictionary, reducing duplicate loads to a single instance. To address an actor reentrancy vulnerability at the `await` suspension point, `LocalImageLoader` checks `if activeTasks[cacheKey] == fetchTask` inside its teardown `defer` block, ensuring concurrent task overwrites cannot cause an earlier task to wipe a newer active network request from the dictionary. `loadImage` returns `nil` when path strings are empty, rather than binding fresh `UUID` strings that previously bypassed cache logic and inflated `NSCache` allocations indefinitely.

### Task Capture Retain Cycles (`EnvironmentContextManager` & `ScansSearchManager`)
When firing background `@MainActor` executions inside persistent managers (like `reverseGeocode` or `performSearch`), default `Task { ... }` or `Task.detached { ... }` blocks implicitly capture `self` via a strong reference. When a `Task` mutates a local property (e.g., `self.geocodeCache[key]`) and is retained by the class (e.g., `self.searchTask = task`), this creates a retain cycle, permanently locking memory inside zombie ViewModels.

**The Refactor**: The codebase captures `[weak self]` inside `Task` / `Task.detached` closures, dropping the strong pointer. A `guard let self = self else { return }` check precedes any variable mutation, allowing Swift garbage collection to purge mapping classes upon background termination. Inside `ScansManager` (`searchTask`) and `EnvironmentContextManager` asynchronously created CoreLocation delegates generated runaway cross-actor memory leaks without closure guard isolations. These closures were refactored to extract lightweight parameters securely outside of the suspending boundary before safely accessing `@MainActor` variables locally.

### Sync Pipeline State Machine (`SyncStateManager`)
The original `SyncStateManager` used two independent properties (`isSyncing: Bool`, `pendingUploadCount: Int`) to represent upload progress, making it impossible to distinguish between uploading, inferencing, and finalizing phases — all of which appear "in progress" to the UI but have meaningfully different durations and semantics.

`SyncStateManager` was refactored to replace these with an exhaustive `SyncPhase` enum:

```swift
enum SyncPhase: Equatable {
    case idle
    case uploading(count: Int)   // PUT requests in flight to R2 staging
    case inferencing             // Gemini Edge function running
    case finalizing              // Writing LocalScanRecord, deleting OfflineQueuedScan
}
```

`OfflineQueueManager` transitions the phase at each boundary:
- `beginSync(itemCount:)` → `.uploading(count:)` when the batch is dispatched
- `beginInferencing()` → `.inferencing` immediately before calling `analyzeSubject`
- `beginFinalizing()` → `.finalizing` immediately before `processAndCleanupOfflineScan`
- `completeSync()` → `.idle` when all tasks settle or on connectivity loss

Computed shims (`isSyncing: Bool { phase.isActive }` and `pendingUploadCount: Int`) preserve backward compatibility for existing UI components.

### Centralized Magic Numbers (`MerianConfig`)
Batch sizes, fetch limits, pagination page sizes, storage thresholds, and retention windows were previously scattered as literals across `OfflineQueueManager`, `ScanRepository`, `ArchiveManager`, and `BackgroundDatabaseActor`. Divergence between these call sites introduced silent bugs (e.g., a fetch limit of 50 and a batch limit of 5 in different files with no linking comment).

All policy constants are now consolidated in `MerianConfig.swift` (Core/Utilities/):

```swift
enum MerianConfig {
    static let uploadBatchSize              = 5
    static let pendingScanFetchLimit        = 50
    static let historicalSyncPageSize       = 200
    static let collectionsSyncPageSize      = 100
    static let ingestCheckpointInterval     = 50
    static let diskSpaceThreshold: Int64    = 500 * 1024 * 1024
    static let archiveRescueWindowStartDays = 80
    static let archiveRescueWindowEndDays   = 88
}
```

`ArchiveManager`, `OfflineQueueManager+Sync`, and `ScanRepository` reference these constants exclusively. Tuning any policy requires a change in exactly one place.

### Transactional Scan Deletion (`eradicateScan`)
The original `eradicateScan` deleted image files from disk before committing the SwiftData changes. A save failure after file deletion left the `LocalScanRecord` intact in the database while its images were gone — a permanently broken state.

The operation was restructured to be database-first:
1. Tombstone any in-flight upload (`softDeleteQueuedScan`).
2. Insert `PendingCloudDeletionTask` + `modelContext.delete(record)`.
3. `modelContext.save()` — **if this fails, return immediately without touching disk**. State is fully consistent.
4. Only after a successful save: `FileIOActor.shared.deleteImages(at:)` asynchronously purges local `.jpg` files. Remote R2 URLs are skipped (they are not locally owned).

This ensures a save failure can never produce a state where the record exists but its images are missing.

### Historical Sync OOM Prevention — Page-at-a-Time Streaming (`ScanRepository`)
The previous `syncHistoricalScansDown` accumulated all cloud scan pages into a single `allScans: [HistoricalScanResponse]` array before any reconciliation began. At 10 k+ scans this buffer grows to 100 MB+ of decoded Swift structs on the `@MainActor` heap and triggers JetSam OOM kills on devices with limited RAM.

The fix streams pages one at a time: each fetched page is passed immediately to `HistoricalDatabaseActor.reconcileScanPage(responses:)` and released before the next network request begins. In-memory scan accumulation is now O(page_size) — always 200 records — regardless of how large the user's library grows.

```swift
let dbActor = HistoricalDatabaseActor(modelContainer: container)
var scanOffset = 0
while true {
    let page: [HistoricalScanResponse] = try await ...
        .range(from: scanOffset, to: scanOffset + pageSize - 1).execute().value
    if !page.isEmpty {
        await dbActor.reconcileScanPage(responses: page)
    }
    if page.count < pageSize { break }
    scanOffset += pageSize
}
await dbActor.syncCollectionsDown(remoteCollections: allCollections)
```

Inside `reconcileScanPage`, the full local ID set is computed once (ID-only column projection, `propertiesToFetch = [\.id]`) on the first call and cached as `cachedLocalIds: Set<String>?`. Subsequent page calls reuse the cached set, appending newly inserted IDs incrementally. `syncCollectionsDown` clears `cachedLocalIds` after the collection sync, releasing the set from memory.

### IN-Clause Batching (`HistoricalDatabaseActor.updateExistingScans`)
`updateExistingScans` builds a SwiftData `#Predicate { chunk.contains($0.id) }` to fetch only the local records that appear in the incoming cloud page. On large libraries, a single `#Predicate` with hundreds of IDs degrades the SQLite query planner — the planner stops using the primary key index for IN-clause lookups above a threshold and falls back to a full table scan.

The fix chunks `responseIds` into slices of 500 before building each predicate. Each chunk executes as a separate `FetchDescriptor` fetch, and results are concatenated. The `propertiesToFetch` projection (`[\.id, \.localImagePath, \.additionalImagePaths, \.referenceImageUrl, \.locationName, \.gpsLatitude, \.gpsLongitude, \.gpsElevation]`) is applied to every chunk, keeping column reads narrow across all batches.

### Idle CMMotionManager Battery Drain (`EnvironmentContextManager`)
`EnvironmentContextManager` previously instantiated a `CMMotionManager` and started device-motion updates at 100 Hz (`motionManager.startDeviceMotionUpdates(to:)`) during live location tracking. No code path ever consumed the motion data — there were no `motionManager.deviceMotion` reads and no handler closure attached to the update queue. The manager was running at 100 Hz purely to warm the sensor, burning CPU cycles and waking the processor 100 times per second for zero benefit.

`CMMotionManager`, the `import CoreMotion` statement, and all `motionManager.*` call sites have been removed from `EnvironmentContextManager`. The captured telemetry fields that were once intended to use motion data (`cameraPitchDegrees`, `compassHeading`) were already pruned from the `CaptureTelemetry` payload in a prior token-reduction pass. Removing the manager eliminates ~1–3% continuous CPU overhead and a measurable battery drain in the field.

### Synchronous `@MainActor` Execution (`ViewfinderIntelligence`)
`ViewfinderIntelligence.analyze(brightness:distance:lumaStdDev:)` performs only pure float comparisons — no I/O, no network, no heavy CPU work. Despite this, the previous implementation wrapped the entire method in a `Task.detached(priority: .userInitiated)` + a nested `defer { Task { @MainActor in self?.isAnalyzing = false } }` trampoline, allocating three Task heap objects per frame at 3 Hz (9 allocations/second) solely to run a handful of float comparisons.

Because the camera's `captureOutput` delegate already dispatches to `@MainActor` via `Task { @MainActor in }` before calling `analyze`, there is no work that needs to leave the main actor. The entire `Task.detached` infrastructure was removed. `analyze` and `updateHint` are now fully synchronous `@MainActor` methods:

```swift
// Before
func analyze(...) {
    Task.detached(priority: .userInitiated) { [weak self] in
        defer { Task { @MainActor [weak self] in self?.isAnalyzing = false } }
        ...
        await self.updateHint(.optimal)
    }
}
private func updateHint(_ hint: VUIHint) async { await MainActor.run { ... } }

// After
func analyze(...) {
    guard !isAnalyzing else { return }
    isAnalyzing = true
    defer { isAnalyzing = false }
    // Direct synchronous comparisons — no tasks
    if brightness < 0.20 { updateHint(.tooDark); return }
    updateHint(.optimal)
}
private func updateHint(_ hint: VUIHint) {  // synchronous
    if currentHint != hint { currentHint = hint }
    let newOptimalState = (hint == .optimal)
    if isOptimal != newOptimalState { isOptimal = newOptimalState }
}
```

The `isAnalyzing` flag is retained as a re-entrancy guard: if `analyze` is called again before the current `@MainActor` drain cycle finishes (e.g., via a rapid frame callback burst), the second call is dropped immediately rather than queueing work. `pauseAnalysis(for:)` also calls `updateHint(.optimal)` directly instead of wrapping it in a `Task { await updateHint }`.

### `trackFPS` Double-Registration Guard (`CameraManager`)
`CameraManager.trackFPS()` uses `withObservationTracking { _ = HardwareOrchestrator.shared.targetFPS } onChange:` to re-apply the framerate whenever `targetFPS` changes. The `onChange` closure calls `trackFPS()` recursively to re-arm the observation for the next change.

Without a guard, if `onChange` fired while a previous `trackFPS()` call had not yet completed its `withObservationTracking` setup (e.g., under rapid `targetFPS` mutations), multiple concurrent observations would accumulate — each one firing its own duplicate `onChange` on the next `targetFPS` write.

A boolean flag `isFPSTrackingRegistered` (marked `@ObservationIgnored` to exclude it from the `@Observable` tracking graph) prevents this:

```swift
private func trackFPS() {
    guard !isFPSTrackingRegistered else { return }
    isFPSTrackingRegistered = true
    withObservationTracking {
        _ = HardwareOrchestrator.shared.targetFPS
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isFPSTrackingRegistered = false
            self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
            self.trackFPS()
        }
    }
}
```

The flag is set before `withObservationTracking` registers and cleared inside `onChange` before the recursive `trackFPS()` call, ensuring exactly one active observation at any time.

### Concurrent Cloud Deletion Fan-Out with Batch Cap (`OfflineQueueManager`)
`syncPendingDeletions()` previously called `MerianNetworkClient.shared.deleteScan(scanId:)` for each queued `PendingCloudDeletionTask` in a serial `for` loop. Each deletion is an independent HTTP round-trip to the `delete-scan` Edge function (~300–600 ms each). For a user who deleted 10 scans offline, draining the queue required 3–6 seconds of sequential network time.

The loop was replaced with a `withTaskGroup` fan-out, batched in groups of 10 to prevent connection-pool exhaustion when users accumulate large queues:

```swift
let batchSize = 10
for batchStart in stride(from: 0, to: pendingTasks.count, by: batchSize) {
    let batch = Array(pendingTasks[batchStart..<min(batchStart + batchSize, pendingTasks.count)])
    let batchResults = await withTaskGroup(of: (String, Error?).self) { group in
        for task in batch {
            group.addTask {
                do {
                    try await MerianNetworkClient.shared.deleteScan(scanId: task.scanId)
                    return (task.scanId, nil)
                } catch { return (task.scanId, error) }
            }
        }
        var collected: [(String, Error?)] = []
        for await result in group { collected.append(result) }
        return collected
    }
    allResults.append(contentsOf: batchResults)
}
// Single context.save() after all batches are processed
```

A single `context.save()` runs after all batches settle, batching all successful tombstone removals into one write. For 10 deletions the wall time drops from ~4 s to ~600 ms; the cap prevents unbounded concurrency for users with hundreds of queued deletions.

### `@MainActor` Sort Offload (`ScansManager`)
When the Scans library has no active filter and the user changes the sort order, `ScansManager` previously re-sorted the full `allScans` array synchronously on the `@MainActor`. For a library with thousands of records a `localizedCaseInsensitiveCompare` sort can take 20–50 ms, producing a visible hitch during the library transition animation.

For the "no active filter" path — which operates on the full dataset — the sort is now offloaded to a `Task.detached(priority: .userInitiated)` worker. However, because `@Model` entities (`LocalScanRecord`) are non-`Sendable` and cannot safely cross isolation boundaries in Swift 6, they are mapped into lightweight primitive structures before offloading:

```swift
struct ScanSortPrimitive: Sendable {
    let id: String
    let timestamp: Date
    let commonName: String
}

let sortOpt = self.sortOption
let recordsPrimitives = self.allScans.map { ScanSortPrimitive(id: $0.id, timestamp: $0.timestamp, commonName: $0.commonName) }

let sortedIds = await Task.detached(priority: .userInitiated) {
    return ScansManager.executeDetachedSort(on: recordsPrimitives, sortOption: sortOpt).map { $0.id }
}.value

let finalSorted = sortedIds.compactMap { self.scanMap[$0] }
await MainActor.run { self.filteredScans = finalSorted }
```

The snapshot capture is a mapped primitive array, so the detached task holds no reference to the `@MainActor`-isolated `ScansManager` or un-safe model references. The main thread is only blocked for the final O(1) single-assignment `scanMap` hash resolution.

### O(N) `scanMap` Rebuild (`ScansManager`)
`ScansManager` maintains a `[String: LocalScanRecord]` dictionary (`scanMap`) for O(1) scan lookups by ID. After every `allScans` change, the previous implementation rebuilt this dictionary from scratch:

```swift
var newMap: [String: LocalScanRecord] = [:]
for scan in allScans { newMap[scan.id] = scan }
self.scanMap = newMap
```

For a library with thousands of records, rebuilding the full dictionary on every single insertion or deletion was O(n) CPU work on the `@MainActor`. Because the `allScans` diff is already computed (yielding `addedScans` and `removedIds`), the rebuild was replaced with incremental patching:

```swift
for scan in addedScans { self.scanMap[scan.id] = scan }
for id in removedIds   { self.scanMap.removeValue(forKey: id) }
```

This reduces the `scanMap` update from O(total library) to O(delta) — constant time for typical single-record mutations.

### Concurrent Archive Downloads with Sliding Window (`ArchiveManager`)
`initiatePrePurgeSync(pendingImages:)` previously downloaded images to the Photo Library in a serial `for` loop — one `PHPhotoLibrary.performChanges` call at a time. For users archiving dozens of images before a purge cycle, serial execution left NVMe bandwidth idle between operations.

The loop was replaced with a `withTaskGroup` sliding window capped at 3 concurrent in-flight downloads:

```swift
await withTaskGroup(of: Void.self) { group in
    var inFlight = 0
    var urlIterator = pendingImages.makeIterator()
    func enqueueNext() {
        while inFlight < 3, let url = urlIterator.next() {
            inFlight += 1
            group.addTask { try? await self.downloadToLocalLibrary(url: url) }
        }
    }
    enqueueNext()
    for await _ in group { inFlight -= 1; enqueueNext() }
}
```

`PHPhotoLibrary.performChanges` serialises internally on the Photos daemon side, so a higher cap would not improve throughput; 3 was chosen to saturate NVMe bandwidth without queuing more requests than the Photos subsystem can absorb simultaneously.
