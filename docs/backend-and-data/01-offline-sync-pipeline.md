# The Offline Synchronization Pipeline

Merian's core differentiator is treating off-grid nature encounters as a first-class citizen using native Apple offline architecture.

## How the Queue Works

### 1. Realtime Inference Mapper (`saveLiveScanRecord`)
When a user scans a subject with an active network connection, the Gemini response cascades back from the Edge node. To persist this inference against iOS RAM loss, `BackgroundDatabaseActor.saveLiveScanRecord(mappedData:localImagePaths:)` is invoked on its isolated `@ModelActor` thread. It accepts an array of local image filenames (relative paths in `URL.documentsDirectory`), inserts a `LocalScanRecord`, and calls `modelContext.save()`.

### 2. Inference Failure & Queueing (`enqueueCapture`)
When a hiker captures a photo off-grid, the telemetry (GPS, weather, elevation, subject distance, location name) is wrapped in a `CaptureTelemetry` struct and passed to `OfflineQueueManager.shared.enqueueCapture(imageDatas:telemetry:)`.

The queue engine spawns a `BackgroundTaskWrapper.execute` window so iOS grants extended time even when the app is backgrounded. All disk I/O runs off the main thread via `FileIOActor`. Once image bytes land in `URL.documentsDirectory`, a new `OfflineQueuedScan` SwiftData record is inserted with the full telemetry payload attached. On a successful `context.save()`, `AppTelemetry.trackOfflineQueued()` fires a `OfflineQueuedScan` TelemetryDeck signal to measure offline usage rate.

**UI Surface**: While a scan awaits network transit, its `OfflineQueuedScan` record is rendered at the **top** of the Scans Library grid (`ScansGrid`) with a dark overlay and `cloud.arrow.up.fill` icon. Tapping a queued tile shows a contextual toast — `"Scan is uploading..."` if the device is online, `"Analysis pending network connection"` if offline — rather than opening `InsightSheet`. Queued scans are excluded from batch-selection mode; their IDs cannot enter the `Share` / `Download` / `Delete` pipeline. The grid query filters out tombstoned (`isDeleted = true`) records at the SwiftData layer so cancelled uploads never resurface.

**The Circuit Breaker (`CircuitBreakerManager`)**: If repeated HTTP errors or timeouts cross a threshold, the circuit "trips", routing all new captures straight to the offline queue and bypassing useless network connections for a guaranteed zero-latency shutter experience.

**Free User Queue Cap**: To prevent scan hoarding, `enqueueCapture` checks the current `OfflineQueuedScan` count on the `@MainActor` before inserting. If a free user already has `UsageManager.shared.maxFreeScansPerDay` (2) items queued, the new item is rejected and any files written to disk are cleaned up atomically — the telemetry signal is **not** fired in this case. Pro users have no queue depth cap.

### 3. Network Awakening (`NWPathMonitor`)
The `NWPathMonitor` instance listens to the cellular stack continuously. When a connection flips `.satisfied`, the manager debounces for 1,000 ms to let the OS networking stack fully settle before starting processing.

### 4. Background Processing & Batch Uploads
The manager guards against expedition mode, connectivity, and an in-flight sync before proceeding. Free users are additionally gated by their daily scan quota: `syncPendingScans` returns immediately if `UsageManager.shared.canPerformScan(isProActive: false)` is false. For free users the batch is further capped to `UsageManager.shared.freeScansRemaining` items, and `UsageManager.shared.consumeScan()` is called once per queued item at upload-scheduling time so the daily limit is enforced through the background URLSession path.

`SyncStateManager.shared.beginSync(itemCount:)` is called to transition the shared state machine to `.uploading(count:)` and broadcast the exact batch volume to the UI.

Batch sizing is governed by `MerianConfig`:
- **`pendingScanFetchLimit`** (50): maximum `OfflineQueuedScan` records fetched per cycle via `BackgroundDatabaseActor.fetchPendingScans(limit:)`.
- **`uploadBatchSize`** (5): maximum scans dispatched to R2 staging per cycle for Pro users (`.prefix(MerianConfig.uploadBatchSize)`). Free users use `freeScansRemaining` as their effective batch limit.

Active upload tasks are deduplicated against `backgroundSession.allTasks` before dispatching, preventing double-uploads on relaunch. Each image is first copied to a temp file in `URL.cachesDirectory` (`<scanId>_<imageIndex>_temp_upload.webp`) before being handed to `URLSession.uploadTask(with:fromFile:)`. The `URLRequest` carries a `Content-Type: image/webp` header, which must match the `image/webp` Content-Type baked into the Cloudflare R2 pre-signed URL by the `generate-upload-urls` Edge function. The client generates deterministic filenames using the local `scanId` and file path; these predictably formatted names combined with the **lowercased UUID** of the authenticated user construct the exact sequence required for the `analyzeSubject` inference step later. The OS background session owns byte transmission from here, handling interruption and resume transparently.

**`ScanUploadItem` struct**: The flat arrays previously used to pass per-image metadata (`fileNames`, `fileURLs`, `scanIDs`, `imageIndices`) have been consolidated into a typed `ScanUploadItem` struct. Each instance carries `scanId`, `imageIndex`, `fileName`, and `fileURL` together, eliminating the class of flat-index bug where indexing into four parallel arrays at position `N` could silently return mismatched values for multi-scan batches.

**`isUploaded` flag (SchemaV32)**: `OfflineQueuedScan` carries a `isUploaded: Bool` field (default `false`, added in a V31→V32 lightweight migration). After the last image for a scan receives HTTP 200 and before `runInferencePipeline` is called, the flag is set to `true` and saved. `fetchPendingScans` filters these out (`!$0.isUploaded`) so a re-upload is never attempted. On connectivity restore **and on every app foreground** (`handleActivePhase`), `replayInferenceForUploadedScans()` queries for `isUploaded == true && isDeleted == false` records and re-enters them directly into `runInferencePipeline` — bypassing the entire upload path. The foreground call site is mandatory: `NWPathMonitor` only fires on connectivity *changes*, so a user returning to the app on an already-stable connection would never trigger the connectivity handler, leaving the scan stuck forever. Calling it in both places closes the gap where an app kill between the last HTTP 200 and the inference Edge call completion left scans permanently stuck in the offline queue.

> **Critical**: The `taskDescription` for each upload task is `"\(scanId)_\(imageIndex)"` where `imageIndex` is the **per-scan** slot (0…N−1 for an N-image scan). It must NOT use the flat position across the entire batch. `processUploadCompletion` fires the inference trigger when `indexPart == localImagePaths.count - 1` — a per-scan comparison. Using the flat batch index instead caused every scan beyond the first in a batch to silently skip inference forever, leaving `OfflineQueuedScan` records stuck indefinitely.

**Concurrent staging (`withTaskGroup`)**: Pre-flight guards — URL validation, file existence checks, and tombstoning — remain serial. Once all guards clear, the `FileManager.copyItem` and `uploadTask` creation for each image are fanned out concurrently via `withTaskGroup`. For a 3-image scan this eliminates 500 ms–2 s of head-of-line blocking before the background session takes ownership.

**Exponential backoff for `generateUploadURLs` failures**: When the pre-signed URL request fails, `syncPendingScans` schedules a `retryBackoffTask` that waits before the next attempt. The delay doubles on each consecutive failure (1 s → 2 s → 4 s → … capped at 30 s), stored in `OfflineQueueManager.uploadRetryDelay`. The delay resets to 0 on any successful URL generation. The retry task is cancelled immediately on connectivity loss so stale retries never fire while offline.

All this payload work runs inside a `BackgroundTaskWrapper.execute` block so iOS does not suspend the process during disk I/O or URL generation. The expiration handler for this block **must reset `isSyncing = false`** before calling `SyncStateManager.shared.completeSync()`. If iOS expires the background task before the URLSession upload tasks are dispatched (e.g., during extreme memory pressure), `isSyncing` would otherwise stay `true` permanently, permanently blocking all future `syncPendingScans()` calls until the next app relaunch.

### 5. Upload Lifecycle via URLSession Delegates
- **Step A**: iOS transmits the staged file to the Cloudflare R2 staging bucket.
- **Step B**: `urlSessionDidFinishEvents(forBackgroundURLSession:)` fires, invoking the `AppDelegate` completion handler so the system knows it's safe to suspend.
- **Step C**: `urlSession(_:task:didCompleteWithError:)` fires. Non-Sendable task properties are captured as local immutable variables before crossing the actor boundary. The handler cleans up the temp staging file unconditionally, then:
  - **Transport errors — file missing** (`NSURLErrorFileDoesNotExist`, `NSURLErrorCannotOpenFile`): terminal — tombstone immediately via `softDeleteQueuedScan`.
  - **Transport errors — transient connectivity** (`NSURLErrorTimedOut`, `NSURLErrorNetworkConnectionLost`, `NSURLErrorNotConnectedToInternet`, `NSURLErrorDataNotAllowed`, `NSURLErrorInternationalRoamingOff`): retain in queue, increment in-memory `uploadRetryCount[scanId]`. After `OfflineQueueManager.maxUploadRetries` (3) consecutive failures the scan is tombstoned. The counter resets to zero on the next successful upload or on app restart.
  - **Transport errors — other**: logged, retained in queue.
  - **HTTP 403 / 401**: Terminal — auth failure, tombstone.
  - **HTTP 429 / 5xx**: Recoverable — retain in queue for next connectivity cycle.
  - **HTTP 4xx (non-403/401/429)**: Terminal — tombstone.
  - **HTTP 200**: Clear the retry counter for this scan ID, then proceed to inference.

  > **Failed Upload Notifications**: Any pathway that natively tombstones a queue payload (due to transient exhaustion, HTTP 4xx permanence, or explicit file-system corruption) proactively fires a `PushNotificationManager.shared.sendUploadFailedNotification()` alert containing an isolated `{"type": "failure"}` payload if the application is currently backgrounded, allowing the user to gracefully intercept lost sync cycles without inadvertently routing to deleted `InsightSheet` indices.
- **Step D**: `SyncStateManager.shared.beginInferencing()` transitions the state machine to `.inferencing`. The inference Edge function (`analyzeSubject`) is called with the R2 object keys. Inference is suppressed until the **last** image file for the scan has landed (guarded by `indexPart == localImagePaths.count - 1`), preventing partial-payload submissions. To pass the server's case-sensitive IDOR block, the authenticated user's UUID embedded within these keys is strictly lowercased.
- **Step E**: `SyncStateManager.shared.beginFinalizing()` transitions to `.finalizing`. `BackgroundDatabaseActor.processAndCleanupOfflineScan` decodes the JSON, then inserts `LocalScanRecord` and deletes the `OfflineQueuedScan` in a **single atomic `modelContext.save()`**. Previously two separate saves were used; merging them eliminates the ghost-record window where both the `LocalScanRecord` (already inserted) and the `OfflineQueuedScan` (not yet deleted) were simultaneously visible in the composite library grid. The `OfflineQueuedScan` removal uses `modelContext.delete(model:where:)` — a bulk delete that avoids faulting the full object into memory. On inference failure, local image files are deleted via `FileIOActor.shared.deleteImages(at:)`.
- **UUID Terminality**: `OfflineQueueManager` strictly awaits the resolved finalized database UUID from `dbActor.processAndCleanupOfflineScan()` (the "Terminal ID"). This effectively terminates the ephemeral offline properties forever. Downstream notifications or `.appDidEnterActivePhaseWithScan` routes ALWAYS execute traversing the Terminal ID, guaranteeing user interactions bind directly to `.biological` persistence blocks instead of ghost records.
- **Long-lived actors**: `BackgroundDatabaseActor` and `ProfileDatabaseActor` are now stored as persistent properties (`_inferenceDbActor`, `_profileDbActor`) on `OfflineQueueManager` and initialized lazily on first use. Reusing a single actor instance across consecutive completions avoids repeated actor allocation + `ModelContext` setup. Each `@ModelActor` serializes concurrent calls through its executor automatically, so rapid burst completions queue safely.
- **Step F**: `GamificationManager.shared.recordNewSpeciesDiscovered()` and push notification fire immediately per completion. `ProfileDatabaseActor.calculateAwards()` and `GamificationManager.shared.evaluateAchievementsForNotifications(awards:)` are **debounced** — a `awardsDebounceTask` is cancelled and rescheduled 0.5 s after each completion. For a 5-scan burst this collapses five `calculateAwards()` passes (each a full scan history read) into one. The `UserDefaultsKeys.hasUnseenScan` flag is set immediately to trigger the MainTabBar red dot without waiting for the debounce window.

**Wireless Offline Weather Hydration (Concurrent)**: If the scan was captured without a network connection and lacks `weatherCondition`, the pipeline retroactively calls `EnvironmentContextManager.shared.fetchHistoricalContext(location:date:)` using the stored GPS coordinates and capture timestamp to reconstruct the weather context for that moment.

This WeatherKit backfill and the `analyzeSubject` inference call run **concurrently via `async let`**:

```swift
async let weatherContext = needsWeather
    ? EnvironmentContextManager.shared.fetchHistoricalContext(location:date:)
    : nil
async let inferenceResult = MerianNetworkClient.shared.analyzeSubject(
    r2ObjectKeys: resolvedKeys, base64ImageDatas: nil, telemetry: baseTelemetry)
let (historicalContext, resultData) = try await (weatherContext, inferenceResult)
```

Previously, the WeatherKit call was `await`ed sequentially before inference — adding 200–800 ms of WeatherKit latency to the hot path for every offline scan that needed weather backfill. Weather is optional metadata; the scan result must not be gated on it. If the weather call fails or returns nil, inference proceeds with the original telemetry unchanged.

When all background upload tasks settle, `SyncStateManager.shared.completeSync()` transitions to `.idle`. If `unsyncedItemsCount > 0` after a batch, `syncPendingScans()` is called recursively to drain the queue automatically.

## The Sync State Machine (`SyncStateManager`)

`SyncStateManager` is an `@MainActor @Observable` singleton that exposes the current phase of the upload pipeline to UI components. It replaced the original pair of `isSyncing: Bool` + `pendingUploadCount: Int` booleans with an exhaustive `SyncPhase` enum:

```swift
enum SyncPhase: Equatable {
    case idle
    case uploading(count: Int)  // Image files are being PUT to R2 staging
    case inferencing            // Gemini Edge function is running
    case finalizing             // Writing LocalScanRecord, cleaning up queue
}
```

Backward-compatible computed shims (`isSyncing: Bool`, `pendingUploadCount: Int`) are preserved for existing UI components. New UI can branch on `phase` directly for richer progress display. `OfflineQueueManager` is the only writer.

## Deletions in Offline Environments

Scan permanence and user privacy require that explicitly deleted datasets are permanently erased, even fully offline.

### 1. Transactional Destruction (`ScanRepository.eradicateScan`)
Deletion follows a strict ordering designed to guarantee consistency: **database operations commit first, file deletion runs after**.

1. `offlineQueue.softDeleteQueuedScan(scanId:)` — tombstone any in-flight upload.
2. Insert `PendingCloudDeletionTask` + `modelContext.delete(record)` + `modelContext.save()` — **atomic DB commit**. If the save fails, the method returns immediately without touching disk; state remains fully consistent.
3. `FileIOActor.shared.deleteImages(at:)` — purge local `.webp` files asynchronously, skipping remote R2 URLs (those are cloud-owned). Runs only after the DB commit succeeds.
4. `offlineQueue.syncPendingDeletions()` async — attempt the cloud deletion immediately; retry on next connectivity cycle.

### 2. Cloud Deletion Tasking (`PendingCloudDeletionTask`)
A `PendingCloudDeletionTask` SwiftData record is inserted at deletion time, queuing the `scanId` for cloud erasure. The UI executes an optimistic delete immediately.

### 3. Upload Interception (`softDeleteQueuedScan` & `deleteQueuedScan`)
If the scan being destroyed is actively queued for upload, invoking `deleteQueuedScan(scanId:)` natively cancels isolated URLSession transmission streams outright globally and enforces disk removal boundaries instantly. The secondary `softDeleteQueuedScan(scanId:)` tombstones the `OfflineQueuedScan` record (`isDeleted = true`), structurally excluding it from future sync attempts across disconnected logic flows. Records are hard-purged later via `purgeSoftDeletedRecords()`.

### 4. Network Polling Sync (`syncPendingDeletions`)
On `NWPathMonitor` reconnect, `syncPendingDeletions()` drains the `PendingCloudDeletionTask` queue. The initial SwiftData fetch is bounded to **200 records** (`fetchLimit = 200`) to prevent a user returning from a long offline period from loading hundreds of tasks into the V8 heap at once; records beyond that limit are processed on the next reconnect cycle. Deletion requests are fanned out **concurrently in batches of 10** via `withTaskGroup`. Each batch fans out all its child tasks simultaneously, collecting results before the next batch begins. A single `modelContext.save()` runs once after all batches complete, removing all successfully confirmed tasks in one write. Capping at 10 concurrent Edge calls prevents connection-pool exhaustion; for a user with 10 offline deletions the wall time still drops from ~4 s (serial) to ~600 ms (concurrent).

`NetworkError.invalidResponse` (resource already gone) is treated as terminal and the task is removed. All other errors retain the task for the next cycle. The result-processing loop builds a `[String: PendingCloudDeletionTask]` dictionary once before iterating results, making each lookup O(1) instead of the previous O(n) linear scan (was O(n²) overall for large batches).

## The Collections Pipeline

Merian supports creating custom `ScanCollection` buckets while fully disconnected.

1. **Entity Instantiation**: A user taps "New Collection" — a `ScanCollection` is inserted into SwiftData and `modelContext.save()` is called immediately. The collection is durable locally from this point.
2. **Background Upload**: `OfflineQueueManager.shared.syncCollections()` is triggered, pushing `SyncCollectionPayload` arrays to the `sync-collections` Edge function. The upload is wrapped in `BackgroundTaskWrapper.execute(name: "CollectionSync")` so iOS grants additional background time if the user closes the app immediately after creating a collection.

   **Diff-based Edge sync**: The `sync-collections` Deno function handles explicitly passed soft-deletions (`is_deleted: true` or `isDeleted: true`) securely before performing a set-based delta sync for `collection_scans` membership. It computes the desired membership from the client payload and diffs it against the current Supabase state. Only the delta (rows to add and rows to remove) is written. We intentionally do not use implicit destructive diffs for whole collections to prevent devices with missing histories from obliterating remote databases. The Edge function actively pre-filters any mappings for scans that haven't synced to the cloud yet, preventing Postgres FK constraint violations from aborting the overarching database chunk. Removals are grouped by `collection_id`. A `MAX_COLLECTIONS = 200` cap is enforced server-side.
   
   **Strict Concurrency Gating**: To prevent race conditions where out-of-order network requests resurrect deleted collections, `OfflineQueueManager.shared.syncCollectionsIfPending()` is heavily gated by an `isCollectionSyncing` boolean latch. If a user modifies and then immediately deletes a collection, the initial `UPSERT` background task fully completes before the `DELETE` task is allowed to fire. This guarantees that `is_deleted: true` always reaches the Edge function last.
   
   **Explicit Local Tombstone Destruction**: When a collection is marked for deletion in the UI, `CollectionActionAlertModifier` explicitly captures underlying SwiftData constraint validations using a strict `do-catch` block around `modelContext.save()` and logs any failures to `MerianLog.data`. This provides a reliable guarantee that the `isDeleted = true` assignment persists to disk. Once the Edge sync returns HTTP 200 indicating successful cloud deletion for the payload, the `BackgroundDatabaseActor` permanently hard deletes the ghost `ScanCollection` record from SwiftData to ensure it cannot resurrect or linger in UI state.
   
   > [!IMPORTANT]
   > **Apple Sign-In (`ES256`) and Edge Functions:** Merian utilizes Apple Sign-In on iOS, which issues JWTs signed with `ES256` rather than the typical `HS256`. Supabase's Kong API Gateway natively rejects `ES256` tokens by default, resulting in silent **401 Unauthorized** errors that do not even reach the Deno runtime. To solve this, all Edge Functions **must** be deployed with the `--no-verify-jwt` flag. This bypasses Kong's fast-path validation and allows our internal `requireAuth` wrapper in `_shared/auth.ts` to natively validate the token using `supabaseClient.auth.getUser()`, which natively supports `ES256`.

3. **Resilient Sync Architecture**: `syncCollections()` no-ops when offline or unauthenticated. Collections created in these states remain in SwiftData and are picked up by the push-before-pull ordering described in step 4.
4. **Push-Before-Pull Ordering**: `syncHistoricalScansDown` calls `pushCollectionsToEdge()` — uploading all local collections to Supabase — **before** fetching the cloud collection list. This guarantees that any collection created while offline or before authentication completes is in the cloud before the reconciliation delete pass runs. Without this ordering, a collection that was never successfully uploaded would be treated as "obsolete" and deleted on next launch.
5. **Reconciliation**: After all scan pages have been streamed, `syncHistoricalScansDown` calls `HistoricalDatabaseActor.syncCollectionsDown(remoteCollections:)`. Collections present in the cloud response are upserted. **Inbound Tombstone Shield**: If the cloud response erroneously includes a collection that is already marked as `isDeleted = true` locally, the cloud response is ignored. This protects against delayed edge functions resurrecting a deleted entity. Collections absent from the cloud response and not named "Favorites" are deleted locally. Because step 4 guarantees every local collection is already in the cloud, the delete pass only removes collections the user genuinely deleted on another device. `syncCollectionsDown` also clears the actor's `cachedLocalIds` set, releasing the accumulated ID set from memory at the end of the sync cycle.
6. **FK Safety**: If the assigned scan UUID hasn't reached Cloudflare R2 yet when the collection payload arrives, the Edge node safely absorbs the Postgres foreign-key rejection. The collection itself is saved. On the next `pushCollectionsToEdge` call the scan reference resolves.

**Critical ordering rule:** The push (`pushCollectionsToEdge`) must always complete before the pull (cloud collections fetch) in `syncHistoricalScansDown`. Reversing this order causes local-only collections to be treated as obsolete and deleted.

## Restoring Historical Workloads (Rehydration)

To support multi-device access and app reinstalls, `ScanRepository.syncHistoricalScansDown(modelContext:)` pulls cloud history and reconciles it with local SwiftData.

### Paginated Cloud Fetch
Both the scans and collections queries are paginated via Supabase PostgREST's `.range(from:to:)` to prevent OOM on accounts with large histories:
- Scans: pages of `MerianConfig.historicalSyncPageSize` (200) records
- Collections: pages of `MerianConfig.collectionsSyncPageSize` (100) records

Each loop runs until the returned page is smaller than the page size, indicating the last page.

### Streaming Reconciliation (`reconcileScanPage` + `syncCollectionsDown`)
A single `HistoricalDatabaseActor` instance is created and each fetched page is processed immediately via `reconcileScanPage(responses:)` before the next page is fetched. This prevents the full cloud scan list from accumulating in memory — at 10 k+ scans, the old "accumulate-then-reconcile" approach could hold 100 MB+ of `HistoricalScanResponse` structs in RAM simultaneously and trigger JetSam OOM kills.

Each page passes through these steps inside the actor:

1. **ID Page Bounding Fetch (per page)**: Inside `reconcileScanPage`, the actor restricts fetching strictly down to the `responseIds` provided in the current PostgREST batch (typically `200` items). It shards this id-set into bounds no larger than 500, and explicitly issues an array intersection query `FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunk.contains($0.id) })`. *CRITICAL QUIRK: We must execute this via `try modelContext.fetchIdentifiers(desc)` rather than `fetch()`. On iOS 17+, invoking `.fetch()` via `#Predicate` natively dynamically unboxes the generic map behind the `@ModelActor` barrier, which completely fails to map back to the `typealias LocalScanRecord` (crashing with `Failed to cast model MerianSchemaV22... to LocalScanRecord`). Extracting identifiers safely and individually reinstantiating `modelContext.model(for: id)` is completely immune to this macro casting panic.*
2. **`updateExistingScans`**: Receives only the local record sets securely matched from the previous bounding fetch. Updates: `localImagePath`, `additionalImagePaths`, `referenceImageUrl`, GPS fields, `locationName`, taxonomic ranks (`taxonomyKingdom` through `taxonomyGenus`), and `customTags`. Backfills `imageQualityScore` when the local value is `nil` and the cloud `HistoricalScanResponse.image_quality_score` is non-nil (one-directional — never overwrites an existing local value). Saves only if any field actually changed. Note: Overwriting `customTags` defaults to cloud-wins reconciliation, erasing offline-only tag additions if they failed to push before the downward sync.
3. **`ingestScans`**: Inserts new `LocalScanRecord` rows for cloud records absent locally entirely. Checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (50) records to limit data loss if a background task is killed mid-ingest. *Crucially, it defaults `hasBeenViewed: true` when instantiating the record to prevent re-installing users from being inundated with thousands of "New" badges on their historical archive.*
4. **`syncCollectionsDown`**: Called once, after all scan pages have streamed. Delegates to `syncCollections` (fetches only the `ScanCollection` records and local scan references; upserts collections *except* those marked as `isDeleted` locally which block cloud overrides). It differentially merges scan relationships to protect offline queued scans from being overwritten, and deletes obsolete non-Favorites collections. **Precondition**: `syncHistoricalScansDown` always calls `pushCollectionsToEdge()` before this step so that the cloud collection list already contains every local collection — the delete pass therefore only removes genuine remote deletions, never unsynced local creations.

### Lifecycle Execution Hook
This synchronization fires the moment a user transitions from Ghost → Authenticated (inside `SupabaseManager.setupAuthStateListener`) and whenever the app recovers foreground state (`AppDIContainer.handleActivePhase`).

### Ghost-Rendering Image Optimization
Historical scans restore their Cloudflare R2 URLs directly into `localImagePath` and `additionalImagePaths` when the physical photo is absent locally. `LocalImageLoader` evaluates HTTP boundaries implicitly, treating remote R2 URLs exactly like local `URL.documentsDirectory` paths — routing async cache fetches transparently so the user downloads only what is on screen.

### SwiftData Typealias UI Quirks
When building UI that references the `LocalScanRecord` typealias, **never attach a `#Predicate` to a `@Query` property wrapper directly** if the predicate executes string evaluations across the versioned schema boundaries. The same internal macro resolution that faults in the background actor will crash the Main thread upon unboxing `_wrappedValue`. 
Instead, fetch unbounded records and filter locally:
```swift
@Query(sort: \.timestamp) private var rawRecords: [LocalScanRecord]
private var cleanRecords: [LocalScanRecord] { rawRecords.filter { $0.isBiological } }
```
## Centralized Configuration (`MerianConfig`)

All magic numbers governing the sync pipeline live in `MerianConfig.swift` (Core/Utilities):

| Constant | Value | Purpose |
|---|---|---|
| `uploadBatchSize` | 5 | Scans dispatched per sync cycle |
| `pendingScanFetchLimit` | 50 | `OfflineQueuedScan` records fetched per cycle |
| `historicalSyncPageSize` | 200 | Records per page for scans rehydration |
| `collectionsSyncPageSize` | 100 | Records per page for collections rehydration |
| `ingestCheckpointInterval` | 50 | SwiftData save frequency during bulk ingest |
| `diskSpaceThreshold` | 500 MB | Minimum free space before archive/rescue operations |
| `archiveRescueWindowStartDays` | 80 | Free Tier ASP rescue window start |
| `archiveRescueWindowEndDays` | 88 | Free Tier ASP rescue window end |
