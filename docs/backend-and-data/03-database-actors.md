# Database Actors

Merian uses multiple Swift `@ModelActor` and `actor` types to safely perform SwiftData and disk I/O work off the main thread. This document explains which actor to use when, how `@ModelActor` isolation works, and why each actor is created ad-hoc rather than reused as a singleton.

---

## Why Actors?

The main thread owns the SwiftUI view hierarchy and the primary `ModelContext`. Performing bulk SwiftData fetches, large ingests, or disk I/O on the main thread causes visible UI stuttering and risks JetSam termination. Actors provide compile-time-enforced isolation: work inside an actor runs on that actor's executor, never blocking the main thread.

---

## Shared Data Transfer Objects (`Core/Data/OfflineSync/OfflineSyncTypes.swift`)

All `Sendable` value types shared across the offline sync pipeline live in a single file so they are visible to any reader without hunting through actor or extension files:

| Type | Purpose |
|---|---|
| `PendingScanPayload` | Minimal snapshot of a queued scan returned by `fetchPendingScans(limit:)`. Safe to pass across actor boundaries. |
| `ScanUploadItem` | One image file ready for a presigned R2 PUT — `scanId`, `imageIndex`, `fileName`, `fileURL`. |
| `ExtractedScanData` | Full `OfflineQueuedScan` snapshot captured on the main actor for handoff to background inference. |
| `OfflineScanProcessingResult` | Result of `processAndCleanupOfflineScan` — species name, discovery flag, `speciesData` for engine hydration, and `wasCleaned` flag controlling main-actor queue flush. |

---

## Actor Inventory

### `BackgroundDatabaseActor` (`Core/Data/Database/BackgroundDatabaseActor.swift`)

**Declaration**: `@ModelActor actor BackgroundDatabaseActor`

**Responsibilities:**

*Upload state machine (V33):*
- `fetchPendingScans(limit:)` — fetches `.pending` (state 0) `OfflineQueuedScan` records for upload dispatch. Scans in `.uploading`, `.staged`, `.inferencing`, or `.failed` states are excluded — they are either in-flight or terminal.
- `markScansAsUploading(scanIds:)` — transitions scans from `.pending → .uploading` and persists before URLSession tasks are dispatched. Source-state guard: predicate restricts the fetch to `.pending` records only, so in-flight or tombstoned scans cannot be double-dispatched.
- `markScanAsStaged(scanId:r2Keys:)` — called once the last image upload for a scan confirms HTTP 200. Persists the confirmed R2 object keys into `stagedR2Keys` and transitions `.uploading → .staged`. Source-state guard: only advances from `.uploading`; prevents a concurrent tombstone from being resurrected.
- `tryClaimForInference(scanId:)` — atomic distributed lock for inference. Transitions `.staged → .inferencing`; returns `false` if the scan is already `.inferencing` or not found. Because `BackgroundDatabaseActor` serializes all calls on its executor, only one pipeline can win this claim per scan — the race between `processUploadCompletion` and `replayInferenceForUploadedScans` is closed here.
- `transitionScanToStaged(id:)` — retreats `.inferencing → .staged` on transient inference failure so `replayInferenceForUploadedScans` can reclaim the scan on the next connectivity restore. Source-state guard: only retreats from `.inferencing` — will not overwrite a concurrent `softDeleteQueuedScan` tombstone (`.failed`) written by the MainActor.
- `reconcileOrphanedUploadingScans(activeScanIds:)` — called once per process life on first connectivity restore. Resets `.uploading → .pending` for scans with no active URLSession task. Safe because no upload tasks are dispatched during the startup window.
- `reconcileOrphanedInferencingScans(activeInferenceScanIds:)` — cross-references live `"inference_*"` URLSession tasks before resetting `.inferencing → .staged`. Only scans with no live OS task are reset, preventing duplicate inference dispatch against tasks still owned by the system after a relaunch.

*Offline scan processing:*
- `processAndCleanupOfflineScan(...)` — the top-level orchestration boundary. Decodes an edge inference result, orchestrates two inner helpers, then saves the `LocalScanRecord` to the background context. **The `OfflineQueuedScan` is intentionally NOT deleted here** — that is always delegated to the main actor's `flushOfflineQueuedScan` so the main `ModelContext` always has a real pending deletion when it saves (the only reliable `@Query` re-evaluation trigger in a presented sheet — SwiftData platform limitation: background-context saves do not reliably propagate to `@Query` in open sheets):
  1. `resolveSpeciesIdAndDiscoveryStatus()`: Decouples local species ID resolution and checks the global `LocalScanRecord` table to determine if the scan qualifies as a brand-new discovery for gamification hooks.
  2. `insertLocalScanRecordIfMissing()`: Builds and stages the final `LocalScanRecord` (including `candidatesData`, `inferenceTier`, `imageQualityScore`, and `alternativeCommonNames`) into the context. `alternativeCommonNames` is sourced from `SpeciesData.alternativeCommonNames` — populated from GBIF vernacular names on the first scan of a species (via `_shared/external.ts`) and served from `species_dictionary.alternative_common_names` on Cache Hit. On save failure, `modelContext.rollback()` clears the pending insert and `resolvedSpeciesName`, `finalScanId`, and `speciesData` are all cleared so the caller avoids emitting ghost notifications or hydrating an engine that lacks a committed database UUID.
- `saveLiveScanRecord(mappedData:localImagePaths:)` — persists a real-time scan result after live inference. Persists `imageQualityScore` (Gemini's photographic quality score, 0–100) from `SpeciesData`. Unlike `blurScore` (ephemeral, live-only, never written to disk), `imageQualityScore` is stored permanently for future community reference-photo curation.

*Enrichment and metadata:*
- `updateScanWithWikipedia(scanId:extract:url:imageUrl:)` — retroactively hydrates a scan with Wikipedia or GBIF data. By accepting optional `String?` parameters, this method permits selective patching (e.g., updating only `referenceImageUrl` from GBIF without overwriting an existing `wikipediaOverview`).
- `updateScanWithOverrideSpeciesData(scanId:commonName:hazardType:wikipediaOverview:wikipediaUrl:referenceImageUrl:iucnRedListStatus:habitatDescription:gbifTaxonKey:taxonomy:)` — persists species-dictionary data fetched for an identification override or reset so the corrected fields survive sheet dismissal and reopen. Intentionally excludes `scientificName` — that column is preserved as the original-AI identifier and is reused as `aiScientificName` in `InferenceEngine.load(from:)`.
- `updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:)` — retroactively persists enrichment data returned by the `enrich-scan` Edge Function. Called by `InferenceEngine.fetchAndApplyEnrichment` after the async enrichment call completes. Updates `habitatDescription`, `gbifTaxonKey`, `lookalikesData` (a JSON-encoded `[SimilarSpeciesEntry]` blob, added in `MerianSchemaV27`), and taxonomic ranks (`Kingdom` through `Genus`) on `LocalScanRecord`. The caller is responsible for encoding `[SimilarSpeciesEntry]` to `Data` via `JSONEncoder` before calling this method — the `JSONEncoder().encode()` call runs inside the background `Task { }` that creates this actor (not on `@MainActor`) to avoid blocking the UI run loop. Encode failures result in a `nil` payload so the field is never written with corrupt data.
- `pushCollectionsToEdge()` — serializes local `ScanCollection` records and calls the `sync-collections` Edge function. Upon a successful HTTP 200 response, it strictly purges any successfully synced tombstoned collections (`isDeleted == true`) from SwiftData to prevent ghost persistence. Note: its invocation is strictly serialised via an `isCollectionSyncing` gate in `OfflineQueueManager` to prevent out-of-order race conditions from resurrecting deleted local entities on the server.

**When to create**: Two patterns — ad-hoc for most operations, long-lived for inference:

```swift
// Ad-hoc: for live scan saving, enrichment, Wikipedia, collections
let container = modelContext.container
let dbActor = BackgroundDatabaseActor(modelContainer: container)
await dbActor.saveLiveScanRecord(mappedData: data, localImagePaths: paths)

// Long-lived: for the offline inference pipeline
// OfflineQueueManager maintains a single shared instance via resolvedInferenceDbActor(container:).
// This serializes markScanAsStaged + tryClaimForInference + transitionScanToStaged on one executor,
// closing the double-pipeline race between processUploadCompletion and replayInferenceForUploadedScans.
// Never call resolvedInferenceDbActor directly from outside OfflineQueueManager.
let inferenceActor = resolvedInferenceDbActor(container: container)
guard await inferenceActor.tryClaimForInference(scanId: scanId) else { return }
```

---

### `HistoricalDatabaseActor` (`Core/Data/Database/ScanRepository.swift`)

**Declaration**: `@ModelActor actor HistoricalDatabaseActor`

**Responsibilities:**
- `reconcileScanPage(responses:)` — primary entry point for streaming reconciliation; called once per page fetched from the cloud. Computes the existing-ID set once on the first call (ID-only projection) and caches it in `cachedLocalIds`, then updates existing records and ingests missing ones for the page. The `cachedLocalIds` set is updated incrementally as each page inserts new records, so the full local ID set is never re-fetched per page. Returns the count of newly inserted records.
- `syncCollectionsDown(remoteCollections:)` — called once, after all scan pages have been streamed. Delegates to `syncCollections` and then clears `cachedLocalIds`, releasing the accumulated set from memory.
- `cachedLocalIds` (private `var`) — `Set<String>?` that lives for the duration of a `syncHistoricalScansDown` call. `nil` before the first `reconcileScanPage` call and after `syncCollectionsDown` clears it.
- `updateExistingScans` (private) — predicate-scoped fetch with `propertiesToFetch` column projection; saves only if fields changed. Batches the incoming `responseIds` into chunks of 500 before building each `#Predicate`, preventing SQL IN-clause planner degradation on large libraries.
- `ingestScans` (private) — inserts new `LocalScanRecord` rows; checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (50) records
- `syncCollections` (private) — upserts `ScanCollection` records; fetches only the local scans referenced by incoming collections
- `reconcileAllHistoricalData(responses:collections:)` — **legacy, kept for test compatibility only**. Resets `cachedLocalIds`, delegates to `reconcileScanPage` once, then calls `syncCollectionsDown`. New call sites should use the `reconcileScanPage` / `syncCollectionsDown` pair.

**When to create**: Ad-hoc, once per `syncHistoricalScansDown` call. Use the paged API to stream one page at a time rather than accumulating the full cloud response in memory:
```swift
let dbActor = HistoricalDatabaseActor(modelContainer: container)

// Stream scan pages one at a time — never accumulate full allScans[] in memory
var scanOffset = 0
while true {
    let page: [HistoricalScanResponse] = try await ...
        .range(from: scanOffset, to: scanOffset + pageSize - 1)
        .execute().value
    if !page.isEmpty {
        await dbActor.reconcileScanPage(responses: page)
    }
    if page.count < pageSize { break }
    scanOffset += pageSize
}

// Collections are small in count — still fully accumulated, then synced once
await dbActor.syncCollectionsDown(remoteCollections: allCollections)
```

The design principle is page-at-a-time streaming: each page is processed and released before the next is fetched, keeping the in-memory scan accumulation O(page_size) rather than O(total_library_size) regardless of how many scans the user has.

---

### `ProfileDatabaseActor` (`Features/Profile/Components/Profile/UserStats.swift`)

**Declaration**: `@ModelActor actor ProfileDatabaseActor`

**Responsibilities:**
- `calculateAll()` — **preferred entry point**. Single fetch with an 11-column `propertiesToFetch` projection (superset covering stats, heatmap, and awards). Returns `(speciesCount: Int, streak: Int, heatmap: ProfileHeatmapData, awards: [AwardPayload])`. Replaces three sequential actor calls with one.
- `calculateProfileStats()` — fetches with `[\.scientificName, \.timestamp]` projection; computes species count and streak. Kept for call sites that only need these two values.
- `calculateHeatmapData()` — fetches with `[\.timestamp]` projection; computes the 52-week scan heatmap. Kept for call sites that only need heatmap data.
- `calculateAwards()` (extension in `Achievements.swift`) — fetches with the full 11-column projection; delegates to `AchievementsCalculator.calculate(from:)`. Called from `InferenceEngine` after every successful inference (not gated on `isNewDiscovery` — awards can trigger on any condition: time-of-day, taxonomy, elevation, etc.)

**When to create**: Ad-hoc. Use `calculateAll()` from `ProfileTabView` (single actor crossing for all profile data) and `calculateAwards()` from `InferenceEngine` (post-inference award refresh):
```swift
// ProfileTabView — single fetch for all profile data
let actor = ProfileDatabaseActor(modelContainer: container)
let (species, streak, heatmap, awards) = await actor.calculateAll()

// InferenceEngine — post-inference award refresh only
if let container = modelContext?.container {
    let profileActor = ProfileDatabaseActor(modelContainer: container)
    let updatedAwards = await profileActor.calculateAwards()
    await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
}
```

---

### `SearchDatabaseActor` (`Core/Data/Database/SearchDatabaseActor.swift`)

**Declaration**: `@ModelActor actor SearchDatabaseActor`

**Responsibilities:**
- `extractSearchablePayloads(from:)` — Generates `SearchableScan` structures for O(1) library text filtering. Evaluates attributes including `scientificName`, `ecologyType`, `taxonomy`, location data, and `customTags`. Uses `modelContext.model(for: id)` to map discrete IDs into memory sequentially without faulting the entire SQLite table array, preventing JetSam crashes.
- `commonGroupName(for:)` — Generates semantic mapping strings from taxonomy class limits (e.g. "Aves" -> "bird", "Insecta" -> "insect", "Mammalia" -> "mammal") to augment layperson searchability alongside AI reasoning text.

**When to create**: Created ad-hoc by `ScansManager` inside `Task.detached` blocks whenever library models mutate, or when `NSNotification.Name("ScanRequiresSearchIndexUpdate")` necessitates a targeted index hot-swap.
```swift
let dbActor = SearchDatabaseActor(modelContainer: container)
let newPayload = await dbActor.extractSearchablePayloads(from: [persistentId])
```

---

### `FileIOActor` (`Core/Data/Database/FileIOActor.swift`)

**Declaration**: `public actor FileIOActor`

**Responsibilities:**
- `writeTemporaryImages(imageDatas:)` — `async` method that writes `[Data]` to `URL.documentsDirectory` and returns `[String]` filenames in the same order as the input. Writes are parallelised: each image is dispatched to a `Task.detached` worker so all files are written concurrently rather than sequentially. On a 3-frame scan this reduces wall-clock write time from `3 × write_time` to `max(write_times)`. Filenames are UUID-based and guaranteed unique.
- `deleteImages(at:)` — deletes files by filename from `documentsDirectory` (skips `http://` paths — those are cloud-owned)
- `validPaths(from:)` — filters a list of paths/URLs down to those that actually exist on disk or are remote URLs

**When to use**: Always use `FileIOActor.shared` — it is a singleton. Never write or delete image files from `BackgroundDatabaseActor`, `@MainActor`, or `Task.detached`. All disk I/O for images flows through here.

```swift
let savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
await FileIOActor.shared.deleteImages(at: failedPaths)
```

**Why isolated from SwiftData actors**: Disk I/O and SQLite writes contend for different OS resources. Keeping them on separate actors prevents either from starving the other.

---

## `@ModelActor` Isolation Explained

`@ModelActor` is a Swift macro that:
1. Creates an actor with its own `ModelContext` bound to the provided `ModelContainer`.
2. Ensures all methods on the actor use that isolated `modelContext` — never the main thread's context.
3. Makes the actor `Sendable`, so it can be passed across task boundaries safely.

```swift
@ModelActor
actor BackgroundDatabaseActor {
    func doWork() {
        // `modelContext` here is isolated to this actor — safe to call fetch/save/insert
        let records = try? modelContext.fetch(FetchDescriptor<LocalScanRecord>())
    }
}
```

**Critical rule**: Never share a `ModelContext` across actors or threads. Always create a new actor instance with the `ModelContainer` (which IS thread-safe), not the `ModelContext`.

---

## Ad-hoc vs Singleton: Why Ad-hoc (and When Not)

Most `@ModelActor` actors are created ad-hoc (per operation) rather than stored as singletons because:

1. **`ModelContext` is not thread-safe** — a singleton actor holding a `ModelContext` would need to be the *only* writer for the duration of its operation. Ad-hoc creation gives each operation its own isolated context.
2. **Backpressure is explicit** — if `syncHistoricalScansDown` creates an actor and `await`s it, the caller naturally blocks until reconciliation is complete. A singleton with a queue would make this implicit and harder to reason about.
3. **No state leakage** — each operation starts with a fresh context. There is no risk of a previous operation's unflushed changes affecting the next one.

**Exception — long-lived inference actor**: `OfflineQueueManager` stores a single `BackgroundDatabaseActor` instance in `_inferenceDbActor` (accessed via `resolvedInferenceDbActor(container:)`). This is intentional:

- **Serialization**: All inference-path state transitions (`markScanAsStaged`, `tryClaimForInference`, `transitionScanToStaged`) must execute on the *same* actor executor to close the race between `processUploadCompletion` and `replayInferenceForUploadedScans`. A fresh actor per call would have its own executor, defeating the serial guarantee.
- **Performance**: Offline upload bursts can complete multiple scans in rapid succession. Reusing one actor avoids repeated `ModelContainer → ModelContext` setup cost per completion.
- The shared actor is still safe for concurrent callers — Swift actors serialize all calls through their executor automatically.

`FileIOActor` is also a singleton because it has no `ModelContext` and manages a single shared resource (the Documents directory).

---

## Decision Guide

| Task | Actor to use |
|---|---|
| Save a live scan result | `BackgroundDatabaseActor` (ad-hoc) |
| Transition scan state for upload pipeline | `BackgroundDatabaseActor` via `resolvedInferenceDbActor` (long-lived) |
| Claim a scan for inference (`tryClaimForInference`) | `BackgroundDatabaseActor` via `resolvedInferenceDbActor` (long-lived) |
| Reset scan to `.staged` on transient failure | `BackgroundDatabaseActor` via `resolvedInferenceDbActor` (long-lived) |
| Process an offline scan after upload | `BackgroundDatabaseActor` via `resolvedInferenceDbActor` (long-lived) |
| Startup reconciliation (orphan reset) | `BackgroundDatabaseActor` (ad-hoc, one-time per process) |
| Sync historical scans from cloud | `HistoricalDatabaseActor` (ad-hoc) |
| Calculate all profile data (stats + heatmap + awards) | `ProfileDatabaseActor.calculateAll()` (ad-hoc) |
| Calculate achievement awards only (post-inference) | `ProfileDatabaseActor.calculateAwards()` via `resolvedProfileDbActor` (long-lived) |
| Calculate profile stats (species count, streak) | `ProfileDatabaseActor.calculateProfileStats()` (ad-hoc) |
| Write image files to disk | `FileIOActor.shared` |
| Delete image files from disk | `FileIOActor.shared` |
| Validate image paths | `FileIOActor.shared` |
| Push collections to Edge | `BackgroundDatabaseActor` (ad-hoc) |
| Persist enrichment data after enrich-scan returns | `BackgroundDatabaseActor` (ad-hoc) |
