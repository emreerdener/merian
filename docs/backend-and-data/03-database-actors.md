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
| `PendingScanPayload` | Minimal snapshot of a queued scan returned by `fetchPendingScans(limit:)`, including local image and audio paths. Safe to pass across actor boundaries. |
| `ScanUploadItem` | One local media file ready for a presigned R2 PUT — `scanId`, `uploadIndex`, `fileName`, `fileURL`, `contentType`. |
| `ExtractedScanData` | Full `OfflineQueuedScan` snapshot captured on the main actor for handoff to background inference. Carries the canonical ordered `capturedMediaItems: [SerializedMediaItem]` timeline, from which image paths, audio paths, prompt text, and serialized observation contexts are derived on demand. |
| `OfflineScanProcessingResult` | Result of `processAndCleanupOfflineScan` — species name, discovery flag, `speciesData` for engine hydration, and `wasCleaned` flag controlling main-actor queue flush. |

---

## Actor Inventory

### `BackgroundDatabaseActor` (`Core/Data/Database/BackgroundDatabaseActor.swift`)

**Declaration**: `@ModelActor actor BackgroundDatabaseActor`

**Responsibilities:**

*Upload state machine (V33):*
- `fetchPendingScans(limit:)` — fetches `.pending` (state 0) `OfflineQueuedScan` records for upload dispatch and returns both image and audio paths derived from the canonical media timeline. Scans in `.uploading`, `.staged`, `.inferencing`, or `.failed` states are excluded — they are either in-flight or terminal.
- `markScansAsUploading(scanIds:)` — transitions scans from `.pending → .uploading`, persists before URLSession tasks are dispatched, and returns the claimed scan IDs. Source-state guard: predicate restricts the fetch to `.pending` records only, so in-flight or tombstoned scans cannot be double-dispatched. Fetch/save failures rollback the actor context and return an empty set so the caller does not sign or dispatch unclaimed files.
- `markScanAsStaged(scanId:r2Keys:)` — called once the last media upload for a scan confirms HTTP 200. Persists the confirmed image/audio R2 object keys into `stagedR2Keys` and transitions `.uploading → .staged`. Source-state guard: only advances from `.uploading`; prevents a concurrent tombstone from being resurrected. Save failure rolls back the actor context.
- `tryClaimForInference(scanId:)` — atomic distributed lock for inference. Transitions `.staged → .inferencing`; returns `false` if the scan is already `.inferencing`, not found, or if the save fails and rolls back. Because `BackgroundDatabaseActor` serializes all calls on its executor, only one pipeline can win this claim per scan — the race between `processUploadCompletion` and `replayInferenceForUploadedScans` is closed here.
- `transitionScanToStaged(id:)` — retreats `.inferencing → .staged` on transient inference failure so `replayInferenceForUploadedScans` can reclaim the scan on the next connectivity restore. Source-state guard: only retreats from `.inferencing` — will not overwrite a concurrent `softDeleteQueuedScan` tombstone (`.failed`) written by the MainActor. Save failure rolls back the actor context.
- `reconcileOrphanedUploadingScans(activeScanIds:)` — called once per process life on first connectivity restore. Resets `.uploading → .pending` for scans with no active URLSession task and returns `true` only when that save commits. Safe because no upload tasks are dispatched during the startup window.
- `reconcileOrphanedInferencingScans(activeInferenceScanIds:)` — cross-references live `"inference_*"` URLSession tasks before resetting `.inferencing → .staged`. Only scans with no live OS task are reset, preventing duplicate inference dispatch against tasks still owned by the system after a relaunch. Save failure rolls back the actor context.

*Offline scan processing:*
- `processAndCleanupOfflineScan(...)` — the top-level orchestration boundary. Accepts the queued scan's ordered mixed-media timeline, decodes an edge inference result, orchestrates two inner helpers, then saves the `LocalScanRecord` to the background context. **The `OfflineQueuedScan` is intentionally NOT deleted here** — that is always delegated to the main actor's `flushOfflineQueuedScan` so the main `ModelContext` always has a real pending deletion when it saves (the only reliable `@Query` re-evaluation trigger in a presented sheet — SwiftData platform limitation: background-context saves do not reliably propagate to `@Query` in open sheets):
    1. `resolveSpeciesIdAndDiscoveryStatus()`: Decouples local species ID resolution and checks the global `LocalScanRecord` table to determine if the scan qualifies as a brand-new discovery for gamification hooks.
    2. `insertLocalScanRecordIfMissing(...)`: Builds and stages the final `LocalScanRecord` (including `candidatesData`, `inferenceTier`, `imageQualityScore`, `alternativeCommonNames`, `capturedMediaJSON`, and `capturedMediaEntries`) into the context. `alternativeCommonNames` is sourced from `SpeciesData.alternativeCommonNames` — populated from GBIF vernacular names on the first scan of a species (via `_shared/external.ts`) and served from `species_dictionary.alternative_common_names` on Cache Hit. On save failure, `modelContext.rollback()` clears the pending insert and `resolvedSpeciesName`, `finalScanId`, and `speciesData` are all cleared so the caller avoids emitting ghost notifications or hydrating an engine that lacks a committed database UUID.
- `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:)` — persists a real-time scan result after live inference. Accepts the current media timeline plus legacy-derived arrays, then writes the mixed-media payload into both `capturedMediaJSON` and `capturedMediaEntries`. The JSON mirror is the preferred hot read path for `CapturedMediaSnapshot`; the relationship mirror remains populated for migration/debugging/fallback durability. Persists `imageQualityScore` (Gemini's photographic quality score, 0–100) from `SpeciesData`. Unlike `blurScore` (ephemeral, live-only, never written to disk), `imageQualityScore` is stored permanently for future community reference-photo curation. It reuses `resolveSpeciesIdAndDiscoveryStatus(...)` and `insertReplacingLocalScanRecord(...)`; this preserves an existing species UUID and staged field notes while replacing any queued/offline collision row with the richer foreground result. Save failure rolls back and returns `false`, suppressing downstream new-discovery side effects for an uncommitted record.
- `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:mediaTimeline:)` — persists description-only, audio-only, or mixed non-visual results after `/identify-multimodal` inference when there are no local image files. Uses the same ordered media timeline as the visual path and the same private replacement helper as live saves, but keeps its modality-specific `coverImagePath == nil` / `isLiveCapture == false` behavior. Save failure rolls back and returns `false`.

*Enrichment and metadata:*
- `updateScanWithOverride(scanId:override:confirmed:newConfirmedSpeciesId:userReviewState:)` — atomic persistence for user review states. Saves the explicit user Identification Override locally, captures truth signals, and synchronously persists the verified Edge taxonomy target directly into `confirmedSpeciesId` bridging the `userReviewState` explicitly.
- `updateScanWithWikipedia(scanId:extract:url:imageUrl:)` — retroactively hydrates a scan with Wikipedia or GBIF data. By accepting optional `String?` parameters, this method permits selective patching (e.g., updating only `referenceImageUrl` from GBIF without overwriting an existing `wikipediaOverview`). Save failure rolls back the actor context, matching the shared `mutateScan(...)` containment used by enrichment and override point-updates.
- `updateScanWithOverrideSpeciesData(scanId:commonName:hazardType:wikipediaOverview:wikipediaUrl:referenceImageUrl:iucnRedListStatus:habitatDescription:gbifTaxonKey:taxonomy:)` — persists species-dictionary data fetched for an identification override or reset so the corrected fields survive sheet dismissal and reopen. Intentionally excludes `scientificName` — that column is preserved as the original-AI identifier and is reused as `aiScientificName` in `InferenceEngine.load(from:)`.
- `updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:alternativeCommonNames:)` — retroactively persists enrichment data returned by the `enrich-scan` Edge Function. Called by `InferenceEngine.fetchAndApplyEnrichment` after the async enrichment call completes. Updates `habitatDescription`, `gbifTaxonKey`, `lookalikesData` (a JSON-encoded `[SimilarSpeciesEntry]` blob, added in `MerianSchemaV27`), and taxonomic ranks (`Kingdom` through `Genus`) on `LocalScanRecord`. When `alternativeCommonNames` is non-nil, the method also writes it to `record.alternativeCommonNames` on the `LocalScanRecord`. The caller is responsible for encoding `[SimilarSpeciesEntry]` to `Data` via `JSONEncoder` before calling this method.
- `clearAllLocalLookalikesCache()` — recovery path for stale similar-species caches. Fetches only biological records with `lookalikesData` or `similarSpecies` present, in 200-record batches, saving after each batch. Save failure rolls back the current batch and exits. It must not use an unbounded `FetchDescriptor<LocalScanRecord>()`.
- `pushCollectionsToEdge()` — serializes local `ScanCollection` records and calls the `sync-collections` Edge function. Membership is built from bounded batches of `LocalScanRecord.collections`, not from `ScanCollection.scans`, to avoid faulting many-to-many arrays for large libraries. Upon a successful HTTP 200 response, it strictly purges any successfully synced tombstoned collections (`isDeleted == true`) from SwiftData to prevent ghost persistence. The tombstone purge save is explicit: failures rollback the actor context and return `false` so `OfflineQueueManager` keeps the collection-sync flag pending for a later retry. Note: callers must route invocation through `OfflineQueueManager`'s shared collection drain (`syncCollectionsIfPending()` / `drainCollectionSyncIfPossible()`) rather than calling it as an unsynchronised side path.

**When to create**: Two patterns — ad-hoc for most operations, long-lived for inference:

```swift
// Ad-hoc: for live scan saving, enrichment, Wikipedia, collections
let container = modelContext.container
let dbActor = BackgroundDatabaseActor(modelContainer: container)
await dbActor.saveLiveScanRecord(
    mappedData: data,
    localImagePaths: paths,
    observationContextsJSON: obsJSONs,
    audioFilePaths: audioPaths,
    mediaTimeline: mediaTimeline
)

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
- `reconcileScanPage(responses:)` — primary entry point for streaming reconciliation; called once per page fetched from the cloud. Computes the existing-ID set fresh each call via a chunked `FetchDescriptor` with `propertiesToFetch = [\.id]` (ID-only column projection), then delegates to `updateExistingScans` and `ingestScans` for the page. Returns the count of newly inserted records.
- `syncCollectionsDown(remoteCollections:)` — called once, after all scan pages have been streamed. Delegates to `syncCollections`.
- `updateExistingScans` (private) — **chunk-process-save** loop: for each stride of 500 IDs, fetches that chunk's full `LocalScanRecord` objects, mutates changed fields, calls `modelContext.save()` if any field changed, then lets the chunk's references fall out of scope so ARC reclaims the heap before the next stride. Save failures rollback the historical actor context before the next chunk. A single `JSONEncoder` is hoisted above both loops to avoid per-record allocation overhead. Prevents IN-clause planner degradation and bounds peak faulted-object count to one chunk.
- `ingestScans` (private) — inserts new `LocalScanRecord` rows; checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (100) records. Checkpoint and final save failures rollback the pending insert batch so failed historical ingestion cannot poison later sync attempts.
- `syncCollections` (private) — upserts `ScanCollection` records; fetches local scans referenced by incoming collections and builds current membership from bounded inverse-side `LocalScanRecord.collections` batches. Save failures rollback the main `ModelContext` so partial inbound names, deletes, or membership rewrites do not remain pending after reconciliation fails.
- `reconcileAllHistoricalData(responses:collections:)` — **legacy, kept for test compatibility only**. Delegates to `reconcileScanPage` once, then calls `syncCollectionsDown`. New call sites should use the `reconcileScanPage` / `syncCollectionsDown` pair.

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

**When to create**: Ad-hoc for profile tab; long-lived shared instance for post-inference award refresh:
```swift
// ProfileTabView — single fetch for all profile data (ad-hoc)
let actor = ProfileDatabaseActor(modelContainer: container)
let (species, streak, heatmap, awards) = await actor.calculateAll()

// InferenceEngine — post-inference award refresh only (long-lived shared instance)
// OfflineQueueManager.shared.resolvedProfileDbActor(container:) returns a cached
// ProfileDatabaseActor, reusing the same ModelContext across consecutive inferences
// instead of allocating a fresh actor per scan.
let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: container)
let updatedAwards = await profileActor.calculateAwards()
await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
```

> **Why long-lived for `calculateAwards()`?** On a burst of offline scan completions (or rapid successive live scans), `analyze()` calls `calculateAwards()` after every result. Allocating a fresh `ProfileDatabaseActor` — and with it a fresh `ModelContext` — per scan wastes actor setup overhead and generates unnecessary SQLite context churn. `resolvedProfileDbActor` maintains one actor per `ModelContainer` identity; Swift actor serialization ensures concurrent callers queue safely.

---

### `SearchDatabaseActor` (`Features/Scans/ViewModels/ScansManager.swift`)

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
- `deleteFiles(at:)` — generalized deletion entry point for absolute file paths, `documentsDirectory` filenames, and mixed cleanup lists captured during queue/tombstone cleanup.
- `validPaths(from:)` — filters a list of paths/URLs down to those that actually exist on disk or are remote URLs

**When to use**: Always use `FileIOActor.shared` — it is a singleton. Never write or delete image files from `BackgroundDatabaseActor`, `@MainActor`, or `Task.detached`. All disk I/O for images flows through here.

```swift
let savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
await FileIOActor.shared.deleteImages(at: failedPaths)
```

**Why isolated from SwiftData actors**: Disk I/O and SQLite writes contend for different OS resources. Keeping them on separate actors prevents either from starving the other.

### `ArchiveTransferWorker` (`Core/Data/Images/ArchiveManager.swift`)

**Declaration**: `private actor ArchiveTransferWorker`

**Responsibilities:**
- Owns the heavy download / temp-file / photo-library rescue work triggered by `ArchiveManager`.
- Streams aging cloud images to disk off the main actor and moves rescued files into the local library.
- Keeps `ArchiveManager` itself free to remain an `@MainActor` lifecycle coordinator without mixing UI state and large file/network work on the same executor.

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

## 2026-05 Collection Projection Rule

Large collection membership reads should be projected from `LocalScanRecord.collections`, not by repeatedly faulting `ScanCollection.scans` on UI or reconciliation paths. `BackgroundDatabaseActor.pushCollectionsToEdge()` and `ScanRepository.syncCollections` now build membership maps from bounded scan-side batches.

---

## Decision Guide

| Task | Actor to use |
|---|---|
| Save a live scan result | `BackgroundDatabaseActor` (ad-hoc) via `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:)` |
| Save a text-only, audio-only, or mixed non-visual result | `BackgroundDatabaseActor` (ad-hoc) via `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:mediaTimeline:)` |
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

## 2026-04 Hardening Updates

- `BackgroundDatabaseActor.buildScanRecord` now preserves the original capture timestamp for offline inserts. Offline replay no longer rewrites chronology to "time of sync", so library ordering, streaks, heatmaps, and analytics stay faithful to when the user actually captured the scan.
- The non-biological bulk-delete actor path now inserts cloud-deletion tombstones and deletes SwiftData rows first, then saves transactionally. Local files are purged only after the save succeeds.
- Save failures inside bulk deletion now rollback the actor `ModelContext` and surface the error to the caller instead of being swallowed with `try?`.
