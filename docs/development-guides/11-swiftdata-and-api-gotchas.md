# SwiftData & Edge API Gotchas

When building zero-OOM pipelines and heavily concurrent systems like Merian, minor API behaviors or framework bugs can manifest as catastrophic system errors. This document outlines critical edge cases involving SwiftData concurrency and Edge Function serialization so future development efforts can avoid repeating them.

---

## 1. SwiftData `@ModelActor` and `#Predicate` Deletion Sync Drops

When deleting records on a background executor (via an `@ModelActor` like `BackgroundDatabaseActor`), you must be extremely precise with how you request the `ModelContext` to purge the record. 

### ❌ The Anti-Pattern: `delete(model:where:)`
```swift
// DO NOT do this inside a background ModelActor
try modelContext.delete(model: OfflineQueuedScan.self, where: #Predicate { $0.id == scanId })
try modelContext.save()
```
While this is extremely efficient as it does not fault models into memory, **in iOS 17 SwiftData it is fundamentally bugged when executing on a background context**. 
- It accurately deletes the SQLite record on disk.
- However, it **does not** accurately formulate and emit the `NSManagedObjectContextObjectsDidChange` background sync notifications to the Main thread context.
- Consequently, any active `@Query` properties bound to the UI (e.g., in a `LibraryView`) will simply hold onto the memory cache and visually "strand" the deleted object in the UI, often leading to infinitely "stuck" loading spinners.

### ✅ The Recommended Pattern: Explicit Fetch-and-Delete
To ensure Main Actor arrays dynamically receive deletion notifications, the record must be instantiated into memory within the active background context prior to calling the atomic `delete` method.

```swift
var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
descriptor.fetchLimit = 1

if let scanToDelete = try modelContext.fetch(descriptor).first {
    modelContext.delete(scanToDelete)
}
try modelContext.save()
```
This strategy faults the swift macro correctly, binds the object identifiers to the active context cache, and when `save()` commits, the delta accurately diffs and synchronizes across all application contexts seamlessly—forcing the UI to refresh instantly.

---

## 2. API Contracts & Silent Optional Fallbacks

When modifying JSON DTO contracts between the client and Edge Functions, be acutely aware of how Swift's `JSONDecoder` evaluates structures comprised entirely of `Optional` properties.

If an API response payload is structurally nested (e.g., `{"success": true, "data": { "confidence_score": 0.9 }}`) but the client attempts to decode the inner payload schema at the root JSON level, the decoding process can fail **silently** without throwing `DecodingError.keyNotFound`.

### The Vulnerability
If the DTO `EdgeResponse` dictates that all of its properties are optional (e.g., `let confidence_score: Double?`, `let scientific_name: String?`), and the decoder parses the outer wrapper `{"success": true, "data": ...}` against `EdgeResponse`:
- It looks for `confidence_score` at the root. It's missing. Since it is optional, the decoder sets it to `nil`.
- It repeats this for all properties.
- **The Result**: Decoding inherently succeeds without throwing an error, but produces an empty, fully `nil` schema instance. 

This causes massive logic failures downstream (e.g., `confidenceScore` falling back to `0.0`, triggering default "Unknown Subject" states in the UI) while entirely obfuscating the root cause by bypassing error-handling catch blocks.

### ✅ The Recommended Pattern: Explicit Wrappers
If the Supabase edge function returns a `{"data": payload}` envelope, you must define and decode an exact 1:1 `EdgeResponseWrapper` struct that strictly requires the `data` key. 

```swift
// STRICT WRAPPER: Enforces key existence.
struct EdgeResponseWrapper: Codable {
    let data: EdgeResponse
}
// This will correctly throw `keyNotFound` if the server payload shape mutates.
let decoded = try JSONDecoder().decode(EdgeResponseWrapper.self, from: rawHttpData)
```

By ensuring that the structural envelope relies on non-optional keys (like `data`), we guarantee that API contract breaches throw loud, trackable `DecodingError` exceptions rather than silently corrupting parsing downstream.

---

## 3. `#Predicate` Cannot Reference Computed Properties

SwiftData's `#Predicate` macro compiles down to `NSPredicate` at the SQL layer. It can only reference stored properties that map 1:1 to database columns. Attempting to reference a computed property — even a simple one that derives from a stored field — crashes at runtime with:

```
Fatal error: keyPathToFlattenedExpression: …keyPath refers to a property
that is not supported by this predicate
```

### The Vulnerability
`OfflineQueuedScan` previously exposed a computed `var isDeleted: Bool { scanStateRaw == 5 }`. Using it in a `@Query` or `FetchDescriptor` predicate compiles fine but crashes at runtime.

### ✅ The Pattern: Store a Raw Int, Predicate on It

```swift
// Model
@Model class OfflineQueuedScan {
    var scanStateRaw: Int = ScanQueueState.pending.rawValue  // stored → safe for #Predicate

    var queueState: ScanQueueState {                         // computed → NOT safe for #Predicate
        get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
        set { scanStateRaw = newValue.rawValue }
    }
}

// Query — works
@Query(filter: #Predicate<OfflineQueuedScan> { $0.scanStateRaw < 5 }, ...)
private var queuedScans: [OfflineQueuedScan]

// FetchDescriptor — works
let failedRaw = ScanQueueState.failed.rawValue
let descriptor = FetchDescriptor<OfflineQueuedScan>(
    predicate: #Predicate { $0.scanStateRaw == failedRaw }
)
```

Always predicate on the raw stored `Int`, never on the typed computed wrapper. The enum is still safe to use everywhere else in business logic — just not inside `#Predicate`.

---

## 4. In-Memory Lock Sets Are Lost on Process Death

`OfflineQueueManager` originally tracked in-flight uploads via `var activeScanUploadIds: Set<String>`. While reliable within a single process, this set is destroyed on any app kill — including legitimate iOS background terminations. On the next launch, `syncPendingScans` would see scans still in `.uploading` state in SwiftData (because the state had not been updated yet), treat them as pending, and re-dispatch duplicate URLSession tasks.

### ✅ The Pattern: Persist State Before Dispatching

Transition scans to `.uploading` in SwiftData **before** calling `uploadTask.resume()`. If the process dies between the state write and the task dispatch, startup reconciliation detects the orphaned `.uploading` scans (no corresponding active URLSession task) and resets them to `.pending`. If the task was dispatched but the process died mid-upload, iOS's background URLSession re-attaches the task on relaunch — the `.uploading` state correctly prevents re-dispatch.

```swift
// Always persist state BEFORE crossing the URLSession boundary
await dbActor.markScansAsUploading(scanIds: filteredScans.map(\.id))

// Then dispatch
for item in uploadItems {
    let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
    uploadTask.resume()
}
```

The same principle applies to any durable operation that must survive a crash: write the intent before performing the action, not after.

---

## 5. Unguarded `BackgroundDatabaseActor` Writes Can Overwrite MainActor Tombstones

`OfflineQueueManager` (MainActor) and `BackgroundDatabaseActor` (`@ModelActor`, background executor) both write to the same SwiftData persistent store. Each holds its own independent `ModelContext`. When both save concurrently, the **last writer wins** at the SQLite layer — the persistent store coordinator merges changes based on commit order, not semantic intent.

### The Vulnerability

`softDeleteQueuedScan` tombstones a scan to `.failed` on the MainActor (e.g., when the user deletes a scan from the UI while inference is running). Concurrently, `runInferencePipeline`'s transient-error catch block calls:

```swift
// ❌ Unguarded: overwrites any state, including .failed
actor.transitionScan(id: scanId, to: .staged)
```

If the BackgroundDatabaseActor's save commits after the MainActor's tombstone, the scan transitions `.failed → .staged` and is immediately eligible for inference replay — the tombstone is silently lost.

### ✅ The Pattern: Source-State Guard on Every Write

Any write that advances or retreats through the state machine must guard the source state it expects:

```swift
// transitionScanToStaged (background actor)
guard scan.scanStateRaw == ScanQueueState.inferencing.rawValue else { return }
scan.scanStateRaw = ScanQueueState.staged.rawValue
try modelContext.save()
```

The guard is checked inside the actor's serial executor. If a concurrent MainActor tombstone wins the race and saves first, the background actor reads the updated state (`.failed`) on its next fetch and the guard rejects the transition, leaving the tombstone intact.

This principle mirrors the existing guards on `markScanAsStaged` (`.uploading`-only) and `markScansAsUploading` (`.pending`-only): every state transition function is responsible for asserting the valid source state, not the caller.

---

## 6. Stale Core Data Fault: Cross-Context Saves Are Not Immediately Visible in Memory

When a fresh `BackgroundDatabaseActor` saves changes to the persistent store, a **separate, long-lived** `BackgroundDatabaseActor` does not automatically see the updated values in its in-memory object cache. Core Data returns cached fault objects for identities it has already loaded — it does not re-query the persistent store unless the object is explicitly refreshed or the context processes a merge notification.

### The Vulnerability

`replayInferenceForUploadedScans` previously created a fresh actor to call `resetOrphanedInferencingScans`:

```swift
// ❌ Fresh actor resets .inferencing → .staged in the persistent store
let freshActor = BackgroundDatabaseActor(modelContainer: container)
await freshActor.resetOrphanedInferencingScans()

// But the shared actor's in-memory copy still shows .inferencing
// tryClaimForInference checks: scan.scanStateRaw == stagedRaw → FAILS every time
guard await sharedActor.tryClaimForInference(scanId: scanId) else { return }
```

The `tryClaimForInference` guard always returned `false` because the shared actor fetched its already-loaded in-memory fault object (which showed `.inferencing`) rather than re-querying the store.

### ✅ The Pattern: Run Reset and Claim on the Same Actor

State machine transitions that must see each other's effects must run on the **same actor instance**, so all reads and writes share the same in-memory object graph:

```swift
// ✅ Shared actor resets AND claims — both see the same in-memory state
let sharedActor = resolvedInferenceDbActor(container: container)
await sharedActor.resetOrphanedInferencingScans()  // .inferencing → .staged in shared context
// tryClaimForInference now sees .staged because it reads from the same context
guard await sharedActor.tryClaimForInference(scanId: scanId) else { return }
```

The shared inference actor (`_inferenceDbActor`) is specifically reserved for state-machine operations that must be serialized. One-shot actors (e.g., reconciliation at startup) are fine as long as they do not need to share in-memory state with the long-lived actor.

---

## 8. Offline Queue Durability: Enqueue at Submission, Not at Rescue

The previous architecture attempted to rescue in-flight live inference captures by calling `enqueueCapture()` from background-phase or sheet-dismiss handlers. This pattern is structurally broken for three compounding reasons:

1. **`Task(priority: .background)` starvation** — rescue tasks created after the app enters the background are queued at the lowest cooperative priority. iOS may suspend the process before the task scheduler gives them CPU time.
2. **`isSyncing` guard deadlock** — `syncPendingScans()` guards with `guard !isSyncing`. If a prior sync cycle is still in-flight (pending network response), the rescue's sync call is silently dropped. The scan enters SwiftData as `.pending` and stalls indefinitely until the next foreground.
3. **In-memory timing window** — `prepareForNewScan()` clears `activeLiveCaptureDatas` synchronously. `analyze()` repopulates it, but only after `capturedPreFetchTask?.value` resolves (GPS/weather fetch, 1–3 s). If rescue fires during this window, the image data is gone.

### ✅ The Pattern: Enqueue Immediately at Submission

Call `enqueueCapture()` synchronously **before any async work begins** in `submitActiveScan`. Use the already-cached GPS (`EnvironmentContextManager.cachedLocation` — live location tracking runs while the camera is active). Pass a caller-generated `scanId` to tie the queued record to the concurrent live inference.

```swift
// In submitActiveScan — BEFORE the Task {} block:
let scanId = UUID().uuidString.lowercased()
diContainer.offlineQueueManager.enqueueCapture(
    imageDatas: datasToAnalyze,
    telemetry: immediateTelemetry,   // GPS from cachedLocation, weather nil (backfilled by runInferencePipeline)
    blurScore: nil,
    scanId: scanId
)

// In the Task — fire live inference concurrently:
await MainActor.run {
    guard self.diContainer.inferenceEngine.isProcessing else { return }
    self.diContainer.inferenceEngine.analyze(scanId: scanId, ...)
}
```

**On live inference success**: `analyze()` calls `OfflineQueueManager.shared.deleteQueuedScan(scanId:)`, which cancels any in-flight URLSession tasks and removes the SwiftData record. If the upload already completed and `processUploadCompletion` claimed the scan first, `deleteQueuedScan` is a no-op (record not found). The idempotency guard in `processAndCleanupOfflineScan` prevents a duplicate `LocalScanRecord`.

**On live inference cancellation or network failure**: the background upload path continues uninterrupted and delivers the result via push notification.

All rescue handlers (`dismissAnalysisToBackground`, `handleBackgroundPhase` inference block, `InsightSheetView.onDisappear` rescue) are deleted. `activeLiveCaptureDatas` and `isBackgroundRescued` are removed from `InferenceEngine` entirely — they had no purpose outside the now-deleted rescue pattern.

---

## 7. Failed `modelContext.save()` Does NOT Roll Back Pending Changes

In SwiftData (built on Core Data), a failed `save()` call leaves all pending changes — inserts, deletes, property mutations — **in the context's pending state**. They are not automatically rolled back. Subsequent operations on the same context accumulate on top of the corrupted pending state.

### The Vulnerability

`processAndCleanupOfflineScan` inserts a `LocalScanRecord` into the background context and calls `save()`. If the save fails (e.g., unique-constraint violation on `LocalScanRecord.id`), the pending INSERT remains on the context. On the next retry a second `processAndCleanupOfflineScan` call stacks a second pending INSERT with the same `id` on top of the first → guaranteed unique-constraint failure on every subsequent attempt.

```swift
// ❌ Reusing the shared actor for cleanup: a failed save corrupts the shared context
let sharedActor = resolvedInferenceDbActor(container: container)
await sharedActor.processAndCleanupOfflineScan(...)  // save() fails
// Now sharedActor.modelContext has a stale pending INSERT stuck in it
await sharedActor.tryClaimForInference(...)           // next attempt stacks a second INSERT →
                                                      // unique-constraint failure forever
```

### ✅ The Pattern: Fresh Actor for Each Cleanup Attempt

Use a **fresh** `BackgroundDatabaseActor` for each `processAndCleanupOfflineScan` call. A failed save is contained to that fresh actor — it is simply discarded. The shared actor's context remains uncorrupted and can continue to serve state-machine transitions correctly:

```swift
// ✅ Fresh actor per cleanup attempt: failure is contained and discarded
let cleanupActor = BackgroundDatabaseActor(modelContainer: container)
await cleanupActor.processAndCleanupOfflineScan(...)  // save() fails → cleanupActor discarded
// sharedActor.modelContext is unaffected; reconcileOrphanedInferencingScans works normally
```

Additionally, `processAndCleanupOfflineScan` itself should be **idempotent**: check whether a `LocalScanRecord` with the target `id` already exists before inserting, to prevent unique-constraint failures when a previous attempt partially committed:

```swift
var existingIdDescriptor = FetchDescriptor<LocalScanRecord>(
    predicate: #Predicate<LocalScanRecord> { $0.id == recordId }
)
existingIdDescriptor.fetchLimit = 1
let alreadyExists = (try? modelContext.fetch(existingIdDescriptor))?.isEmpty == false
if !alreadyExists {
    modelContext.insert(record)
}
```

---

## 9. Orphaned `.uploading` Scans When `generateUploadURLs` Fails Mid-Session

`syncPendingScans` calls `markScansAsUploading` to transition selected scans from `.pending` to `.uploading` **before** dispatching the URLSession upload tasks (see §4 — state must be persisted before the task dispatch boundary). This is intentional and correct for the crash-recovery case. However it introduces a trap when the next step fails:

If `generateUploadURLs` throws — e.g. because `syncTask` was cancelled when `NWPathMonitor` fires offline as the user backgrounds — the catch block schedules a retry via `syncPendingScans()`. But `syncPendingScans` only fetches `scanStateRaw == 0` (`.pending`) records. The scans are now in `.uploading` and are **permanently invisible to the retry** within that process session.

`reconcileOrphanedUploadingScans` cannot help here: it is gated to run once at cold-start (before any upload tasks are dispatched), after which `hasReconciledStartupState = true` permanently. The scans stay stuck in `.uploading` and show an infinite spinner in the scans library until the app is killed and relaunched.

### ✅ Fix: Reset Orphans Before Scheduling the Retry

In the `generateUploadURLs` catch block, cross-reference live URLSession tasks and call `reconcileOrphanedUploadingScans` before the retry is scheduled. Scans with a live upload task in-flight are left in `.uploading`; only true orphans (no task, `generateUploadURLs` never reached `uploadTask.resume()`) are reset to `.pending`.

```swift
} catch {
    // Reset scans we marked .uploading back to .pending.
    // generateUploadURLs failed before any URLSession tasks were dispatched, so every
    // .uploading scan without a live task is an orphan. Without this reset,
    // syncPendingScans only fetches .pending and the scan is never retried.
    let liveTasks = await session.allTasks
    let activeUploadIds = Set(liveTasks.compactMap { task -> String? in
        guard let desc = task.taskDescription, !desc.hasPrefix("inference_") else { return nil }
        return desc.components(separatedBy: "_").first
    })
    await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeUploadIds)
    // ... schedule backoff retry
}
```

**Safety-net layer**: `replayInferenceForUploadedScans` also calls `reconcileOrphanedUploadingScans` on every invocation (foreground return + connectivity restore) using the same live-task cross-reference. This catches the case where the `syncPendingScans` Swift Task is killed before its catch block runs — a scenario the primary fix cannot handle.

---

## 10. Cold-Start Timing Gap: Reconcile Completes After `syncPendingScans` Already Ran

**Scenario**: The app is killed while a scan is in `.uploading` state — e.g. the user launches a scan and exits the app within ~1 second before `generateUploadURLs` returns and URLSession upload tasks are dispatched. On cold-start, the scan is `.uploading` with no active URLSession task.

**The gap**: `handleActivePhase` calls `syncPendingScans()` and `replayInferenceForUploadedScans()` in separate async Tasks. `syncPendingScans` internally calls `replayInferenceForUploadedScans()` first (line 131). On cold-start, `replayInferenceForUploadedScans` sets `hasReconciledStartupState = true`, fires an async Task (the cold-start reconcile), and **returns immediately**. `syncPendingScans` then fetches `.pending` scans — finds **none** (the scan is `.uploading`) — and returns early with `isSyncing = false`. The cold-start reconcile Task eventually completes, resets `.uploading` → `.pending`, and calls `replayInferenceForUploadedScans()` again. But the second `replayInferenceForUploadedScans()` only handles `.staged` scans — it does not call `syncPendingScans()`. The `.pending` scan sits permanently until the next connectivity change or foreground event.

```
handleActivePhase fires:
  syncPendingScans()
    → replayInferenceForUploadedScans()     // cold-start: fires Task A, returns immediately
    → fetchPendingScans()                   // finds nothing (.uploading excluded)
    → isSyncing = false, returns
  replayInferenceForUploadedScans()         // hasReconciledStartupState=true now → fires Task B

Task A (cold-start):
  reconcileOrphanedUploadingScans → .uploading → .pending  ✓
  callback: replayInferenceForUploadedScans() → replayInferenceStagedScans()
  // ← .pending scan NEVER picked up, no syncPendingScans called  ✗
```

### ✅ Fix: Call `syncPendingScans()` Conditionally in the Cold-Start Callback

`reconcileOrphanedUploadingScans` now returns `Bool` (`true` if any scans were reset). The cold-start callback calls `syncPendingScans()` only when `hadOrphans == true`:

```swift
let hadOrphans = await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeIds)
await MainActor.run {
    if hadOrphans { self.syncPendingScans() }  // pick up newly-reset .pending scans immediately
    self.replayInferenceForUploadedScans()
}
```

Guarding on `hadOrphans` is essential. An unconditional `syncPendingScans()` call fires even when the reconcile found nothing — in the common case (no orphaned uploads) this triggers a spurious second sync on every cold-start, interfering with the backoff timer and causing test instability via the `isSyncing` latch.

**Note**: Do NOT add `syncPendingScans()` to the normal-path callback in `replayInferenceForUploadedScans`. The normal path is called from within `syncPendingScans` itself (line 131). Adding `syncPendingScans()` there creates a recursive chain: `syncPendingScans` → `replayInferenceForUploadedScans` → normal Task → `syncPendingScans` → `replayInferenceForUploadedScans` → another Task → `reconcileOrphanedInferencingScans` → resets legitimately-claimed `.inferencing` scans → `replayInferenceStagedScans` → claims them again → infinite oscillation.

---

## 16. `activeScanId` Stale Hydration Window

`InferenceEngine.activeScanId` is set at the start of `analyze()` to the caller's scan ID. The background offline path (`OfflineQueueManager+URLSession`) uses this to detect when a background inference result for the same scan should hydrate the live engine instead of discarding:

```swift
if engine.activeScanId == scanId,
   engine.isProcessing || engine.speciesData?.scanId == nil {
    engine.isProcessing = false
    engine.speciesData = speciesData
}
```

**The bug (fixed)**: `activeScanId` was never cleared when the pipeline exited. If live inference failed (producing an error `SpeciesData` with `scanId: nil`), the engine remained with `activeScanId != nil` and `isProcessing = false`. A background inference arriving minutes later would see `engine.speciesData?.scanId == nil` (true for error placeholders) and overwrite the stale error state — even though the user had long since dismissed the insight sheet.

**The fix**: `activeScanId` is cleared in the inference task's `defer` block alongside `isProcessing`:

```swift
defer {
    self.isProcessing = false
    self.activeScanId = nil  // bounds hydration window to isProcessing == true
    self.phaseRotationTask?.cancel()
}
```

For the success path this is a no-op: background correctly skips because `speciesData.scanId != nil`. For the failure path it ensures the background path only hydrates the engine while the live pipeline is actually running.

---

## 17. `@Observable` Struct Properties: Optional-Chain Mutations Do Not Reliably Fire Notifications

`InferenceEngine` holds `var speciesData: SpeciesData?` where `SpeciesData` is a **struct** on an `@Observable` class. SwiftUI's `@Observable` macro synthesizes `get`/`set` accessors (not `_modify`) for stored properties. Because a `_modify` accessor is absent, optional-chain mutations like `self.speciesData?.field = x` go through a copy-on-write cycle at the compiler level rather than through `withMutation(keyPath:)` — and empirically do **not** reliably fire observation notifications to subscribed views.

### ❌ The Anti-Pattern

```swift
// Any or all of these may silently fail to notify @Observable observers:
self.speciesData?.habitatDescription = "..."
self.speciesData?.referenceImageUrl = imgUrl
self.speciesData?.taxonomy = taxonomy
```

Views that track `inferenceEngine.speciesData` via `@Observable` (e.g. `HabitatAndDistributionCard`) will not re-render when mutations are applied this way, even though the data is correctly written in memory. The card appears stuck or empty until something else forces a re-render (e.g. the user dismisses and reopens the sheet). `ImagesCarousel` is no longer in this category — it receives all data as injected parameters from `InsightSheetViewModel`, which in turn reads from the engine. The re-render chain still applies transitively through the viewModel's computed properties (`refUrls`, `validHistoricImagePaths`, `liveImageData`).

### ✅ The Required Pattern: Single Full-Value Replacement

Collect **all** mutations into a local copy, then assign back in a single write. The single setter call goes through `withMutation(keyPath: \.speciesData)` and guarantees exactly one observation notification for the entire batch:

```swift
if var updated = self.speciesData {
    updated.habitatDescription = "..."
    updated.referenceImageUrl = imgUrl
    updated.taxonomy = taxonomy
    // ... all mutations on `updated` ...
    self.speciesData = updated  // single @Observable-triggering assignment
}
```

### Affected Sites in `InferenceEngine.swift`

All write paths in `InferenceEngine` that modify `speciesData` follow this pattern:

| Function | Fields written |
|---|---|
| `fetchAndApplyEnrichment` | `habitatDescription`, `gbifTaxonKey`, `taxonomy`, `similarSpecies` |
| `fetchWikipediaAndHydrate` | `wikipediaOverview`, `wikipediaUrl`, `referenceImageUrl` |
| `fetchAndPatchOverrideData` (cache hit) | `commonName`, `insightData`, `taxonomy`, `iucnRedListStatus`, `habitatDescription`, `gbifTaxonKey`, `referenceImageUrl`, `wikipediaOverview`, `wikipediaUrl` |
| `applyIdentificationOverride` (wipe) | All contextual fields reset to nil + override identity fields |
| `dropInvalidCarouselImage` | `referenceImageUrl` (URL removed from comma-separated list) |
| Historical load path | `similarSpecies`, `candidates` |

### Why This Matters for Live UI

The insight sheet is open while background hydration tasks (`fetchWikipediaAndHydrate`, `fetchAndApplyEnrichment`, `fetchAndPatchOverrideData`) complete asynchronously. If these tasks use optional-chain mutations, the cards (`HabitatAndDistributionCard`, `TaxonomyCard`, `SimilarSpeciesGallery`) will not update live — the user sees empty or skeleton states until the sheet is dismissed and reopened. Full-value replacement ensures cards populate in real time without any user interaction. `ImagesCarousel` receives its data through `InsightSheetViewModel` computed properties, so the same full-value-replacement rule applies at the engine level — the viewModel's observation chain propagates changes correctly only when `speciesData` itself is replaced, not field-mutated.

---

## 18. `@Model` Zombie Crash in `LazyVGrid` via Deferred Attribute Fault

**Symptom**: Fatal error `"This backing data was detached from a context without resolving attribute faults"` on a property like `OfflineQueuedScan.localImagePaths`, originating inside a `LazyVGrid` `ForEach` body — **after** the object has been deleted from the context.

**Why it happens**: SwiftUI's `LazyVGrid` evaluates view closures lazily — tile bodies are computed only when the row scrolls into the viewport. If a `@Model` attribute (e.g., `localImagePaths: [String]`) was never accessed before deletion, it is still in a faulted state (unfulfilled). SwiftUI's `@Observable` machinery also registers observation dependencies on the `@Model` object when the grid first reads it. After `context.delete(scan)` fires, SwiftUI re-evaluates the view (responding to the deletion notification), triggering a fault on the already-deleted object — which crashes immediately.

The same crash path applies anywhere a deleted `@Model` reference can be re-evaluated: inside `InsightSheetViewModel` computed properties (`validHistoricImagePaths`, `analyzingPhrase`), or inside `AnalyzingContentView` views that read the queued scan's telemetry fields.

### ❌ The Anti-Pattern

```swift
// Holding a live @Model reference across a deletion boundary
@State private var queuedScan: OfflineQueuedScan?

// LazyVGrid tile
ScanThumbnail(imagePath: queued.localImagePaths.first) // CRASH after context.delete(queued)

// InsightSheetViewModel
var validHistoricImagePaths: [String] {
    if let scan = queuedScan { return scan.localImagePaths } // CRASH
    ...
}
```

### ✅ The Pattern: Value-Type Snapshot at Fetch Time

Copy all needed data out of the `@Model` object into a plain value-type struct **while the object is live** — before any `context.delete()` can fire. The grid and the insight sheet chain then hold only the value type; no `@Model` reference survives the boundary.

```swift
// QueuedScanSnapshot — for grid tiles
struct QueuedScanSnapshot: Identifiable, Equatable {
    let id: String
    let imagePath: String?    // localImagePaths.first, resolved at fetch time
    let timestamp: Date
    var gridId: String { "q_\(id)" }  // namespace against LocalScanRecord IDs
}

// QueuedScanContext — for the full insight sheet chain
struct QueuedScanContext: Identifiable {
    let id: String
    let localImagePaths: [String]
    let timestamp: Date
    let locationName: String?
    let weatherTemperatureF: Double?
    let weatherCondition: String?
    let gpsElevation: Double?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    init(from scan: OfflineQueuedScan) { /* copy while live */ }
}

// In ScansSheetView.refreshQueuedScans() — map at fetch time, before any deletion can fire
queuedScans = fetched.map {
    QueuedScanSnapshot(id: $0.id, imagePath: $0.localImagePaths.first, timestamp: $0.timestamp)
}

// In LibraryView — snapshot before presenting the insight sheet
if let scan = (try? modelContext.fetch(descriptor))?.first {
    scanToManage = QueuedScanContext(from: scan)  // all fields resolved NOW
    isQueuedSheetPresented = true
}
```

**`gridId` namespacing**: `LocalScanRecord.id` and `QueuedScanSnapshot.id` share the same UUID (both use `client_scan_id`). Without namespacing, `LazyVGrid`'s `ForEach` produces duplicate `AnyHashable` keys, causing SwiftUI to skip one tile entirely. `gridId = "q_\(id)"` guarantees a distinct key for every queued-scan tile.

**`InsightSheetViewModel.queuedContext: QueuedScanContext?`**: All computed properties that previously switched on a live `OfflineQueuedScan?` now switch on `queuedContext == nil`. `AnalyzingContentView` receives `queuedContext: QueuedScanContext?` rather than a `@Model` reference — it reads `queuedContext?.locationName`, etc. — so no attribute is ever accessed post-deletion.
