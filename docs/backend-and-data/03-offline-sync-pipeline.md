# The Offline Synchronization Pipeline

Merian's core differentiator is treating off-grid nature encounters as a first-class citizen using native Apple offline architecture.

## How the Queue Works

### 1. Realtime Inference Mapper (`saveLiveScanRecord`)
When a user scans a subject with an active network connection, the Gemini response cascades back from the Edge node. To persist this inference against iOS RAM loss, `BackgroundDatabaseActor.saveLiveScanRecord(mappedData:localImagePaths:)` is invoked on its isolated `@ModelActor` thread. It accepts an array of local image filenames (relative paths in `URL.documentsDirectory`), inserts a `LocalScanRecord`, and calls `modelContext.save()`.

### 2. Inference Failure & Queueing (`enqueueCapture`)
When a hiker captures a photo off-grid, the telemetry (GPS, weather, elevation, subject distance, location name) is wrapped in a `CaptureTelemetry` struct and passed to `OfflineQueueManager.shared.enqueueCapture(imageDatas:telemetry:)`.

The queue engine spawns a `BackgroundTaskWrapper.execute` window so iOS grants extended time even when the app is backgrounded. All disk I/O runs off the main thread via `FileIOActor`. Once image bytes land in `URL.documentsDirectory`, a new `OfflineQueuedScan` SwiftData record is inserted with the full telemetry payload attached.

**The Circuit Breaker (`CircuitBreakerManager`)**: If repeated HTTP errors or timeouts cross a threshold, the circuit "trips", routing all new captures straight to the offline queue and bypassing useless network connections for a guaranteed zero-latency shutter experience.

**Free User Queue Cap**: To prevent scan hoarding, `enqueueCapture` checks the current `OfflineQueuedScan` count on the `@MainActor` before inserting. If a free user already has `UsageManager.shared.maxFreeScansPerDay` (2) items queued, the new item is rejected and any files written to disk are cleaned up atomically. Pro users have no queue depth cap.

### 3. Network Awakening (`NWPathMonitor`)
The `NWPathMonitor` instance listens to the cellular stack continuously. When a connection flips `.satisfied`, the manager debounces for 1,000 ms to let the OS networking stack fully settle before starting processing.

### 4. Background Processing & Batch Uploads
The manager guards against expedition mode, connectivity, and an in-flight sync before proceeding. Free users are additionally gated by their daily scan quota: `syncPendingScans` returns immediately if `UsageManager.shared.canPerformScan(isProActive: false)` is false. For free users the batch is further capped to `UsageManager.shared.freeScansRemaining` items, and `UsageManager.shared.consumeScan()` is called once per queued item at upload-scheduling time so the daily limit is enforced through the background URLSession path.

`SyncStateManager.shared.beginSync(itemCount:)` is called to transition the shared state machine to `.uploading(count:)` and broadcast the exact batch volume to the UI.

Batch sizing is governed by `MerianConfig`:
- **`pendingScanFetchLimit`** (50): maximum `OfflineQueuedScan` records fetched per cycle via `BackgroundDatabaseActor.fetchPendingScans(limit:)`.
- **`uploadBatchSize`** (5): maximum scans dispatched to R2 staging per cycle for Pro users (`.prefix(MerianConfig.uploadBatchSize)`). Free users use `freeScansRemaining` as their effective batch limit.

Active upload tasks are deduplicated against `backgroundSession.allTasks` before dispatching, preventing double-uploads on relaunch. Each image is first copied to a temp file in `URL.cachesDirectory` (`<scanId>_<index>_temp_upload.jpg`) before being handed to `URLSession.uploadTask(with:fromFile:)`. The OS background session owns byte transmission from here, handling interruption and resume transparently.

All this payload work runs inside a `BackgroundTaskWrapper.execute` block so iOS does not suspend the process during disk I/O or URL generation.

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
- **Step D**: `SyncStateManager.shared.beginInferencing()` transitions the state machine to `.inferencing`. The inference Edge function (`analyzeSubject`) is called with the R2 object keys. Inference is suppressed until the **last** image file for the scan has landed (guarded by `indexPart == localImagePaths.count - 1`), preventing partial-payload submissions.
- **Step E**: `SyncStateManager.shared.beginFinalizing()` transitions to `.finalizing`. `BackgroundDatabaseActor.processAndCleanupOfflineScan` decodes the JSON, inserts `LocalScanRecord`, deletes the `OfflineQueuedScan`, and saves. On inference failure, local image files are deleted via `FileIOActor.shared.deleteImages(at:)`.
- **Step F**: `ProfileDatabaseActor.calculateAwards()` recalculates the full achievement state. Because awards can trigger on any condition over the scan history (time-of-day, species counts, ecology types, etc.) — not just new discoveries — this runs after every successful inference. `GamificationManager.shared.recordNewSpeciesDiscovered()` is additionally called when `isNewDiscovery == true`. A push notification is queued if the app is backgrounded.

**Wireless Offline Weather Hydration**: If the scan was captured without a network connection and lacks `weatherCondition`, the pipeline retroactively calls `EnvironmentContextManager.shared.fetchHistoricalContext(location:date:)` using the stored GPS coordinates and capture timestamp before triggering inference, perfectly reconstructing the weather context for that moment.

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
3. `FileIOActor.shared.deleteImages(at:)` — purge local `.jpg` files asynchronously, skipping remote R2 URLs (those are cloud-owned). Runs only after the DB commit succeeds.
4. `offlineQueue.syncPendingDeletions()` async — attempt the cloud deletion immediately; retry on next connectivity cycle.

### 2. Cloud Deletion Tasking (`PendingCloudDeletionTask`)
A `PendingCloudDeletionTask` SwiftData record is inserted at deletion time, queuing the `scanId` for cloud erasure. The UI executes an optimistic delete immediately.

### 3. Upload Interception (`softDeleteQueuedScan`)
If the scan being destroyed is actively queued for upload, `softDeleteQueuedScan` tombstones the `OfflineQueuedScan` record (`isDeleted = true`), excluding it from future sync attempts. Records are hard-purged later via `purgeSoftDeletedRecords()`.

### 4. Network Polling Sync (`syncPendingDeletions`)
On `NWPathMonitor` reconnect, `syncPendingDeletions()` drains the `PendingCloudDeletionTask` queue, calling the `delete-scan` Edge function for each. `NetworkError.invalidResponse` (resource already gone) is treated as terminal and the task is removed. All other errors retain the task for the next cycle.

## The Collections Pipeline

Merian supports creating custom `ScanCollection` buckets while fully disconnected.

1. **Entity Instantiation**: A user taps "New Collection" — a `ScanCollection` is inserted into SwiftData with a UUID immediately.
2. **Offline-Safe Mapping**: The user groups a `LocalScanRecord` into the collection. `OfflineQueueManager.shared.syncCollections()` runs in the background, pushing `SyncCollectionPayload` arrays to the `sync-collections` Edge function.
3. **Resilient Sync Architecture**: If the assigned scan UUID hasn't reached Cloudflare R2 yet, the Edge Node safely absorbs the Postgres foreign-key rejection. The collection itself saves. On subsequent app foreground cycles, `pushCollectionsToEdge` naturally retries and resolves the reference.
4. **Rehydration**: `syncHistoricalScansDown` fetches `[CloudCollectionResponse]` and reconciles them against local `ScanCollection` records. Obsolete collections (absent from the cloud response and not "Favorites") are deleted.

## Restoring Historical Workloads (Rehydration)

To support multi-device access and app reinstalls, `ScanRepository.syncHistoricalScansDown(modelContext:)` pulls cloud history and reconciles it with local SwiftData.

### Paginated Cloud Fetch
Both the scans and collections queries are paginated via Supabase PostgREST's `.range(from:to:)` to prevent OOM on accounts with large histories:
- Scans: pages of `MerianConfig.historicalSyncPageSize` (200) records
- Collections: pages of `MerianConfig.collectionsSyncPageSize` (100) records

Each loop runs until the returned page is smaller than the page size, indicating the last page.

### Single-Actor Reconciliation (`reconcileAllHistoricalData`)
Once all pages are accumulated, a single `HistoricalDatabaseActor` instance is created and `reconcileAllHistoricalData(responses:collections:)` is called **once**. This replaces the previous architecture of three sequential `await` calls to the same actor, which introduced two unnecessary actor-boundary crossings. All reconciliation work now happens inside one actor invocation:

1. **ID projection fetch**: Fetches only `\.id` from all local `LocalScanRecord` rows (minimal column projection) to compute the existing-ID set cheaply off the main thread.
2. **`updateExistingScans`**: Fetches only local records whose IDs appear in the cloud response (predicate-scoped + `propertiesToFetch` projection). Updates: `localImagePath`, `additionalImagePaths`, `referenceImageUrl`, GPS fields, `locationName`. Saves only if any field actually changed.
3. **`ingestScans`**: Inserts new `LocalScanRecord` rows for cloud records absent locally. Checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (50) records to limit data loss if a background task is killed mid-ingest.
4. **`syncCollections`**: Fetches only `ScanCollection` records and only the local scan records referenced by the incoming collections (predicate-scoped). Upserts collections, rebuilds scan relationships, deletes obsolete non-Favorites collections.

### Lifecycle Execution Hook
This synchronization fires the moment a user transitions from Ghost → Authenticated (inside `SupabaseManager.setupAuthStateListener`) and whenever the app recovers foreground state (`AppDIContainer.handleActivePhase`).

### Ghost-Rendering Image Optimization
Historical scans restore their Cloudflare R2 URLs directly into `localImagePath` and `additionalImagePaths` when the physical photo is absent locally. `LocalImageLoader` evaluates HTTP boundaries implicitly, treating remote R2 URLs exactly like local `URL.documentsDirectory` paths — routing async cache fetches transparently so the user downloads only what is on screen.

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
