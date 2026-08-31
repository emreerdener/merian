# SwiftData & Edge API Gotchas

When building zero-OOM pipelines and heavily concurrent systems like Merian,
minor API behaviors or framework bugs can manifest as catastrophic system
errors. This document outlines critical edge cases involving SwiftData
concurrency and Edge Function serialization so future development efforts can
avoid repeating them.

---

## 0. Duplicate Schema Checksums Need Store-Aware Representatives

SwiftData staged migration plans cannot contain two schema versions with the
same model checksum. Merian shipped V46 as a no-op after V45, so the primary
`MerianMigrationPlan` keeps the duplicate-prone V44/V45/V46 recent cluster out
of `schemas` and jumps older unknown stores from V43→V49. Source-isolated recent
plans still handle V44, V45, and V46 stores directly; V44, V45, and V46 stores
jump through separate direct V44→V49, V45→V49, and V46→V49 plans. Those repairs
are intermediate targets: every selected plan then applies the lightweight
V49→V50 stage, while a current V50 store opens without a plan.

One extra wrinkle: a user may already have a local store stamped as V46.
SwiftData can validate that on-disk source model alongside the primary plan's
V47 representative, which reintroduces duplicate-checksum or stale-model startup
failures even though V46 is not listed in the primary plan. V47 therefore keeps
local-scan, captured-media, and collection entities frozen inside V47, and keeps
its queued scan model scalar-only. V44, V45, and V46 recovery plans skip V47 and
use the actual source stamp as the only recent representative in the plan, then
jump directly to V49. Startup reads the store metadata before creating
`ModelContainer`. Fresh stores and stores already stamped at the current schema
open without a migration plan; known recent sources open with the matching
source-isolated plan (V49 through V42); only unknown or older existing stores
use the linear full historical plan. V49 has a one-stage lightweight V49→V50
plan; V50 is current and has no source-only rename stage. If SwiftData still
throws `Duplicate version checksums across stages detected`, startup falls back
through the same source-isolated plans before legacy rescue or safe mode. These
plans avoid forcing SwiftData to validate unrelated older retired schemas or
adjacent checksum-equivalent representatives while a recent store only needs to
advance to the current version.

Do not encode recent sources as an integer range followed by a generic app
fallback. Keep a finite recent-source enum, convert actual store metadata into
that enum, and dispatch it exhaustively to dedicated plans. The supported cases
must be consecutive and end at `CurrentSchema - 1`; checksum fallback must try
current store first and then supported sources newest to oldest. A disk fixture
must call this production metadata decision before opening with a plan.
Otherwise a future schema bump can appear covered while silently sending the
newly released predecessor through full historical validation.

When another no-op schema is ever shipped, keep only one representative in a
single plan and make any targeted alternate plan route through that checksum
representative instead of reintroducing the no-op schema classes.

## 1. SwiftData `@ModelActor` and `#Predicate` Deletion Sync Drops

When deleting records on a background executor (via an `@ModelActor` like
`BackgroundDatabaseActor`), you must be extremely precise with how you request
the `ModelContext` to purge the record.

### ❌ The Anti-Pattern: `delete(model:where:)`

```swift
// DO NOT do this inside a background ModelActor
try modelContext.delete(model: OfflineQueuedScan.self, where: #Predicate { $0.id == scanId })
try modelContext.save()
```

While this is extremely efficient as it does not fault models into memory, **in
iOS 17 SwiftData it is fundamentally bugged when executing on a background
context**.

- It accurately deletes the SQLite record on disk.
- However, it **does not** accurately formulate and emit the
  `NSManagedObjectContextObjectsDidChange` background sync notifications to the
  Main thread context.
- Consequently, any active `@Query` properties bound to the UI (e.g., in a
  `LibraryView`) will simply hold onto the memory cache and visually "strand"
  the deleted object in the UI, often leading to infinitely "stuck" loading
  spinners.

### ✅ The Recommended Pattern: Explicit Fetch-and-Delete

To ensure Main Actor arrays dynamically receive deletion notifications, the
record must be instantiated into memory within the active background context
prior to calling the atomic `delete` method.

```swift
var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
descriptor.fetchLimit = 1

if let scanToDelete = try modelContext.fetch(descriptor).first {
    modelContext.delete(scanToDelete)
}
try modelContext.save()
```

This strategy faults the swift macro correctly, binds the object identifiers to
the active context cache, and when `save()` commits, the delta accurately diffs
and synchronizes across all application contexts seamlessly—forcing the UI to
refresh instantly.

---

## 2. Snapshot `@Model` Values Before Async Boundaries

SwiftData `@Model` objects are not durable value objects. A view dismissal,
delete action, background save, or context reset can detach the backing data
while an async task that captured the model is still alive. Reading any
unfaulted attribute after that point can crash in
`SwiftData._KKMDBackingData.getValue`.

The safe pattern is to copy every scalar needed by the task while still on the
owning actor, then pass only those value types across the suspension point:

```swift
let recordId = record.id
let referenceImageUrl = record.referenceImageUrl
let candidatesData = record.candidatesData

hydrationTask = Task { [weak self] in
    guard let self else { return }
    let refUrls = Self.normalizedReferenceURLs(from: referenceImageUrl)
    // Never touch `record` here.
}
```

`InferenceEngine.load(from:)` follows this rule for historical reference images.
The same rule applies to sheet routes, share/export flows, delete confirmations,
refinement setup, and any `Task.detached` or `Task {}` that can outlive the
source SwiftUI view.

---

## 3. API Contracts & Silent Optional Fallbacks

When modifying JSON DTO contracts between the client and Edge Functions, be
acutely aware of how Swift's `JSONDecoder` evaluates structures comprised
entirely of `Optional` properties.

If an API response payload is structurally nested (e.g.,
`{"success": true, "data": { "confidence_score": 0.9 }}`) but the client
attempts to decode the inner payload schema at the root JSON level, the decoding
process can fail **silently** without throwing `DecodingError.keyNotFound`.

### The Vulnerability

If the DTO `EdgeResponse` dictates that all of its properties are optional
(e.g., `let confidence_score: Double?`, `let scientific_name: String?`), and the
decoder parses the outer wrapper `{"success": true, "data": ...}` against
`EdgeResponse`:

- It looks for `confidence_score` at the root. It's missing. Since it is
  optional, the decoder sets it to `nil`.
- It repeats this for all properties.
- **The Result**: Decoding inherently succeeds without throwing an error, but
  produces an empty, fully `nil` schema instance.

This causes massive logic failures downstream (e.g., `confidenceScore` falling
back to `0.0`, triggering default "Unknown Subject" states in the UI) while
entirely obfuscating the root cause by bypassing error-handling catch blocks.

### ✅ The Recommended Pattern: Explicit Wrappers

If the Supabase edge function returns a `{"data": payload}` envelope, you must
define and decode an exact 1:1 `EdgeResponseWrapper` struct that strictly
requires the `data` key.

```swift
// STRICT WRAPPER: Enforces key existence.
struct EdgeResponseWrapper: Codable {
    let data: EdgeResponse
}
// This will correctly throw `keyNotFound` if the server payload shape mutates.
let decoded = try JSONDecoder().decode(EdgeResponseWrapper.self, from: rawHttpData)
```

By ensuring that the structural envelope relies on non-optional keys (like
`data`), we guarantee that API contract breaches throw loud, trackable
`DecodingError` exceptions rather than silently corrupting parsing downstream.

---

## 4. `#Predicate` Cannot Reference Computed Properties

SwiftData's `#Predicate` macro compiles down to `NSPredicate` at the SQL layer.
It can only reference stored properties that map 1:1 to database columns.
Attempting to reference a computed property — even a simple one that derives
from a stored field — crashes at runtime with:

```
Fatal error: keyPathToFlattenedExpression: …keyPath refers to a property
that is not supported by this predicate
```

### The Vulnerability

`OfflineQueuedScan` previously exposed a computed
`var isDeleted: Bool { scanStateRaw == 5 }`. Using it in a `@Query` or
`FetchDescriptor` predicate compiles fine but crashes at runtime.

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

Always predicate on the raw stored `Int`, never on the typed computed wrapper.
The enum is still safe to use everywhere else in business logic — just not
inside `#Predicate`.

---

## 5. Keep Queue Job Predicates Simple

SwiftData's `#Predicate` macro can also struggle with large boolean expressions
over string-backed enum fields. For queue control-plane rows, fetch by the
stable job id first, then check `statusRaw` in normal Swift:

```swift
var descriptor = FetchDescriptor<OfflineJobRecord>(
    predicate: #Predicate { $0.id == OfflineQueueManager.collectionSyncJobId }
)
descriptor.fetchLimit = 1
let job = try context.fetch(descriptor).first
let isActive = job.map {
    $0.statusRaw == OfflineJobStatus.pending.rawValue ||
    $0.statusRaw == OfflineJobStatus.waiting.rawValue ||
    $0.statusRaw == OfflineJobStatus.running.rawValue
} ?? false
```

This avoids slow type-checking and keeps the SQL predicate on a single indexed
column. Apply the same pattern when adding future `OfflineJobRecord` schedulers.

---

## 6. In-Memory Lock Sets Are Lost on Process Death

`OfflineQueueManager` originally tracked in-flight uploads via
`var activeScanUploadIds: Set<String>`. While reliable within a single process,
this set is destroyed on any app kill — including legitimate iOS background
terminations. On the next launch, `syncPendingScans` would see scans still in
`.uploading` state in SwiftData (because the state had not been updated yet),
treat them as pending, and re-dispatch duplicate URLSession tasks.

### ✅ The Pattern: Persist State Before Dispatching

Validate the media staging manifest first, then transition scans to `.uploading`
in SwiftData **before** calling `uploadTask.resume()`. `MediaStagingContract`
owns the preflight budget checks and deterministic upload task descriptions, so
oversized or malformed local media is tombstoned while the scan is still
`.pending`. If the process dies between the state write and the task dispatch,
startup reconciliation detects the orphaned `.uploading` scans (no corresponding
active URLSession task) and resets them to `.pending`. If the task was
dispatched but the process died mid-upload, iOS's background URLSession
re-attaches the task on relaunch — the `.uploading` state correctly prevents
re-dispatch.

```swift
// Validate local media budgets and object-key contract first.
let preparation = prepareUploadItems(from: filteredScans, userId: stagingUserId)

// Always persist state BEFORE crossing the URLSession boundary.
let claimedScanIds = await dbActor.markScansAsUploading(
    scanIds: Array(Set(preparation.uploadItems.map(\.scanId)))
)
let claimedUploadItems = preparation.uploadItems.filter { claimedScanIds.contains($0.scanId) }
guard !claimedUploadItems.isEmpty else { return }

// Then dispatch the validated, position-aligned server manifest.
for (item, presignedURL) in zip(claimedUploadItems, presignedURLs) {
    let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
    uploadTask.taskDescription = MediaStagingContract.uploadTaskDescription(
        scanId: item.scanId,
        uploadIndex: item.uploadIndex,
        syncGeneration: generation,
        objectKey: presignedURL.objectKey
    )
    uploadTask.resume()
}
```

The same principle applies to any durable operation that must survive a crash:
write the intent before performing the action, not after. If the intent save
fails, rollback and do not dispatch the external action.

---

## 7. Unguarded `BackgroundDatabaseActor` Writes Can Overwrite MainActor Tombstones

`OfflineQueueManager` (MainActor) and `BackgroundDatabaseActor` (`@ModelActor`,
background executor) both write to the same SwiftData persistent store. Each
holds its own independent `ModelContext`. When both save concurrently, the
**last writer wins** at the SQLite layer — the persistent store coordinator
merges changes based on commit order, not semantic intent.

### The Vulnerability

`softDeleteQueuedScan` tombstones a scan to `.failed` on the MainActor (e.g.,
when the user deletes a scan from the UI while inference is running).
Concurrently, `runInferencePipeline`'s transient-error catch block calls:

```swift
// ❌ Unguarded: overwrites any state, including .failed
actor.transitionScan(id: scanId, to: .staged)
```

If the BackgroundDatabaseActor's save commits after the MainActor's tombstone,
the scan transitions `.failed → .staged` and is immediately eligible for
inference replay — the tombstone is silently lost.

### ✅ The Pattern: Source-State Guard on Every Write

Any write that advances or retreats through the state machine must guard the
source state it expects:

```swift
// transitionScanToStaged (background actor)
guard scan.scanStateRaw == ScanQueueState.inferencing.rawValue else { return }
scan.scanStateRaw = ScanQueueState.staged.rawValue
try modelContext.save()
```

The guard is checked inside the actor's serial executor. If a concurrent
MainActor tombstone wins the race and saves first, the background actor reads
the updated state (`.failed`) on its next fetch and the guard rejects the
transition, leaving the tombstone intact.

This principle mirrors the existing guards on `markScanAsStaged`
(`.uploading`-only) and `markScansAsUploading` (`.pending`-only): every state
transition function is responsible for asserting the valid source state, not the
caller.

---

## 8. Stale Core Data Fault: Cross-Context Saves Are Not Immediately Visible in Memory

When a fresh `BackgroundDatabaseActor` saves changes to the persistent store, a
**separate, long-lived** `BackgroundDatabaseActor` does not automatically see
the updated values in its in-memory object cache. Core Data returns cached fault
objects for identities it has already loaded — it does not re-query the
persistent store unless the object is explicitly refreshed or the context
processes a merge notification.

### The Vulnerability

`replayInferenceForUploadedScans` previously created a fresh actor to call
`resetOrphanedInferencingScans`:

```swift
// ❌ Fresh actor resets .inferencing → .staged in the persistent store
let freshActor = BackgroundDatabaseActor(modelContainer: container)
await freshActor.resetOrphanedInferencingScans()

// But the shared actor's in-memory copy still shows .inferencing
// tryClaimForInference checks: scan.scanStateRaw == stagedRaw → FAILS every time
guard await sharedActor.tryClaimForInference(scanId: scanId) else { return }
```

The `tryClaimForInference` guard always returned `false` because the shared
actor fetched its already-loaded in-memory fault object (which showed
`.inferencing`) rather than re-querying the store.

### ✅ The Pattern: Run Reset and Claim on the Same Actor

State machine transitions that must see each other's effects must run on the
**same actor instance**, so all reads and writes share the same in-memory object
graph:

```swift
// ✅ Shared actor reconciles AND claims — both see the same in-memory state
let sharedActor = resolvedQueueDbActor(container: container)
await sharedActor.reconcileOrphanedInferencingScans(
    activeInferenceScanIds: activeIds,
    observedThrough: taskSnapshotDate
)
// tryClaimForInference now sees .staged because it reads from the same context
guard await sharedActor.tryClaimForInference(scanId: scanId) else { return }
```

The shared queue actor (`_queueDbActor`) is reserved for upload/inference
state-machine operations that must be serialized. Upload claims, both orphan
reconcilers, staging, inference claims, and retry transitions all use this
instance. Every live-task reconciliation also captures an `observedThrough` date
before its first suspension and ignores rows with a newer `queueUpdatedAt`; a
queued stale reconcile therefore cannot overwrite a replacement claim. Final
`LocalScanRecord` persistence remains a fresh-actor operation so a failed save
cannot poison this long-lived context.

---

## 9. Relationship Mirrors Are Not Always Safe Hot Read Paths

SwiftData relationship arrays are faulting boundaries. Even when the
relationship is small, a SwiftUI body evaluation can trigger a child fault at a
fragile time. On May 12, 2026, TestFlight build 390 crashed in `BiologicalView`
while computing `LocalScanRecord.capturedMediaSnapshot`: `capturedMediaEntries`
was sorted, `CapturedMediaEntry.serializedItem` read `kindRaw`, and SwiftData
trapped in `_InvalidFutureBackingData.getValue`.

### The Vulnerability

The mixed-media model writes two equivalent representations:

```swift
record.capturedMediaJSON = MediaJSONParser.jsonString(from: items)
record.capturedMediaEntries = CapturedMediaEntry.makeEntries(from: items)
```

Treating the relationship as the preferred read source makes every
`capturedMediaSnapshot` access fault child rows during layout, export, toolbar,
or historical-load work. That turns an otherwise safe scalar read into a
SwiftData object-lifecycle dependency.

### ✅ The Pattern: Prefer Scalar Mirrors, Lazily Fault Relationships

`LocalScanRecord.serializedCapturedMediaItems` and
`OfflineQueuedScan.serializedCapturedMediaItems` must read `capturedMediaJSON`
first and only evaluate `capturedMediaEntries` as a fallback when the JSON is
absent or invalid:

```swift
if let capturedMediaJSON,
   let jsonItems = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
    return jsonItems
}

if let capturedMediaEntries, !capturedMediaEntries.isEmpty {
    return CapturedMediaEntry.serializedItems(from: capturedMediaEntries)
}
```

Keep the relationship mirror populated for migration/debugging/fallback
durability, but do not make SwiftUI hot paths depend on it while the scalar
timeline is valid. Regression coverage lives in
`SerializedMediaItemTests.swift`.

---

## 10. Offline Queue Durability: Enqueue at Submission, Not at Rescue

The previous architecture attempted to rescue in-flight live inference captures
by calling `enqueueCapture()` from background-phase or sheet-dismiss handlers.
This pattern is structurally broken for three compounding reasons:

1. **`Task(priority: .background)` starvation** — rescue tasks created after the
   app enters the background are queued at the lowest cooperative priority. iOS
   may suspend the process before the task scheduler gives them CPU time.
2. **`isSyncing` guard deadlock** — `syncPendingScans()` guards with
   `guard !isSyncing`. If a prior sync cycle is still in-flight (pending network
   response), the rescue's sync call is silently dropped. The scan enters
   SwiftData as `.pending` and stalls indefinitely until the next foreground.
3. **In-memory timing window** — `prepareForNewScan()` clears
   `activeLiveCaptureDatas` synchronously. `analyze()` repopulates it, but only
   after `capturedPreFetchTask?.value` resolves (GPS/weather fetch, 1–3 s). If
   rescue fires during this window, the image data is gone.

### ✅ The Pattern: Enqueue Immediately at Submission

The caller-scoped admission preview may suspend before a queue row exists, so it
must preserve staged input. After that preview succeeds and the captured staging
snapshot is revalidated, call `enqueueCapture()` synchronously before awaiting
environment context or starting provider work. Use the already-cached GPS
(`EnvironmentContextManager.lastKnownLocation` — live location tracking runs
while the camera is active). Generate both a stable `scanId` and, when a live
request is eligible, a foreground inference UUID. The queue transaction must
persist that UUID on the scan-ingestion job, and the concurrent live inference
must receive the same value.

```swift
// In submitStagedCapture, after admission and before context/provider Tasks:
let scanId = UUID().uuidString.lowercased()
let foregroundGeneration =
    admissionRoute == .foreground && offlineQueueManager.isOnline ? UUID() : nil
diContainer.offlineQueueManager.enqueueCapture(
    imageDatas: datasToAnalyze,
    telemetry: immediateTelemetry,
    blurScore: nil,
    scanId: scanId,
    foregroundInferenceGeneration: foregroundGeneration,
    onQueued: { didQueue in
        // Start live inference only after didQueue == true, passing both values.
    }
)
```

## 11. `ScanCollection.scans` Is Not a Free Read Path

`ScanCollection.scans` is a relationship fault, not a cheap array property.
Using it in SwiftUI hot paths (`CollectionCard`, selection toggles, detail
filtering) or historical reconciliation can fault a large graph onto the main
actor and trigger frame drops or OOM spikes on big libraries.

### ✅ The Pattern: Project For The Consumer

- Build lightweight membership snapshots from `LocalScanRecord.collections`.
- Cache collection counts, member ID sets, and optional cover scans in value
  types such as `CollectionMembershipSnapshot`.
- Use those snapshots in SwiftUI instead of repeatedly asking a collection for
  `scans?.count`, `contains`, or full member arrays.
- For collection upload, query the bounded non-Favorites `ScanCollection`
  owners, prefetch their direct `scans` relationships once, and serialize sorted
  member IDs. Never rediscover those memberships by walking unrelated
  `LocalScanRecord` rows with `fetchOffset`.
- At the Edge boundary, hydrate existing `collection_scans` rows with the
  `(collection_id, scan_id)` keyset cursor and write only the computed
  membership delta. Do not reintroduce progressively slower range/offset pages.
- Admit collection ownership through the atomic `upsert_owned_collections`
  result, never a SELECT-then-service-role-upsert preflight. Use only accepted
  IDs downstream. Add memberships through `insert_owned_collection_scans`, which
  joins both parents to the caller; missing/foreign parents are skippable, while
  RPC/read/write errors must remain retryable failures.
- Recovery sweeps such as lookalike-cache clearing must include a predicate and
  fetch limit; unbounded full-library fetches are zero-OOM violations.

## 12. Auth and Store Bootstrap Must Not `fatalError`

Login/bootstrap failures happen on real devices: no key window yet, a cleared
Apple callback nonce, `SecRandomCopyBytes` failure, or a corrupted local store.
These are operational failures, not programmer assertions.

### ✅ The Pattern: Recover Or Degrade

- Apple Sign-In should log and cancel if a presentation anchor or nonce is
  unavailable.
- `MerianEnvironment.load()` should return typed diagnostics, not hard-crash on
  missing plist keys. Optional SDKs can skip setup, and Supabase endpoint
  construction should throw `MerianError.invalidURL` until config is valid.
- `ModelContainer` creation should attempt corruption-specific quarantine once,
  archive non-corrupt legacy migration failures under `store-rescue/`, and then
  fall back to an in-memory safe mode if recovery still fails.
- If in-memory safe mode also fails, render a startup-blocked recovery surface
  without attaching `.modelContainer`; do not use `try!`.
- User-facing startup banners are acceptable; crash loops are not.

## 12.1 Offline Queue Must Not Prime Live Inference State

Offline queued-only visual and non-visual submissions must not call
`InferenceEngine.prepareForNewScan()`. That method intentionally sets
`isProcessing = true` so the insight sheet routes to the analyzing skeleton. If
the device is offline and the code returns after enqueueing, no live inference
task exists to clear that state.

### ✅ The Pattern: Prepare Only After Online Confirmation

1. Snapshot media, create any eligible foreground generation, and enqueue both
   durable work and that owner.
2. Wait for queue acceptance and recheck `OfflineQueueManager.isOnline`.
3. If offline, clear `pendingAnalyzeScanId`, show a toast, and return.
4. If online, call `prepareForNewScan()`, open the insight sheet, and start live
   inference.

```swift
// In the Task — fire live inference concurrently:
await MainActor.run {
    guard self.diContainer.inferenceEngine.isProcessing else { return }
    self.diContainer.inferenceEngine.analyze(
        scanId: scanId,
        foregroundInferenceGeneration: foregroundGeneration,
        ...
    )
}
```

## 13. Remote Media Validation Requires Exact Host Checks

`url.contains("merian.app")` is not validation. It accepts malicious hosts such
as `merian.app.attacker.tld`.

### ✅ The Pattern: `URLComponents` + Exact Allowlist

- Parse with `URLComponents`.
- Require `https`.
- Allow only exact approved hosts such as `media.merian.app`.
- Convert to `[URL]` before crossing actor boundaries so export/download workers
  do not re-parse untrusted strings.

## 14. Persisted View Settings Should Not Live In Views

Scattering `@AppStorage("...")` across hot SwiftUI surfaces creates two
long-term problems: duplicated storage-key knowledge and hidden coupling between
unrelated views that mutate the same preference.

### ✅ The Pattern: `UserDefaultsKeys` + `AppSettings`

- Keep storage names in `UserDefaultsKeys`.
- Expose typed, observable properties through `AppSettings`.
- Inject `AppSettings` via environment, or through the owning view model/manager
  initializer for tests.
- Use `diContainer.appSettings` inside `CaptureWorkspaceViewModel` and related
  modality extensions so previews and tests do not mutate global defaults.
- Treat global UI flags as settings too: unread scan badge state, Explore
  unread/chip/onboarding state, post-identification notification prompt state,
  zoom controls, and foreground notification suppression all live on
  `AppSettings`.
- Use `refreshFromDefaults()` on foreground when a background delegate may have
  written persisted state while SwiftUI was suspended.
- Reserve direct `UserDefaults` access for typed keyed stores
  (`FieldNotesStore`, `ExploreShareStateStore`, `SpeciesPreferredNameStore`),
  migrations, throttle timestamps, synchronous system delegates that cannot hop
  to `@MainActor`, or tests validating the persistence layer itself. When a
  SwiftData repository owns the durable value, write SwiftData first and clear
  stale legacy keys only after save succeeds. Network DTOs and SwiftUI
  presentation models should not read legacy mirrors directly; hydrate
  view-model state from the repository with an explicit `ModelContext` instead.
- Per-entity stores should expose small static helpers and namespace-safe
  `clearAll` methods rather than letting view models concatenate key prefixes.

## 15. Detached Work Should Be Routed Through A Named Bridge

Raw `Task.detached` calls scattered through feature code make it hard to audit
which executor escapes are intentional and which are accidental.

### ✅ The Pattern: `DetachedWork`

- Use structured `Task {}` when work belongs to the caller’s lifecycle.
- Move stateful async work into actors or repositories when ownership matters.
- If a true detached bridge is still required, route it through `DetachedWork`
  and keep inputs `Sendable`.
- Add lint rules around feature-layer files so new raw `Task.detached` call
  sites do not creep back in unnoticed.

**On live inference success**: `analyze()` calls `deleteQueuedScan` with a
`ForegroundInferenceGenerationExpectation` for its exact durable owner. The
queue manager validates that expectation before and after URLSession task
enumeration, then cancels only matching work and removes the SwiftData record.
If upload/recovery already won or a replacement owns the scan, deletion is an
idempotent no-op. `ScanFinalizationCoordinator` and the durable generation check
prevent a duplicate `LocalScanRecord`.

**On dual-path finalization**: live inference and the background URLSession
inference result can complete the same `scanId` in separate SwiftData contexts.
All three local record finalizers (`processAndCleanupOfflineScan`,
`saveLiveScanRecord`, and `saveNonVisualRecord`) must acquire
`ScanFinalizationCoordinator` before fetching/inserting/replacing the final
`LocalScanRecord`. This per-scan async lock is intentionally above SwiftData: it
prevents Core Data's unique-constraint merge policy from ever having to
reconcile two concurrent `LocalScanRecord.id` writers.

This is especially important for mixed-media records.
`LocalScanRecord.capturedMediaEntries` is a to-many relationship with no
inverse. If two contexts race on the same unique scan id, Core Data may try to
merge the losing object's to-many relationship into the winning object and abort
with `NSMergePolicy _cannotResolveConflictOnEntity:relationshipWithNoInverse:`.
Do not "fix" that crash by changing merge policies or dropping the scalar JSON
mirror. Serialize finalization per scan id, then re-check whether the local
record already exists after waiting.

**On live inference cancellation or network failure**: the exact foreground
generation is synchronously retired and the background path resumes. A
cooperatively cancelled stale handler has no telemetry, circuit-breaker, haptic,
error-UI, retry, or deletion authority.

All rescue handlers (`dismissAnalysisToBackground`, `handleBackgroundPhase`
inference block, `InsightSheetView.onDisappear` rescue) are deleted.
`activeLiveCaptureDatas` and `isBackgroundRescued` are removed from
`InferenceEngine` entirely — they had no purpose outside the now-deleted rescue
pattern.

---

## 16. Failed `modelContext.save()` Does NOT Roll Back Pending Changes

In SwiftData (built on Core Data), a failed `save()` call leaves all pending
changes — inserts, deletes, property mutations — **in the context's pending
state**. They are not automatically rolled back. Subsequent operations on the
same context accumulate on top of the corrupted pending state.

### The Vulnerability

`processAndCleanupOfflineScan` inserts a `LocalScanRecord` into the background
context and calls `save()`. If the save fails (e.g., unique-constraint violation
on `LocalScanRecord.id`), the pending INSERT remains on the context. On the next
retry a second `processAndCleanupOfflineScan` call stacks a second pending
INSERT with the same `id` on top of the first → guaranteed unique-constraint
failure on every subsequent attempt.

```swift
// ❌ Reusing the shared queue actor for cleanup: a failed save corrupts the shared context
let sharedActor = resolvedQueueDbActor(container: container)
await sharedActor.processAndCleanupOfflineScan(...)  // save() fails
// Now sharedActor.modelContext has a stale pending INSERT stuck in it
await sharedActor.tryClaimForInference(...)           // next attempt stacks a second INSERT →
                                                      // unique-constraint failure forever
```

### ✅ The Pattern: Fresh Actor for Each Cleanup Attempt

Use a **fresh** `BackgroundDatabaseActor` for each
`processAndCleanupOfflineScan` call. A failed save is contained to that fresh
actor — it is simply discarded. The shared actor's context remains uncorrupted
and can continue to serve state-machine transitions correctly:

```swift
// ✅ Fresh actor per cleanup attempt: failure is contained and discarded
let cleanupActor = BackgroundDatabaseActor(modelContainer: container)
await cleanupActor.processAndCleanupOfflineScan(...)  // save() fails → cleanupActor discarded
// sharedActor.modelContext is unaffected; reconcileOrphanedInferencingScans works normally
```

Additionally, `processAndCleanupOfflineScan` itself should be **idempotent**:
check whether a `LocalScanRecord` with the target `id` already exists before
inserting, to prevent unique-constraint failures when a previous attempt
partially committed. This check must happen inside the
`ScanFinalizationCoordinator` critical section so an offline finalizer that
waited behind a live save sees the just-committed live row and skips insertion:

The same rule applies on the MainActor, queue manager, migration plan, and
historical sync actors. UI mutation paths must not show success, enqueue offline
sync, push cloud updates, or post search-index notifications until
`modelContext.save()` succeeds. Queue paths must not delete staged files, fire
push notifications, dispatch URLSession uploads, or consume a free-tier scan
slot unless the local queue mutation committed (or the slot is refunded on
failure). Visual submission must wait for `enqueueCapture`'s queued callback
before presenting queued success or starting live analysis; failed durable
writes own cleanup of orphaned source video/audio paths and must not leave the
UI in a false queued state. Video-aware queue finalization must use
`OfflineQueueManager.deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:)` so
inference-only frames can be deleted while adopted playback video, audio, and
display media are preserved. Custom migration stages must not clear scratchpad
backfill data or complete the migration after a failed save, and migration fetch
failures must propagate instead of being logged and ignored. Historical
reconciliation must not continue with failed pending updates or inserts still
attached to its context. On failure, call `modelContext.rollback()`, log an
`.error`, and keep external side effects untouched.
`InsightSheetViewModel.toggleScanInCollection(...)`,
`InsightSheetViewModel.markRecordViewedIfAppropriate(...)`, `UserTagsViewModel`
with `UserTagsDependencies`, `OfflineQueueManager.flushOfflineQueuedScan(...)`,
`OfflineQueueManager.softDeleteQueuedScan(...)`,
`OfflineQueueManager.deleteQueuedScan(...)`,
`OfflineQueueManager.enqueueCapture(...)`,
`OfflineQueueManager.enqueueNonVisualCapture(...)`,
`BackgroundDatabaseActor.markScansAsUploading(...)`, `MerianMigrationPlan`
custom saves, `ScanRepository.eradicateScan(...)`,
`ScanRepository.purgeAllData(modelContext:resetDerivedState:)`, and historical
`updateExistingScans` / `ingestScans` / `syncCollections` follow this
containment pattern. For custom tags, each successful local commit enqueues an
immutable cloud snapshot behind its predecessor; do not restore independent
fire-and-forget RPC tasks, because an older add may otherwise finish after a
newer removal. The snapshot must retain the authoring account ID and acquire an
exact `beginUnownedAccountBoundWork(expectedUserID:)` lease before using the
Supabase client. A remote failure is best-effort and does not roll back the
already committed local tag or search-index invalidation. The all-data purge
additionally requires its `resetDerivedState` closure. Callers must pass the
app-owned private-map sensitive reset so exact-coordinate snapshots, actor
indexes, and preview renders are detached and the active-map presentation reset
generation advances before the destructive SwiftData transaction begins; an
eventual library event is not the erasure boundary.

That video-aware signature is shorthand for media adoption. Any inference-owned
finalization must additionally supply its exact foreground or background
generation expectation; only an explicit user/system deletion may intentionally
cancel every generation without one.

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

## 17. Orphaned `.uploading` Scans When `generateUploadURLs` Fails Mid-Session

`syncPendingScans` calls `markScansAsUploading` to transition selected scans
from `.pending` to `.uploading` **before** dispatching the URLSession upload
tasks (see §4 — state must be persisted before the task dispatch boundary). This
is intentional and correct for the crash-recovery case. However it introduces a
trap when the next step fails:

If `generateUploadURLs` throws — e.g. because `syncTask` was cancelled when
`NWPathMonitor` fires offline as the user backgrounds — the catch block
schedules a retry via `syncPendingScans()`. But `syncPendingScans` only fetches
`scanStateRaw == 0` (`.pending`) records. The scans are now in `.uploading` and
are **permanently invisible to the retry** within that process session.

`reconcileOrphanedUploadingScans` cannot help here: it is gated to run once at
cold-start (before any upload tasks are dispatched), after which
`hasReconciledStartupState = true` permanently. The scans stay stuck in
`.uploading` and show an infinite spinner in the scans library until the app is
killed and relaunched.

### ✅ Fix: Reset Orphans Before Scheduling the Retry

In the `generateUploadURLs` catch block, cross-reference live URLSession tasks
and call `reconcileOrphanedUploadingScans` before the retry is scheduled. Scans
with a live upload task in-flight are left in `.uploading`; only true orphans
(no task, `generateUploadURLs` never reached `uploadTask.resume()`) are reset to
`.pending`.

```swift
} catch {
    // Reset scans we marked .uploading back to .pending.
    // generateUploadURLs failed before any URLSession tasks were dispatched, so every
    // .uploading scan without a live task is an orphan. Without this reset,
    // syncPendingScans only fetches .pending and the scan is never retried.
    let liveTasks = await session.allTasks
    let activeUploadIds = Set(liveTasks.compactMap { task in
        MediaStagingContract.parseUploadTaskDescription(task.taskDescription)?.scanId
    })
    await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeUploadIds)
    // ... schedule backoff retry
}
```

**Safety-net layer**: `replayInferenceForUploadedScans` also calls
`reconcileOrphanedUploadingScans` on every invocation (foreground return +
connectivity restore) using the same live-task cross-reference. This catches the
case where the `syncPendingScans` Swift Task is killed before its catch block
runs — a scenario the primary fix cannot handle.

---

## 18. Cold-Start Timing Gap: Reconcile Completes After `syncPendingScans` Already Ran

**Scenario**: The app is killed while a scan is in `.uploading` state — e.g. the
user launches a scan and exits the app within ~1 second before
`generateUploadURLs` returns and URLSession upload tasks are dispatched. On
cold-start, the scan is `.uploading` with no active URLSession task.

**The gap**: `handleActivePhase` calls `syncPendingScans()` and
`replayInferenceForUploadedScans()` in separate async Tasks. `syncPendingScans`
internally calls `replayInferenceForUploadedScans()` first (line 131). On
cold-start, `replayInferenceForUploadedScans` sets
`hasReconciledStartupState = true`, fires an async Task (the cold-start
reconcile), and **returns immediately**. `syncPendingScans` then fetches
`.pending` scans — finds **none** (the scan is `.uploading`) — and returns early
with `isSyncing = false`. The cold-start reconcile Task eventually completes,
resets `.uploading` → `.pending`, and calls `replayInferenceForUploadedScans()`
again. But the second `replayInferenceForUploadedScans()` only handles `.staged`
scans — it does not call `syncPendingScans()`. The `.pending` scan sits
permanently until the next connectivity change or foreground event.

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

`reconcileOrphanedUploadingScans` now returns `Bool` (`true` if any scans were
reset). The cold-start callback calls `syncPendingScans()` only when
`hadOrphans == true`:

```swift
let hadOrphans = await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeIds)
await MainActor.run {
    if hadOrphans { self.syncPendingScans() }  // pick up newly-reset .pending scans immediately
    self.replayInferenceForUploadedScans()
}
```

Guarding on `hadOrphans` is essential. An unconditional `syncPendingScans()`
call fires even when the reconcile found nothing — in the common case (no
orphaned uploads) this triggers a spurious second sync on every cold-start,
interfering with the backoff timer and causing test instability via the
`isSyncing` latch.

**Note**: Do NOT add `syncPendingScans()` to the normal-path callback in
`replayInferenceForUploadedScans`. The normal path is called from within
`syncPendingScans` itself (line 131). Adding `syncPendingScans()` there creates
a recursive chain: `syncPendingScans` → `replayInferenceForUploadedScans` →
normal Task → `syncPendingScans` → `replayInferenceForUploadedScans` → another
Task → `reconcileOrphanedInferencingScans` → resets legitimately-claimed
`.inferencing` scans → `replayInferenceStagedScans` → claims them again →
infinite oscillation.

---

## 19. `activeScanId` Stale Hydration Window

`InferenceEngine.activeScanId` is set at the start of `analyze()` with a unique
`activeLiveInferenceAttemptGeneration`. The background offline path
(`OfflineQueueManager+URLSession`) may hydrate the live engine only when it
still owns both values:

```swift
if engine.commitRecoveredBackgroundResult(
    for: scanId,
    replacingAttemptGeneration: presentationGeneration,
    expectedForegroundGeneration: releasedForegroundGeneration,
    speciesData: speciesData
) {
    engine.inferenceTask?.cancel()
}
```

**The bug (fixed)**: scan ID alone left an ABA window. A delayed background
completion could target a replacement attempt for the same scan; conversely, the
cooperatively cancelled live task could resume its error handler after
background recovery published a result.

**The fix**: every live task captures its presentation UUID and durable
foreground generation. It checks the full owner at task entry, after suspension,
immediately before provider dispatch, and before result or failure side effects.
Background recovery compares the exact UUID and absence of a new foreground
owner, then atomically invalidates the live presentation slot before publishing
and cancelling the old task. Explicit cancellation also clears `activeScanId`
synchronously because its invalidated task defer no longer owns the slot:

```swift
defer {
    if isLocalLiveInferenceAttemptCurrent(
        scanId: ownedScanId,
        attemptGeneration: attemptGeneration
    ) {
        isProcessing = false
        activeScanId = nil
        activeLiveInferenceAttemptGeneration = nil
    }
}
```

The hydration window is therefore bounded by ownership, not timing or
cooperative cancellation.

Failure handlers must snapshot the full current-owner result before registering
synchronous retirement. Only a proven current owner may then emit telemetry,
record a circuit-breaker failure, trigger an error haptic, or assign an error
placeholder, with no intervening `await`. Rechecking only the process-local scan
ID or presentation UUID is insufficient: a durable foreground owner may already
have been retired or replaced while those local values still match.

`load(from:)` must follow the same replacement protocol before assigning a
historical record ID. Merely overwriting `activeScanId` makes the old live task
fail its local checks without giving it a way to relinquish the durable
foreground generation, which can suppress recovery indefinitely. The method
therefore invalidates and retires the live UUID first, cancels its provider and
hydration tasks, and leaves the queued row for background replay.

---

## 20. `@Observable` Struct Properties: Optional-Chain Mutations Do Not Reliably Fire Notifications

`InferenceEngine` holds `var speciesData: SpeciesData?` where `SpeciesData` is a
**struct** on an `@Observable` class. SwiftUI's `@Observable` macro synthesizes
`get`/`set` accessors (not `_modify`) for stored properties. Because a `_modify`
accessor is absent, optional-chain mutations like `self.speciesData?.field = x`
go through a copy-on-write cycle at the compiler level rather than through
`withMutation(keyPath:)` — and empirically do **not** reliably fire observation
notifications to subscribed views.

### ❌ The Anti-Pattern

```swift
// Any or all of these may silently fail to notify @Observable observers:
self.speciesData?.habitatDescription = "..."
self.speciesData?.referenceImageUrl = imgUrl
self.speciesData?.taxonomy = taxonomy
```

Views that track `inferenceEngine.speciesData` via `@Observable` (e.g.
`HabitatAndDistributionCard`) will not re-render when mutations are applied this
way, even though the data is correctly written in memory. The card appears stuck
or empty until something else forces a re-render (e.g. the user dismisses and
reopens the sheet). `ImagesCarousel` is no longer in this category — it receives
all data as injected parameters from `InsightSheetViewModel`, which in turn
reads from the engine. The re-render chain still applies transitively through
the viewModel's computed properties (`refUrls`, `activeMedia`, `totalImages`).

### ✅ The Required Pattern: Single Full-Value Replacement

Collect **all** mutations into a local copy, then assign back in a single write.
The single setter call goes through `withMutation(keyPath: \.speciesData)` and
guarantees exactly one observation notification for the entire batch:

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

All write paths in `InferenceEngine` that modify `speciesData` follow this
pattern:

| Function                                | Fields written                                                                                                                                               |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `fetchAndApplyEnrichment`               | `habitatDescription`, `gbifTaxonKey`, `taxonomy`, `similarSpecies`                                                                                           |
| `fetchWikipediaAndHydrate`              | `wikipediaOverview`, `wikipediaUrl`, `referenceImageUrl`                                                                                                     |
| `fetchAndPatchOverrideData` (cache hit) | `commonName`, `insightData`, `taxonomy`, `iucnRedListStatus`, `habitatDescription`, `gbifTaxonKey`, `referenceImageUrl`, `wikipediaOverview`, `wikipediaUrl` |
| `applyIdentificationOverride` (wipe)    | All contextual fields reset to nil + override identity fields                                                                                                |
| Historical load path                    | `similarSpecies`, `candidates`                                                                                                                               |

### Why This Matters for Live UI

The insight sheet is open while background hydration tasks
(`fetchWikipediaAndHydrate`, `fetchAndApplyEnrichment`,
`fetchAndPatchOverrideData`) complete asynchronously. If these tasks use
optional-chain mutations, the cards (`HabitatAndDistributionCard`,
`TaxonomyCard`, `SimilarSpeciesGallery`) will not update live — the user sees
empty or skeleton states until the sheet is dismissed and reopened. Full-value
replacement ensures cards populate in real time without any user interaction.
`ImagesCarousel` receives its data through `InsightSheetViewModel` computed
properties, so the same full-value-replacement rule applies at the engine level
— the viewModel's observation chain propagates changes correctly only when
`speciesData` itself is replaced, not field-mutated.

Transient image failures are deliberately absent from the table:
`ImagesCarousel` owns them as scan-scoped presentation state and never edits
`speciesData.referenceImageUrl` or the persisted media timeline. Changing the
scan clears that transient state, resets page selection, and restores muted
video playback.

---

## 21. `@Model` Zombie Crash in `LazyVGrid` via Deferred Attribute Fault

**Symptom**: Fatal error
`"This backing data was detached from a context without resolving attribute faults"`
on a property like `OfflineQueuedScan.capturedMediaEntries`, scalar
`capturedMediaJSON`, or any lazily faulted media/telemetry attribute,
originating inside a `LazyVGrid` `ForEach` body — **after** the object has been
deleted from the context.

**Why it happens**: SwiftUI's `LazyVGrid` evaluates view closures lazily — tile
bodies are computed only when the row scrolls into the viewport. If a `@Model`
attribute (for example the queued scan's media payload) was never accessed
before deletion, it is still in a faulted state (unfulfilled). SwiftUI's
`@Observable` machinery also registers observation dependencies on the `@Model`
object when the grid first reads it. After `context.delete(scan)` fires, SwiftUI
re-evaluates the view (responding to the deletion notification), triggering a
fault on the already-deleted object — which crashes immediately.

The same crash path applies anywhere a deleted `@Model` reference can be
re-evaluated: inside `InsightSheetViewModel` computed properties that branch on
queued scan media, or inside `QueuedContentView` views that read the queued
scan's telemetry fields.

### ❌ The Anti-Pattern

```swift
// Holding a live @Model reference across a deletion boundary
@State private var queuedScan: OfflineQueuedScan?

// LazyVGrid tile
ScanThumbnail(imagePath: queued.capturedMediaSnapshot.primaryImagePath) // CRASH after context.delete(queued)

// InsightSheetViewModel
var queuedImagePaths: [String] {
    if let scan = queuedScan { return scan.capturedMediaSnapshot.imagePaths } // CRASH
    ...
}
```

### ✅ The Pattern: Value-Type Snapshot at Fetch Time

Copy all needed data out of the `@Model` object into a plain value-type struct
**while the object is live** — before any `context.delete()` can fire. The grid
and the insight sheet chain then hold only the value type; no `@Model` reference
survives the boundary.

```swift
// QueuedScanSnapshot — for grid tiles
struct QueuedScanSnapshot: Identifiable, Equatable {
    let id: String
    let imagePath: String?
    let capturedMediaJSON: String?
    let queueState: ScanQueueState
    let timestamp: Date
    let queueNextRetryAt: Date?
    let queueNeedsAttention: Bool
    let approximateQueuedBytes: Int64  // internal diagnostics, not user-facing
    var gridId: String { "q_\(id)" }  // namespace against LocalScanRecord IDs
}

// QueuedScanContext — for the full insight sheet chain
struct QueuedScanContext: Identifiable {
    let id: String
    let capturedMediaItems: [SerializedMediaItem]
    let queueState: ScanQueueState
    let timestamp: Date
    let locationName: String?
    let weatherTemperatureF: Double?
    let weatherCondition: String?
    let gpsElevation: Double?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    init(from scan: OfflineQueuedScan) { /* copy while live */ }
}

// In ScansShellDataStore.queuedSnapshots(in:) — map before deletion can fire
let queuedSnapshots = fetched.map {
    QueuedScanSnapshot(
        id: $0.id,
        imagePath: $0.capturedMediaSnapshot.primaryImagePath,
        timestamp: $0.timestamp
    )
}

// In LibraryView — resolve the completion race, then snapshot before routing
if let completedRecord = localScanRecord(id: snapshot.id) {
    onSelect(completedRecord)
} else if let queuedContext = queuedScanContext(id: snapshot.id) {
    onQueuedInsight?(queuedContext)  // helper copied all live fields NOW
}

// In ScansSheetView — the view retains view-local navigation, not data loading
onQueuedScanSelected: { context in
    navigationPath.append(QueuedScanInsightRoute(queuedScan: context))
}
```

**`gridId` namespacing**: `LocalScanRecord.id` and `QueuedScanSnapshot.id` share
the same UUID (both use `client_scan_id`). Without namespacing, `LazyVGrid`'s
`ForEach` produces duplicate `AnyHashable` keys, causing SwiftUI to skip one
tile entirely. `gridId = "q_\(id)"` guarantees a distinct key for every
queued-scan tile.

**`InsightSheetViewModel.queuedContext: QueuedScanContext?`**: All computed
properties that previously switched on a live `OfflineQueuedScan?` now switch on
`queuedContext == nil`. `QueuedContentView` receives `QueuedScanContext` rather
than a `@Model` reference, and the queued media path is always rebuilt from
`queuedContext.capturedMediaSnapshot` instead of faulting properties off the
deleted model. `ScansShellDataStore` owns the queue-to-value projection;
`ScansSheetView` retains the resulting context in its private pushed route while
hashing and comparing by scan ID, so the destination survives queue deletion and
completed-result handoff without a nested sheet.

---

## 22. Field Notes Need a Single Local/Private Boundary

Field notes exist in three local stores during migration and offline flows:
`LocalScanRecord.fieldNotes`, `OfflineQueuedScan.fieldNotes`, and the legacy
`FieldNotesStore` bridge in `UserDefaults`. Explore posts can also expose a
public copy through `field_notes`, but that value is not the private source of
truth.

### The Vulnerability

If each view fetches and writes these stores independently, subtle ordering
differences can erase notes. For example, an Explore post may still have public
field notes while the local scan appears empty; a direct write from the Explore
UI can accidentally clear or overwrite the private scan-library note when
toggling visibility or reopening the insight sheet.

### The Pattern: `FieldNotesRepository`

Use `FieldNotesRepository` for all local/private note reads, writes, clears, and
Explore repair. Resolve it at a feature effect boundary rather than directly in
a SwiftUI view. Insight Field Notes adapts it through
`InsightFieldNotesDependencies`, whose initializer-injected closures keep the
editor and Shell state deterministic:

```swift
let notes = FieldNotesRepository.fieldNotes(
    for: scanId,
    modelContext: modelContext,
    activeRecord: record
)

FieldNotesRepository.setFieldNotes(
    updatedText,
    for: scanId,
    modelContext: modelContext,
    activeRecord: record
)
```

The repository resolves SwiftData records before the legacy bridge, mirrors
successful reads into the bridge, and promotes bridge-only values back into
SwiftData. Writes must explicitly save SwiftData, roll back on failure, and
update `FieldNotesStore` only after the database commit succeeds. Public Explore
notes may only enter local storage through
`promoteExternalFieldNotesIfLocalMissing(...)`, which refuses to overwrite
existing local/private notes.

---

## 23. SwiftUI `.id(...)` Modifier on Lazy Containers Tearing Down Swift Concurrency Tasks

When building dynamic feed lists or nested comments layouts, you must not use
the `.id(...)` identity-forcing modifier to force updates on view container
hierarchies (like a `LazyVStack` or `ScrollView`) driven by dynamic view model
states.

### The Vulnerability: The "Feedback Loop of Doom"

If a container enclosing a list carries a dynamic identity modifier like
`.id(viewModel.replyStateVersion)`, any modification of the inner state that
increments that version will force SwiftUI to completely tear down and recreate
the entire view tree.

- When SwiftUI destroys the view container, it **immediately cancels** all
  running asynchronous `.task` operations inside its subviews.
- Upon instantaneous recreation of the view container, those `.task` blocks
  re-initialize, dispatch new requests, modify states, increment the version
  tracker again, and immediately trigger a subsequent view tear down.
- **The Result**: An infinite, highly destructive CPU-burning loop of task
  cancellation and view recreation, leaving the UI stuck in loading spinners and
  starving cooperative async queues.

### ✅ The Recommended Pattern: Property-Level `@Observable` Redraws

Under iOS 17's `@Observable` framework, SwiftUI automatically tracks property
access down to the finest granular level. Let SwiftUI's diffing engine handle
animatable row-level updates naturally. Never apply `.id(...)` to the enclosing
collection or layout container for state synchronization.

```swift
// ❌ The Anti-Pattern: Tearing down containers on view model updates
LazyVStack {
    ForEach(viewModel.comments) { comment in
        commentThread(comment)
    }
}
.id(viewModel.replyStateVersion) // DANGER: Cancels concurrent Tasks inside subviews on every state write!

// ✅ The Correct Pattern: Let @Observable handle fine-grained updates automatically
LazyVStack {
    ForEach(viewModel.comments) { comment in
        commentThread(comment)
    }
}
```

## 2026-04 Hardening Updates

- Treat `ModelContainer` startup failures as data-loss-sensitive.
  Corruption-class failures may quarantine `default.store`, `default.store-wal`,
  and `default.store-shm`; non-corrupt failures on legacy migration strategies
  may archive those artifacts under `store-rescue/` before attempting
  recreation.
- Never delete local media before the corresponding SwiftData delete/save
  succeeds. Broken ordering leaves detached records pointing at missing files
  and is now explicitly forbidden.
- Background actor delete paths must use `rollback()` on save failure rather
  than `try? save()`. Silent save failure is architecture drift, not acceptable
  resilience.
- `MerianMigrationPlan` custom stages must use the shared migration save helper
  rather than `try? context.save()` or bare `try context.save()`. If a backfill
  cannot be committed, rollback and throw; opening the upgraded store without
  the backfilled fields is worse than surfacing a migration failure. Stage
  fetches must also use the concrete source/target schema type, never active
  global models or `CurrentSchema`, to avoid SwiftData casting traps during
  historical migrations. Relationship targets created during a custom migration
  must be schema-scoped snapshots too; active relationship models can still
  carry active-owner metadata. Insert newly created relationship rows into the
  migration `ModelContext` before assigning them to a relationship; relationship
  assignment alone is not a safe insert path during staged migration.
- Lookalike cache invalidation must stay batched and biological-only.
  `BackgroundDatabaseActor.clearAllLocalLookalikesCache()` is regression-tested
  with more than one batch of biological records plus a non-biological control
  record so a future unbounded fetch or predicate drift is caught.

---

## 24. SwiftData `propertiesToFetch` Assertion Crash on Optional Attributes

When querying records using a `FetchDescriptor` and limiting the columns loaded
via `propertiesToFetch`, you must be extremely careful not to include any
optional primitive properties (such as `String?`, `Double?`, or `[String]?`).

### The Vulnerability

Using optional properties inside the `propertiesToFetch` keypath array compiles
successfully but causes an immediate **`EXC_BREAKPOINT (SIGTRAP)`** crash at
runtime during query compilation inside `modelContext.fetch(descriptor)`:

```
Thread 4 Crashed::  Dispatch queue: NSManagedObjectContext 0x600003904b60
0   libswiftCore.dylib            	_assertionFailure(_:_:file:line:flags:) + 244
1   SwiftData                     	[Internal serialization helper]
2   SwiftData                     	[Query compiler entrypoint]
3   SwiftData                     	[FetchDescriptor serialization]
4   libswiftCore.dylib            	_KeyedEncodingContainerBox.encodeNil<A>(forKey:) + 184
5   libswiftCore.dylib            	KeyedEncodingContainer.encodeNil(forKey:) + 36
```

- **Why it happens**: When converting the `FetchDescriptor`'s keypaths into a
  Core Data properties-to-fetch representation, SwiftData's custom query encoder
  attempts to serialize the schema properties. Since the target property is
  optional, it tries to encode its nil-ability, calling `encodeNil(forKey:)` on
  the query encoder.
- **The Trap**: SwiftData's internal query encoder leaves `encodeNil(forKey:)`
  unimplemented. When called, it hits an explicit `_assertionFailure()` and
  traps the process with a `SIGTRAP` crash.

This makes using `propertiesToFetch` on columns like
`capturedMediaJSON: String?`, `coverImagePath: String?`, or
`wikipediaOverview: String?` extremely dangerous.

### ✅ The Pattern: Remove Projections for Optional Fields

To bypass this framework bug safely, **completely omit the `propertiesToFetch`
projection** from `FetchDescriptor`s whenever any of the requested properties
are optional:

```swift
// ❌ The Anti-Pattern: Triggers KeyedEncodingContainer.encodeNil assertion failure
var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.scanStateRaw == pendingRaw })
descriptor.propertiesToFetch = [\.id, \.capturedMediaJSON] // capturedMediaJSON is optional String?
let pending = try modelContext.fetch(descriptor)

// ✅ The Correct Pattern: Omit propertiesToFetch projection completely
var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.scanStateRaw == pendingRaw })
let pending = try modelContext.fetch(descriptor) // Fetches the full lightweight object safely
```

Because these metadata models (`OfflineQueuedScan` and `LocalScanRecord`) are
highly compact and database operations occur asynchronously on a dedicated
`@ModelActor` queue, fetching the full record carries negligible overhead and is
100% crash-free.

---

## 25. Replay Intents Are Not Raw Media Archives

`identify-multimodal` now writes a paired `scan_ingestion_intents` row alongside
`scan_ingestion_jobs`. This is a durable server replay contract for accepted
scan-ingestion attempts, but it is intentionally not a dump of the original
client payload.

### The Vulnerability

Treating `request_payload` as a complete request archive can create two classes
of bugs:

- A privacy/storage bug if future code tries to persist raw `imageBase64s`,
  `audioBase64s`, or local device file paths.
- A recovery bug if server tooling assumes an inline-media request can be
  replayed without the iOS offline queue.

Inline foreground media is redacted before persistence. The intent records only
counts for those inline media arrays and sets `resumable = false` plus
`inline_media_redacted = true`. Queued/staged media requests are the replayable
case because the payload contains server-owned staged object keys, media
descriptors, upload-session ids, telemetry, observation context, and checksums.
Current intent schema version 3 stores each observation context as bounded
`freeText` only. It never persists the retired capture-composition `addedAt` /
`added_at` field. Schema-v2 rows remain replay-readable; multimodal's input
normalizer discards any legacy timestamp before a new intent, scan row, or
Captured Media manifest is written.

### The Pattern: Store The Sanitized Intent, Keep Raw Media Client-Owned

When adding or changing ingestion payload fields:

- Add metadata fields to `_shared/scanIngestionIntents.ts` only if they are safe
  to store server-side.
- Preserve `ownerMediaTimeline` absence for old intents; do not synthesize an
  empty authoritative timeline, and never reintroduce description timestamps as
  a second chronology source.
- Keep raw media bytes, private file paths, and unbounded text out of
  `request_payload`.
- Use `payload_checksum` and `manifest_checksum` to prove retry shape, not to
  smuggle raw request bodies into Postgres.
- Treat `resumable = false` as a hard boundary: server tools can diagnose or
  mark the job for client retry, but cannot independently reconstruct the
  original media.

Video remains stricter than still images: a new video scan is not complete until
the playback `.mp4` is promoted and represented in both `video_storage_urls` and
the `captured_media` timeline. The sampled video frames are inference inputs,
not shareable replacement media.

---

## 26. An AI Response Is Not a Durable Scan Until the Owner Row Is Read Back

`/identify-multimodal` used to construct its AI response and schedule
moderation, media promotion, species resolution, and `insertScan` as background
work. iOS then saved the local result on `200`, while Explore and Field Chat
could immediately fail because `public.scans` was absent.

### The anti-pattern

```typescript
runBackground(runBackgroundIngestion());
return successResponse(aiResult);
```

`EdgeRuntime.waitUntil` is appropriate for bounded optional work; it cannot turn
required persistence into an HTTP success guarantee.

### The required pattern

```typescript
await runDurableIngestion();
await readScanByIdAndOwner(scanId, authenticatedUserId);
runBackground(runOptionalWrites());
return successResponse(aiResult);
```

The durable step includes moderation, required media promotion, primary species
resolution, duplicate-safe scan creation, owner read-back, and one database
finalization transaction. That transaction verifies every claimed staging key is
promoted or explicitly consumed, rebuilds canonical image/video/audio rows, and
writes ledger completion last. Operational failure returns retryable
`503 scan_persistence_failed`; terminal policy rejection returns
`400 observation_rejected`. iOS must retain its durable queue source or mark
terminal attention according to those statuses instead of creating a successful
local record.

Recovery does not weaken this rule. A bounded non-media `recovery_scan` exists
only for older/interrupted drift. Status/share routes independently validate
identity and fields, defer to active/retryable richer ingestion, allow exact
structured `replay_exhausted`, and require matching composite
dead-letter/quota/media-lifecycle proof for exact
`media_reconciliation_abandoned`, rejecting later committed policy authority.
They write without overwrite and reload by owner. Media continues through owner
staging. Never trust an abandoned terminal label alone or repair this class of
bug with a direct iOS table upsert, an `authenticated` grant, or a server key in
the app.

---

## 27. Redundant Queue Authority Must Reconcile Before Mutation

Scan-ingestion retry control is deliberately mirrored on `OfflineQueuedScan` and
its scan-keyed `OfflineJobRecord`. This lets the presented queue row and the
media-agnostic scheduler survive migrations and independent context lifecycles.
It also means one resident SwiftData fault can temporarily disagree with the
other after a cross-context save.

Never decide whether staging may reset retry metadata from only one copy. Build
one monotonic projection before every serialized mutation:

1. a cloud-complete recovery marker outranks server-retry state;
2. server-retry state present in either copy is authoritative;
3. the attempt count is `max(0, max(scanCount, jobCount))`, never a sum and
   never the value from whichever model happened to fault first; and
4. write the projected marker/count back to both models before applying the
   queue transition, then save them together.

Read-only preflight checks use a fresh `ModelContext` and consult both rows.
This prevents a cached main-context scan from hiding a background-actor commit.
The writer still runs under the scan inference persistence coordinator, so
mirror repair does not replace generation fencing. Missing or unreadable
authority must fail closed; a message string or approximate state is never
permission to dispatch Identify.

Regression tests must drift each redundant copy independently. At minimum, erase
the queue-row retry marker/counter while the job survives, pass through
`.pending → .uploading → .staged`, and prove the marker survives, the next
attempt advances, and a job-only cloud-complete marker vetoes a late inference
retry.

---

## 28. Compatibility Media Repair Must Be a Durable Queue Transition

A process-local preflight is not enough when an old app version could already
have persisted or started uploading a media format that a new inference contract
rejects. The app may terminate during conversion, a background PUT may finish
after upgrade, or staged object keys may still refer to the old bytes. Merely
transcoding a snapshot in memory leaves each of those paths able to replay the
incompatible object.

Use this sequence for persisted compatibility repair:

1. Hold the same per-subject coordinator used by the downstream claim.
2. In a short database transaction, re-fetch the exact eligible state, write a
   durable in-progress latch, retreat to a runnable pre-upload state, clear
   every derived staging key and background generation, and save.
3. Perform expensive file conversion outside the `ModelActor` transaction. Keep
   the source until commit and delete only newly generated artifacts on
   cancellation or failure.
4. Re-fetch and commit only if the state and latch still match. Rewrite every
   redundant persisted media representation atomically, record the completed
   generation, and require fresh signing.
5. Make all ordinary upload and inference claim sites reject the in-progress or
   still-legacy row. Intercept terminal callbacks from pre-upgrade uploads and
   route them through the same repair before dispatch.
6. Let higher-authority terminal state win. In particular, a proven
   cloud-complete recovery marker must veto local conversion and redispatch.

The queued-audio implementation reuses the existing V49
`queueSchemaRepairGeneration` scalar (`-1` claimed, `2` committed, `1`
ordinary/reset). That is a semantics change, not a persisted-model change, so it
does not justify a new SwiftData schema version. If a repair needs a new field,
relationship, uniqueness rule, or enum storage shape instead, follow the full
schema-update procedure and migration fixture matrix.

---

## 29. `PersistentModel.isDeleted` Is Framework State, Not App Storage

Every SwiftData `@Model` conforms to `PersistentModel`, which exposes
`isDeleted` as framework lifecycle state. Do not declare an application-owned
stored property with that Swift name. The declaration can compile and appear to
accept an assignment, while `ModelContext.save()` resolves the member as
framework state rather than a durable application attribute.

The released V50 `ScanCollection` demonstrates the failure: collection deletion
assigned its intended soft-delete marker to `true`, but an actual simulator save
left the held value `false`, and a fresh fetch also returned `false`. The active
V50 Swift type repairs the collision with `isPendingDeletion` mapped to the same
`isDeleted` column; the historical Swift property remains only in the frozen V50
fixture. Downstream code now serializes the durable value as `is_deleted`, so
enqueue ordering, inbound tombstone shielding, and acknowledgement-only purge
retain their intended guarantees.

### ❌ The Anti-Pattern: Shadow Framework Lifecycle Names

```swift
@Model
final class ScanCollection {
    var isDeleted = false // Collides with PersistentModel.isDeleted.
}
```

A successful `save()` call is not proof that the intended field persisted. Tests
must verify the held model, a fresh context fetch, and a reopened disk-backed
store. Payload tests must read the reopened model rather than a transient value
captured before the save.

### ✅ The Pattern: Migrate to a Domain-Specific Stored Name

Choose a non-reserved domain name, keep wire naming in the DTO mapper, and treat
the rename as a schema change. Freeze the outgoing schema before editing the
active model, then add one ordered lightweight migration and a source-isolated
plan for stores already on the outgoing version:

```swift
@Model
final class ScanCollection {
    @Attribute(originalName: "isDeleted")
    var isPendingDeletion = false
}

let payload = SyncCollectionPayload(
    // ...
    is_deleted: collection.isPendingDeletion
)
```

For Merian, the released V50 graph is frozen in `SchemaV50Snapshots.swift`;
`MerianActiveSchemaV50` maps the source property with
`@Attribute(originalName:)` while preserving the same persisted checksum and the
existing `is_deleted` JSON contract. A disk-backed V50 fixture passes through
the production startup selector, opens without a migration plan, and proves
save, refetch, restart, offline retention, exact payload mapping, inbound
reconciliation fencing, and acknowledgement-only purge. Because V50 did not
retain prior assignments, the migration does not invent or infer historical
delete intent.
