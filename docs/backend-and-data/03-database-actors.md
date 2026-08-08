# Database Actors

Merian uses multiple Swift `@ModelActor` and `actor` types to safely perform
SwiftData and disk I/O work off the main thread. This document explains which
actor to use when, how `@ModelActor` isolation works, and why each actor is
created ad-hoc rather than reused as a singleton.

---

## Why Actors?

The main thread owns the SwiftUI view hierarchy and the primary `ModelContext`.
Performing bulk SwiftData fetches, large ingests, or disk I/O on the main thread
causes visible UI stuttering and risks JetSam termination. Actors provide
compile-time-enforced isolation: work inside an actor runs on that actor's
executor, never blocking the main thread.

---

## Shared DTOs And Coordination

All `Sendable` value types shared across the offline sync pipeline live in a
single file so they are visible to any reader without hunting through actor or
extension files:

| Type                                  | Purpose                                                                                                                                                                                                                                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PendingScanPayload`                  | Minimal snapshot of a queued scan returned by `fetchPendingScans(limit:)`, including local image and audio paths. Safe to pass across actor boundaries.                                                                                                                                                |
| `ScanUploadItem`                      | One local media file ready for a presigned R2 PUT — `scanId`, per-scan `uploadIndex`, `mediaKind`, `fileName`, `fileURL`, `contentType`, and expected `objectKey`.                                                                                                                                     |
| `ExtractedScanData`                   | Full `OfflineQueuedScan` snapshot captured on the main actor for handoff to background inference. Carries the canonical ordered `capturedMediaItems: [SerializedMediaItem]` timeline, from which image paths, audio paths, prompt text, and serialized observation contexts are derived on demand.     |
| `OfflineScanProcessingResult`         | Result of `processAndCleanupOfflineScan` — species name, discovery flag, `speciesData` for engine hydration, and `wasCleaned` flag controlling main-actor queue flush.                                                                                                                                 |
| `ScanFinalizationCoordinator`         | Per-scan async lock used by live visual, live non-visual, and background URLSession finalizers before they write `LocalScanRecord.id`. Prevents Core Data unique-constraint merge policy from merging no-inverse media relationships when the two inference paths complete the same scan concurrently. |
| `ScanInferencePersistenceCoordinator` | Per-scan async lock shared by every `BackgroundDatabaseActor` instance and the main-actor queue deletion path. It keeps the durable inference-generation check, URLSession cancellation, retry retreat/finalization, and SwiftData save inside one compare-before-mutate critical section.             |

Both coordinators live beside `BackgroundDatabaseActor`, not in
`OfflineSyncTypes.swift`, because they are executable coordination rather than
transport DTOs. The in-memory lock is not the ownership authority:
`OfflineJobRecord.metadataJSON` stores the UUID generation transactionally with
`.staged → .inferencing`, and every late retry, completion, or delete must match
that durable value. A `nil` value may be adopted only for work already in flight
during the rollout; a non-`nil` generation is never overwritten by a different
attempt.

---

## Actor Inventory

### `BackgroundDatabaseActor` (`Core/Data/Database/BackgroundDatabaseActor.swift`)

**Declaration**: `@ModelActor actor BackgroundDatabaseActor`

**Responsibilities:**

_Upload state machine (V33):_

- `fetchPendingScans(limit:)` — fetches `.pending` (state 0) `OfflineQueuedScan`
  records for upload dispatch and returns both image and audio paths derived
  from the canonical media timeline. Scans in `.uploading`, `.staged`,
  `.inferencing`, or `.failed` states are excluded — they are either in-flight
  or terminal.
- `markScansAsUploading(scanIds:)` — transitions scans from
  `.pending → .uploading`, persists before URLSession tasks are dispatched, and
  returns the claimed scan IDs. Source-state guard: predicate restricts the
  fetch to `.pending` records only, so in-flight or tombstoned scans cannot be
  double-dispatched. Fetch/save failures rollback the actor context and return
  an empty set so the caller does not sign or dispatch unclaimed files.
- `markScanAsStaged(scanId:r2Keys:)` — called once the last media upload for a
  scan confirms HTTP 200. Persists the confirmed image/audio R2 object keys into
  `stagedR2Keys`, normally resets upload retry metadata, updates the queue job,
  and transitions `.uploading → .staged` in one save. Source-state guard: only
  advances from `.uploading`; prevents a concurrent tombstone from being
  resurrected. It returns `.staged` only after save, `.alreadyAdvanced` for a
  serialized matching staged manifest or inferencing owner, `.retryRequired`
  for retryable fetch/state/manifest/save failure, and `.discarded` for missing
  or non-runnable rows. Save failure rolls back every part of the transaction,
  and the upload callback cannot continue to an inference claim from
  uncommitted or mismatched keys. An exact scheduled
  `server_retryable_failure` reclaim preserves its marker, count, last attempt,
  and matching job metadata through a required re-stage.
- `tryClaimForInference(scanId:generation:)` — atomic local-persistence lock for
  inference. It transitions `.staged → .inferencing` and saves the generation in
  the same transaction; returns `false` if the scan is already `.inferencing`,
  not found, cancelled while waiting, or if the save fails and rolls back.
  `ScanInferencePersistenceCoordinator` serializes independent SwiftData
  contexts for that scan, so only one pipeline can win the claim. The race
  between `processUploadCompletion` and `replayInferenceForUploadedScans` is
  closed at the persistence boundary.
- `transitionScanToStaged(id:)` — retreats `.inferencing → .staged` on transient
  inference failure so `replayInferenceForUploadedScans` can reclaim the scan on
  the next connectivity restore. Source-state guard: only retreats from
  `.inferencing` — will not overwrite a concurrent `softDeleteQueuedScan`
  tombstone (`.failed`) written by the MainActor. Save failure rolls back the
  actor context.
- Generation-aware claims persist the attempt UUID in the scan-ingestion job.
  Retry scheduling, retreat, final record persistence, and queue deletion
  acquire `ScanInferencePersistenceCoordinator`, compare that UUID, and discard
  stale callbacks before they can save or cancel URLSession work.
- `reconcileOrphanedUploadingScans(activeScanIds:observedThrough:)` — resets
  `.uploading → .pending` for scans with no active URLSession task and returns
  `true` only when that save commits. The caller captures `observedThrough`
  before enumerating tasks; rows claimed after that snapshot have a newer
  `queueUpdatedAt` and cannot be reset by the delayed reconciliation pass.
- `reconcileOrphanedInferencingScans(activeInferenceScanIds:observedThrough:)` —
  cross-references current and legacy inference URLSession tasks before
  resetting `.inferencing → .staged`. It uses the same snapshot cutoff, so a
  replacement inference claim cannot be mistaken for an orphan while the actor
  call is queued. Save failure rolls back the actor context.

_Offline scan processing:_

- `processAndCleanupOfflineScan(...)` — the top-level orchestration boundary.
  Accepts the queued scan's ordered mixed-media timeline, decodes an edge
  inference result, orchestrates two inner helpers, then saves the
  `LocalScanRecord` to the background context. **The `OfflineQueuedScan` is
  intentionally NOT deleted here** — that is delegated to the main actor's
  queue-deletion path so the main `ModelContext` always has a real pending
  deletion when it saves (the only reliable `@Query` re-evaluation trigger in a
  presented sheet — SwiftData platform limitation: background-context saves do
  not reliably propagate to `@Query` in open sheets). Video-aware completion
  uses `deleteQueuedScan` with adopted media paths and the exact background or
  foreground generation expectation. This allows queued inference frames to be
  purged while video/audio/display media adopted by the final `LocalScanRecord`
  survives, without granting stale work deletion authority:
  1. `resolveSpeciesIdAndDiscoveryStatus()`: Decouples local species ID
     resolution and checks the global `LocalScanRecord` table to determine if
     the scan qualifies as a brand-new discovery for gamification hooks.
  2. `insertLocalScanRecordIfMissing(...)`: Builds and stages the final
     `LocalScanRecord` (including `candidatesData`, `inferenceTier`,
     `imageQualityScore`, `alternativeCommonNames`, `capturedMediaJSON`, and
     `capturedMediaEntries`) into the context. `alternativeCommonNames` is
     sourced from `SpeciesData.alternativeCommonNames` — populated from GBIF
     vernacular names on the first scan of a species (via `_shared/external.ts`)
     and served from `species_dictionary.alternative_common_names` on Cache Hit.
     On save failure, `modelContext.rollback()` clears the pending insert and
     `resolvedSpeciesName`, `finalScanId`, and `speciesData` are all cleared so
     the caller avoids emitting ghost notifications or hydrating an engine that
     lacks a committed database UUID. The existing-record check runs after
     acquiring `ScanFinalizationCoordinator`, so if a live path committed the
     same `scanId` while the background finalizer waited, offline finalization
     skips the insert instead of relying on unique-constraint merge recovery.
- `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:persistenceFence:)`
  — persists a real-time scan result after live inference. Accepts the current
  media timeline and legacy-derived arrays. Queue-backed live callers also
  provide `LiveInferencePersistenceFence(scanId:generation:)`; a stale durable
  owner or mismatched provider scan ID is rejected before writing. The method
  writes the mixed-media payload into both `capturedMediaJSON` and
  `capturedMediaEntries`. The JSON mirror is the preferred hot read path for
  `CapturedMediaSnapshot`; the relationship mirror remains populated for
  migration/debugging/fallback durability. Persists `imageQualityScore`
  (Gemini's photographic quality score, 0–100) from `SpeciesData`. Unlike
  `blurScore` (ephemeral, live-only, never written to disk), `imageQualityScore`
  is stored permanently for future community reference-photo curation. It
  acquires `ScanFinalizationCoordinator` for `mappedData.scanId`, then reuses
  `resolveSpeciesIdAndDiscoveryStatus(...)` and
  `insertReplacingLocalScanRecord(...)`; this preserves an existing species UUID
  and staged field notes while replacing any queued/offline collision row with
  the richer foreground result. The durable generation is revalidated while
  holding the per-scan persistence coordinator before finalization and save.
  Save failure rolls back and returns `.notSaved`, suppressing downstream
  new-discovery side effects for an uncommitted record.
- `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:mediaTimeline:persistenceFence:)`
  — persists description-only, audio-only, or mixed non-visual results after
  `/identify-multimodal` inference when there are no local image files. Uses the
  same ordered media timeline, live persistence fence, and private replacement
  helper as visual saves, but keeps its modality-specific
  `coverImagePath == nil` / `isLiveCapture == false` behavior. It also acquires
  `ScanFinalizationCoordinator` before species resolution and replacement so
  audio/description live completion cannot race the background completion for
  the same queued scan. Save failure rolls back and returns `.notSaved`.

_Enrichment and metadata:_

- `updateScanWithOverride(scanId:override:confirmed:newConfirmedSpeciesId:userReviewState:)`
  — atomic persistence for user review states. Saves the explicit user
  Identification Override locally, captures truth signals, and synchronously
  persists the verified Edge taxonomy target directly into `confirmedSpeciesId`
  bridging the `userReviewState` explicitly.
- `updateScanWithWikipedia(scanId:extract:url:imageUrl:)` — retroactively
  hydrates a scan with Wikipedia or GBIF data. By accepting optional `String?`
  parameters, this method permits selective patching (e.g., updating only
  `referenceImageUrl` from GBIF without overwriting an existing
  `wikipediaOverview`). Save failure rolls back the actor context, matching the
  shared `mutateScan(...)` containment used by enrichment and override
  point-updates.
- `updateScanWithOverrideSpeciesData(scanId:commonName:hazardType:wikipediaOverview:wikipediaUrl:referenceImageUrl:iucnRedListStatus:habitatDescription:gbifTaxonKey:taxonomy:)`
  — persists species-dictionary data fetched for an identification override or
  reset so the corrected fields survive sheet dismissal and reopen.
  Intentionally excludes `scientificName` — that column is preserved as the
  original-AI identifier and is reused as `aiScientificName` in
  `InferenceEngine.load(from:)`.
- `updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:alternativeCommonNames:)`
  — retroactively persists enrichment data returned by the `enrich-scan` Edge
  Function. Called by `InferenceEngine.fetchAndApplyEnrichment` after the async
  enrichment call completes. Updates `habitatDescription`, `gbifTaxonKey`,
  `lookalikesData` (a JSON-encoded `[SimilarSpeciesEntry]` blob, added in
  `MerianSchemaV27`), and taxonomic ranks (`Kingdom` through `Genus`) on
  `LocalScanRecord`. When `alternativeCommonNames` is non-nil, the method also
  writes it to `record.alternativeCommonNames` on the `LocalScanRecord`. The
  caller is responsible for encoding `[SimilarSpeciesEntry]` to `Data` via
  `JSONEncoder` before calling this method.
- `clearAllLocalLookalikesCache()` — recovery path for stale similar-species
  caches. Fetches only biological records with `lookalikesData` or
  `similarSpecies` present, in 200-record batches, saving after each batch. Save
  failure rolls back the current batch and exits. It must not use an unbounded
  `FetchDescriptor<LocalScanRecord>()`.
- `collectionSyncPayloads()` / `pushCollectionsToEdge()` — fetches only
  non-Favorites `ScanCollection` rows, prefetches their direct inverse `scans`
  relationships, and emits deterministic, sorted membership IDs. It does not
  enumerate unrelated `LocalScanRecord` rows and does not use OFFSET pagination.
  The Edge function then computes the database membership delta. Upon a
  successful HTTP 200 response, the actor strictly purges successfully synced
  tombstones (`isDeleted == true`) from SwiftData. A purge save failure rolls
  back and returns `false`, so `OfflineQueueManager` retains the pending
  collection job. Callers must use the shared collection drain
  (`syncCollectionsIfPending()` / `drainCollectionSyncIfPossible()`), never an
  unsynchronised side path.

**When to create**: Two patterns — ad-hoc for most operations, long-lived for
the offline queue state machine:

```swift
// Ad-hoc: for live scan saving, enrichment, Wikipedia, collections
let container = modelContext.container
let dbActor = BackgroundDatabaseActor(modelContainer: container)
let fence = LiveInferencePersistenceFence(
    scanId: scanId,
    generation: foregroundGeneration
)
await dbActor.saveLiveScanRecord(
    mappedData: data,
    localImagePaths: paths,
    observationContextsJSON: obsJSONs,
    audioFilePaths: audioPaths,
    mediaTimeline: mediaTimeline,
    persistenceFence: fence
)

// Long-lived: for offline upload/inference claims, retries, and orphan recovery.
// OfflineQueueManager maintains one instance via resolvedQueueDbActor(container:).
// The shared executor plus observedThrough cutoffs keep a stale reconcile from
// overwriting a replacement upload or inference claim.
// Never call resolvedQueueDbActor directly from outside OfflineQueueManager.
let queueActor = resolvedQueueDbActor(container: container)
guard await queueActor.tryClaimForInference(scanId: scanId) else { return }
```

---

### `HistoricalDatabaseActor` (`Core/Data/Database/ScanRepository.swift`)

**Declaration**: `@ModelActor actor HistoricalDatabaseActor`

**Responsibilities:**

- `reconcileScanPage(responses:)` — primary entry point for streaming
  reconciliation; called once per page fetched from the cloud. Computes the
  existing-ID set fresh each call via a chunked `FetchDescriptor` with
  `propertiesToFetch = [\.id]` (ID-only column projection), then delegates to
  `updateExistingScans` and `ingestScans` for the page. Returns the count of
  newly inserted records.
- `syncCollectionsDown(remoteCollections:)` — called once, after all scan pages
  have been streamed. Delegates to `syncCollections`.
- `updateExistingScans` (private) — **chunk-process-save** loop: for each stride
  of 500 IDs, fetches that chunk's full `LocalScanRecord` objects, mutates
  changed fields, calls `modelContext.save()` if any field changed, then lets
  the chunk's references fall out of scope so ARC reclaims the heap before the
  next stride. Save failures rollback the historical actor context before the
  next chunk. A single `JSONEncoder` is hoisted above both loops to avoid
  per-record allocation overhead. Prevents IN-clause planner degradation and
  bounds peak faulted-object count to one chunk.
- `ingestScans` (private) — inserts new `LocalScanRecord` rows; checkpoint-saves
  every `MerianConfig.ingestCheckpointInterval` (100) records. Checkpoint and
  final save failures rollback the pending insert batch so failed historical
  ingestion cannot poison later sync attempts.
- `syncCollections` (private) — upserts `ScanCollection` records; fetches local
  scans referenced by incoming collections and builds current membership from
  bounded inverse-side `LocalScanRecord.collections` batches. Save failures
  rollback the main `ModelContext` so partial inbound names, deletes, or
  membership rewrites do not remain pending after reconciliation fails.
- `reconcileAllHistoricalData(responses:collections:)` — **legacy, kept for test
  compatibility only**. Delegates to `reconcileScanPage` once, then calls
  `syncCollectionsDown`. New call sites should use the `reconcileScanPage` /
  `syncCollectionsDown` pair.

**When to create**: Ad-hoc, once per `syncHistoricalScansDown` call. Use the
paged API to stream one page at a time rather than accumulating the full cloud
response in memory:

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

The design principle is page-at-a-time streaming: each page is processed and
released before the next is fetched, keeping the in-memory scan accumulation
O(page_size) rather than O(total_library_size) regardless of how many scans the
user has.

---

### `ProfileDatabaseActor` (`Features/Profile/UserProfile/Components/UserStats.swift`)

**Declaration**: `@ModelActor actor ProfileDatabaseActor`

**Responsibilities:**

- `calculateAll()` — **preferred entry point**. Single fetch with an 11-column
  `propertiesToFetch` projection (superset covering stats, heatmap, and awards).
  Returns
  `(speciesCount: Int, streak: Int, heatmap: ProfileHeatmapData, awards: [AwardPayload])`.
  Replaces three sequential actor calls with one.
- `calculateProfileStats()` — fetches with `[\.scientificName, \.timestamp]`
  projection; computes species count and streak. Kept for call sites that only
  need these two values.
- `calculateHeatmapData()` — fetches with `[\.timestamp]` projection; computes
  the 52-week scan heatmap. Kept for call sites that only need heatmap data.
- `calculateAwards()` (extension in `Achievements.swift`) — fetches with the
  full 11-column projection; delegates to
  `AchievementsCalculator.calculate(from:)`. Called from `InferenceEngine` after
  every successful inference (not gated on `isNewDiscovery` — awards can trigger
  on any condition: time-of-day, taxonomy, elevation, etc.)

**When to create**: Ad-hoc for profile tab; long-lived shared instance for
post-inference award refresh:

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

> **Why long-lived for `calculateAwards()`?** On a burst of offline scan
> completions (or rapid successive live scans), `analyze()` calls
> `calculateAwards()` after every result. Allocating a fresh
> `ProfileDatabaseActor` — and with it a fresh `ModelContext` — per scan wastes
> actor setup overhead and generates unnecessary SQLite context churn.
> `resolvedProfileDbActor` maintains one actor per `ModelContainer` identity;
> Swift actor serialization ensures concurrent callers queue safely.

---

### `SpeciesObservationStatsDatabaseActor` (`Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift`, reducer in `Features/Insights/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`)

**Declaration**: `@ModelActor actor SpeciesObservationStatsDatabaseActor`

**Responsibilities:**

- `fetchLocalStats(scientificName:speciesId:now:)` — computes private local
  chart overlays for the Species Observation Charts card without blocking
  `@MainActor`.
- Fetches biological candidate rows with filtered `#Predicate` descriptors: one
  descriptor for `speciesId` / `confirmedSpeciesId` when a dictionary species
  UUID exists, and one descriptor for exact `scientificName` /
  `userIdentificationOverride` fallback.
- Merges candidates by `LocalScanRecord.id`, sorts deterministically by
  timestamp/id, then delegates to `SpeciesObservationStatsReducer` so
  seasonality, history, life-stage filtering, and effective-name matching remain
  identical to the previous behavior.
- Uses a narrow `propertiesToFetch` projection containing only reducer fields,
  avoiding full `LocalScanRecord` materialization for large local libraries.

**When to create**: Ad-hoc per chart load from the current `ModelContainer`. Do
not fetch the user's entire biological library from
`SpeciesObservationStatsViewModel` on the main actor.

```swift
let actor = SpeciesObservationStatsDatabaseActor(modelContainer: modelContext.container)
let localStats = await actor.fetchLocalStats(
    scientificName: normalizedName,
    speciesId: speciesId
)
```

---

### `SearchDatabaseActor` (`Features/Scans/Library/ViewModels/ScansManager.swift`)

**Declaration**: `@ModelActor actor SearchDatabaseActor`

**Responsibilities:**

- `extractSearchablePayloads(from:)` — Generates `SearchableScan` structures for
  indexed library text filtering. It batch-fetches requested string IDs with one
  `FetchDescriptor` and restores caller order through an ID map; it does not
  issue one `model(for:)` fault per record.
- Full library rebuilds do not create this actor for a second fetch.
  `ScansManager` cooperatively extracts `RawScanSnapshot` values from its
  already-resident query, then builds the text snapshot in a detached task.
- Advanced filters are a separate value-type pipeline in
  `ScanLibraryFilterIndex.swift`; they do not dereference SwiftData models from
  `SearchDatabaseActor`.
- `commonGroupName(for:)` — Generates semantic mapping strings from taxonomy
  class limits (e.g. "Aves" -> "bird", "Insecta" -> "insect", "Mammalia" ->
  "mammal") to augment layperson searchability alongside AI reasoning text.

**When to create**: Created ad-hoc by `ScansManager` inside `Task.detached`
blocks whenever library models mutate, or when the typed
`AppEvent.scanSearchIndexInvalidated(scanId:)` invalidation necessitates a
targeted index hot-swap. The event carries only the stable ID; the actor reloads
the authoritative durable scan before rebuilding its payload.

```swift
let dbActor = SearchDatabaseActor(modelContainer: container)
let newPayload = await dbActor.extractSearchablePayloads(from: [persistentId])
```

---

### `FileIOActor` (`Core/Data/Database/FileIOActor.swift`)

**Declaration**: `public actor FileIOActor`

**Responsibilities:**

- `writeTemporaryImages(imageDatas:)` — `async` method that writes `[Data]` to
  `URL.documentsDirectory` and returns `[String]` filenames in the same order as
  the input. Writes are parallelised: each image is dispatched to a
  `Task.detached` worker so all files are written concurrently rather than
  sequentially. On a 3-frame scan this reduces wall-clock write time from
  `3 × write_time` to `max(write_times)`. Filenames are UUID-based and
  guaranteed unique.
- `deleteImages(at:)` — deletes files by filename from `documentsDirectory`
  (skips `http://` paths — those are cloud-owned)
- `deleteFiles(at:)` — generalized deletion entry point for absolute file paths,
  `documentsDirectory` filenames, and mixed cleanup lists captured during
  queue/tombstone cleanup.
- `validPaths(from:)` — filters a list of paths/URLs down to those that actually
  exist on disk or are remote URLs

**When to use**: Always use `FileIOActor.shared` — it is a singleton. Never
write or delete scan media from `BackgroundDatabaseActor`, `@MainActor`, or
ad-hoc `Task.detached` blocks. Image writes still use
`writeTemporaryImages(imageDatas:)`; mixed cleanup for images, video files,
thumbnails, extracted audio, and queue-only inference frames should flow through
`deleteFiles(at:)`.

```swift
let savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
await FileIOActor.shared.deleteImages(at: failedPaths)
```

**Why isolated from SwiftData actors**: Disk I/O and SQLite writes contend for
different OS resources. Keeping them on separate actors prevents either from
starving the other.

### `ArchiveManager` (`Core/Data/Images/ArchiveManager.swift`)

**Declaration**: `@MainActor @Observable final class ArchiveManager`

**Responsibilities:**

- Downloads generated dataset archive ZIP files via an isolated media session.
- Reuses local Documents files for repeat archive opens.
- Exposes disk-space diagnostics without owning SwiftData rescue work.

---

## `@ModelActor` Isolation Explained

`@ModelActor` is a Swift macro that:

1. Creates an actor with its own `ModelContext` bound to the provided
   `ModelContainer`.
2. Ensures all methods on the actor use that isolated `modelContext` — never the
   main thread's context.
3. Makes the actor `Sendable`, so it can be passed across task boundaries
   safely.

```swift
@ModelActor
actor BackgroundDatabaseActor {
    func doWork() {
        // `modelContext` here is isolated to this actor — safe to call fetch/save/insert
        let records = try? modelContext.fetch(FetchDescriptor<LocalScanRecord>())
    }
}
```

**Critical rule**: Never share a `ModelContext` across actors or threads. Always
create a new actor instance with the `ModelContainer` (which IS thread-safe),
not the `ModelContext`.

---

## Ad-hoc vs Singleton: Why Ad-hoc (and When Not)

Most `@ModelActor` actors are created ad-hoc (per operation) rather than stored
as singletons because:

1. **`ModelContext` is not thread-safe** — a singleton actor holding a
   `ModelContext` would need to be the _only_ writer for the duration of its
   operation. Ad-hoc creation gives each operation its own isolated context.
2. **Backpressure is explicit** — if `syncHistoricalScansDown` creates an actor
   and `await`s it, the caller naturally blocks until reconciliation is
   complete. A singleton with a queue would make this implicit and harder to
   reason about.
3. **No state leakage** — each operation starts with a fresh context. There is
   no risk of a previous operation's unflushed changes affecting the next one.

**Exception — long-lived queue actor**: `OfflineQueueManager` stores a single
`BackgroundDatabaseActor` instance in `_queueDbActor` (accessed via
`resolvedQueueDbActor(container:)`). This is intentional:

- **Serialization**: Upload claims/reconciliation and inference transitions
  (`markScansAsUploading`, `markScanAsStaged`, `tryClaimForInference`,
  `transitionScanToStaged`, and both orphan reconcilers) execute on the _same_
  actor executor. Snapshot cutoffs then remain meaningful even if replacement
  work reaches the actor before an older reconciliation call.
- **Performance**: Offline upload bursts can complete multiple scans in rapid
  succession. Reusing one actor avoids repeated `ModelContainer → ModelContext`
  setup cost per completion.
- The shared actor is still safe for concurrent callers — Swift actors serialize
  all calls through their executor automatically.

`FileIOActor` is also a singleton because it has no `ModelContext` and manages a
single shared resource (the Documents directory).

## 2026-07 Collection Projection Rule

Collection upload reads must begin with the changed relationship owners.
`BackgroundDatabaseActor.collectionSyncPayloads()` fetches the bounded
non-Favorites `ScanCollection` set and prefetches each row's inverse `scans`
relationship. Do not restore the former 200-row `LocalScanRecord.collections`
OFFSET walk: it scanned unrelated records, repeated progressively more SQLite
work, and rebuilt the same memberships on every collection job. The Edge
endpoint reads current `collection_scans` membership with a stable
`(collection_id, scan_id)` keyset cursor and writes only its delta; range/OFFSET
pagination is not part of this upload path. Historical download reconciliation
remains independently page-bounded because it is ingesting remote scan history
rather than projecting an existing local relationship.

## 2026-06 Smart Collection Boundary

Smart default collections are local, auto-managed UI projections.
`SmartCollectionSuggester` reads local `LocalScanRecord` rows on the main UI
side and emits private collections without creating `ScanCollection` objects or
cloud payloads. Hidden smart collection ids are stored only in
`UserDefaultsKeys.hiddenSmartCollectionIDs`. The Edge sync contract remains
unchanged: only persisted `ScanCollection` records are serialized to
`/sync-collections`, and smart collections do not enter that payload unless a
future explicit conversion feature creates normal collections.

---

## Decision Guide

| Task                                                     | Actor to use                                                                                                                                                   |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Save a live scan result                                  | `BackgroundDatabaseActor` (ad-hoc) via `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:persistenceFence:)` |
| Save a text-only, audio-only, or mixed non-visual result | `BackgroundDatabaseActor` (ad-hoc) via `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:mediaTimeline:persistenceFence:)`                |
| Transition scan state for upload pipeline                | `BackgroundDatabaseActor` via `resolvedQueueDbActor` (long-lived)                                                                                              |
| Claim a scan for inference (`tryClaimForInference`)      | `BackgroundDatabaseActor` via `resolvedQueueDbActor` (long-lived)                                                                                              |
| Reset scan to `.staged` on transient failure             | `BackgroundDatabaseActor` via `resolvedQueueDbActor` (long-lived)                                                                                              |
| Process an offline scan after upload                     | Fresh `BackgroundDatabaseActor` for final record persistence; shared `resolvedQueueDbActor` for queue transitions                                              |
| Startup/ongoing orphan reconciliation                    | `BackgroundDatabaseActor` via `resolvedQueueDbActor`, with a pre-enumeration `observedThrough` cutoff                                                          |
| Sync historical scans from cloud                         | `HistoricalDatabaseActor` (ad-hoc)                                                                                                                             |
| Calculate all profile data (stats + heatmap + awards)    | `ProfileDatabaseActor.calculateAll()` (ad-hoc)                                                                                                                 |
| Calculate achievement awards only (post-inference)       | `ProfileDatabaseActor.calculateAwards()` via `resolvedProfileDbActor` (long-lived)                                                                             |
| Calculate profile stats (species count, streak)          | `ProfileDatabaseActor.calculateProfileStats()` (ad-hoc)                                                                                                        |
| Write scan image files to disk                           | `FileIOActor.shared`                                                                                                                                           |
| Delete scan media files from disk                        | `FileIOActor.shared`                                                                                                                                           |
| Validate scan media paths                                | `FileIOActor.shared`                                                                                                                                           |
| Push collections to Edge                                 | `BackgroundDatabaseActor` (ad-hoc)                                                                                                                             |
| Persist enrichment data after enrich-scan returns        | `BackgroundDatabaseActor` (ad-hoc)                                                                                                                             |

## 2026-04 Hardening Updates

- `BackgroundDatabaseActor.buildScanRecord` now preserves the original capture
  timestamp for offline inserts. Offline replay no longer rewrites chronology to
  "time of sync", so library ordering, streaks, heatmaps, and analytics stay
  faithful to when the user actually captured the scan.
- The non-biological bulk-delete actor path now inserts cloud-deletion
  tombstones and deletes SwiftData rows first, then saves transactionally. Local
  files are purged only after the save succeeds.
- Save failures inside bulk deletion now rollback the actor `ModelContext` and
  surface the error to the caller instead of being swallowed with `try?`.
