# The Offline Synchronization Pipeline

Merian's core differentiator is treating off-grid nature encounters as a first-class citizen using native Apple offline architecture.

## How the Queue Works

### 1. Realtime Inference Mapper (`saveLiveScanRecord`)
When a user scans a subject with an active network connection, the Gemini response cascades back from the Edge node. To persist this inference against iOS RAM loss, `BackgroundDatabaseActor.saveLiveScanRecord(mappedData:localImagePaths:)` is invoked on its isolated `@ModelActor` thread. It accepts an array of local image filenames (relative paths in `URL.documentsDirectory`), inserts a `LocalScanRecord`, and calls `modelContext.save()`.

### 2. Inference Failure & Queueing (`enqueueCapture`)
When a hiker captures a photo off-grid, the telemetry (GPS, weather, elevation, subject distance, location name) is wrapped in a `CaptureTelemetry` struct and passed to `OfflineQueueManager.shared.enqueueCapture(imageDatas:telemetry:)`.

The queue engine spawns a `BackgroundTaskWrapper.execute` window so iOS grants extended time even when the app is backgrounded. All disk I/O runs off the main thread via `FileIOActor`. Once image bytes land in `URL.documentsDirectory`, a new `OfflineQueuedScan` SwiftData record is inserted with the full telemetry payload attached. On a successful `context.save()`, `AppTelemetry.trackOfflineQueued()` fires a `OfflineQueuedScan` TelemetryDeck signal to measure offline usage rate.

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

Active upload tasks are deduplicated against `backgroundSession.allTasks` before dispatching, preventing double-uploads on relaunch. Each image is first copied to a temp file in `URL.cachesDirectory` (`<scanId>_<index>_temp_upload.webp`) before being handed to `URLSession.uploadTask(with:fromFile:)`. The `URLRequest` carries a `Content-Type: image/webp` header, which must match the `image/webp` Content-Type baked into the Cloudflare R2 pre-signed URL by the `generate-upload-urls` Edge function. The client generates deterministic filenames using the local `scanId` and file path; these predictably formatted names combined with the **lowercased UUID** of the authenticated user construct the exact sequence required for the `analyzeSubject` inference step later. The OS background session owns byte transmission from here, handling interruption and resume transparently.

**Concurrent staging (`withTaskGroup`)**: Pre-flight guards — URL validation, file existence checks, and tombstoning — remain serial. Once all guards clear, the `FileManager.copyItem` and `uploadTask` creation for each image are fanned out concurrently via `withTaskGroup`. For a 3-image scan this eliminates 500 ms–2 s of head-of-line blocking before the background session takes ownership.

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
- **Step D**: `SyncStateManager.shared.beginInferencing()` transitions the state machine to `.inferencing`. The inference Edge function (`analyzeSubject`) is called with the R2 object keys. Inference is suppressed until the **last** image file for the scan has landed (guarded by `indexPart == localImagePaths.count - 1`), preventing partial-payload submissions. To pass the server's case-sensitive IDOR block, the authenticated user's UUID embedded within these keys is strictly lowercased.
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
3. `FileIOActor.shared.deleteImages(at:)` — purge local `.webp` files asynchronously, skipping remote R2 URLs (those are cloud-owned). Runs only after the DB commit succeeds.
4. `offlineQueue.syncPendingDeletions()` async — attempt the cloud deletion immediately; retry on next connectivity cycle.

### 2. Cloud Deletion Tasking (`PendingCloudDeletionTask`)
A `PendingCloudDeletionTask` SwiftData record is inserted at deletion time, queuing the `scanId` for cloud erasure. The UI executes an optimistic delete immediately.

### 3. Upload Interception (`softDeleteQueuedScan`)
If the scan being destroyed is actively queued for upload, `softDeleteQueuedScan` tombstones the `OfflineQueuedScan` record (`isDeleted = true`), excluding it from future sync attempts. Records are hard-purged later via `purgeSoftDeletedRecords()`.

### 4. Network Polling Sync (`syncPendingDeletions`)
On `NWPathMonitor` reconnect, `syncPendingDeletions()` drains the `PendingCloudDeletionTask` queue. Deletion requests are fanned out **concurrently in batches of 10** via `withTaskGroup`. Each batch fans out all its child tasks simultaneously, collecting results before the next batch begins. A single `modelContext.save()` runs once after all batches complete, removing all successfully confirmed tasks in one write. Capping at 10 concurrent Edge calls prevents connection-pool exhaustion; for a user with 10 offline deletions the wall time still drops from ~4 s (serial) to ~600 ms (concurrent).

`NetworkError.invalidResponse` (resource already gone) is treated as terminal and the task is removed. All other errors retain the task for the next cycle.

## The Collections Pipeline

Merian supports creating custom `ScanCollection` buckets while fully disconnected.

1. **Entity Instantiation**: A user taps "New Collection" — a `ScanCollection` is inserted into SwiftData and `modelContext.save()` is called immediately. The collection is durable locally from this point.
2. **Background Upload**: `OfflineQueueManager.shared.syncCollections()` is triggered, pushing `SyncCollectionPayload` arrays to the `sync-collections` Edge function. The upload is wrapped in `BackgroundTaskWrapper.execute(name: "CollectionSync")` so iOS grants additional background time if the user closes the app immediately after creating a collection.

   **Diff-based Edge sync**: The `sync-collections` Deno function handles explicitly passed soft-deletions (`is_deleted: true` or `isDeleted: true`) securely before performing a set-based delta sync for `collection_scans` membership. It computes the desired membership from the client payload and diffs it against the current Supabase state. Only the delta (rows to add and rows to remove) is written. We intentionally do not use implicit destructive diffs for whole collections to prevent devices with missing histories from obliterating remote databases. The Edge function actively pre-filters any mappings for scans that haven't synced to the cloud yet, preventing Postgres FK constraint violations from aborting the overarching database chunk. Removals are grouped by `collection_id`. A `MAX_COLLECTIONS = 200` cap is enforced server-side.
   
   **Strict Local Tombstone Destruction**: Once the Edge sync returns HTTP 200 indicating successful cloud deletion for any `isDeleted == true` payload, the `BackgroundDatabaseActor` permanently deletes the ghost `ScanCollection` record from SwiftData to ensure it cannot resurrect or linger in UI state.
   
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
2. **`updateExistingScans`**: Receives only the local record sets securely matched from the previous bounding fetch. Updates: `localImagePath`, `additionalImagePaths`, `referenceImageUrl`, GPS fields, `locationName`, taxonomic ranks (`taxonomyKingdom` through `taxonomyGenus`), and `customTags`. Saves only if any field actually changed. Note: Overwriting `customTags` defaults to cloud-wins reconciliation, erasing offline-only tag additions if they failed to push before the downward sync.
3. **`ingestScans`**: Inserts new `LocalScanRecord` rows for cloud records absent locally entirely. Checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (50) records to limit data loss if a background task is killed mid-ingest.
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
