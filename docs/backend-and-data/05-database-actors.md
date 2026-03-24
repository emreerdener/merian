# Database Actors

Merian uses multiple Swift `@ModelActor` and `actor` types to safely perform SwiftData and disk I/O work off the main thread. This document explains which actor to use when, how `@ModelActor` isolation works, and why each actor is created ad-hoc rather than reused as a singleton.

---

## Why Actors?

The main thread owns the SwiftUI view hierarchy and the primary `ModelContext`. Performing bulk SwiftData fetches, large ingests, or disk I/O on the main thread causes visible UI stuttering and risks JetSam termination. Actors provide compile-time-enforced isolation: work inside an actor runs on that actor's executor, never blocking the main thread.

---

## Actor Inventory

### `BackgroundDatabaseActor` (`Core/Data/Database/BackgroundDatabaseActor.swift`)

**Declaration**: `@ModelActor actor BackgroundDatabaseActor`

**Responsibilities:**
- `fetchPendingScans(limit:)` — fetches `OfflineQueuedScan` records for the upload pipeline
- `processAndCleanupOfflineScan(...)` — decodes an edge inference result, inserts a `LocalScanRecord`, deletes the `OfflineQueuedScan`, purges local images on failure
- `saveLiveScanRecord(mappedData:localImagePaths:)` — persists a real-time scan result after live inference
- `updateScanWithWikipedia(...)` — retroactively hydrates a scan with Wikipedia data
- `pushCollectionsToEdge()` — serializes local `ScanCollection` records and calls the `sync-collections` Edge function

**When to create**: Always create ad-hoc per operation:
```swift
let container = modelContext.container
let dbActor = BackgroundDatabaseActor(modelContainer: container)
await dbActor.saveLiveScanRecord(mappedData: data, localImagePaths: paths)
```

---

### `HistoricalDatabaseActor` (`Core/Data/Database/ScanRepository.swift`)

**Declaration**: `@ModelActor actor HistoricalDatabaseActor`

**Responsibilities:**
- `reconcileAllHistoricalData(responses:collections:)` — single entry point for the full historical sync: updates existing records, ingests missing ones, reconciles collections
- `updateExistingScans` (private) — predicate-scoped fetch with `propertiesToFetch` column projection; saves only if fields changed
- `ingestScans` (private) — inserts new `LocalScanRecord` rows; checkpoint-saves every `MerianConfig.ingestCheckpointInterval` (50) records
- `syncCollections` (private) — upserts `ScanCollection` records; fetches only the local scans referenced by incoming collections

**When to create**: Ad-hoc, once per `syncHistoricalScansDown` call:
```swift
let dbActor = HistoricalDatabaseActor(modelContainer: container)
let newCount = await dbActor.reconcileAllHistoricalData(responses: allScans, collections: allCollections)
```

The design principle is one actor invocation for all reconciliation work, avoiding multiple `await` actor-boundary crossings for shared state.

---

### `ProfileDatabaseActor` (`Features/Profile/Components/Profile/UserStats.swift`)

**Declaration**: `@ModelActor actor ProfileDatabaseActor`

**Responsibilities:**
- `calculateProfileStats()` — fetches all `LocalScanRecord` rows with a column-projected descriptor (scientific name and timestamp only) to compute species count and scan streak
- `calculateAwards()` (extension in `Achievements.swift`) — fetches all `LocalScanRecord` rows and delegates to `AchievementsCalculator.calculate(from:)`, returning an `[AwardPayload]` array
- Called from `InferenceEngine` after every successful inference (not gated on `isNewDiscovery` — awards can trigger on any condition: time-of-day, taxonomy, elevation, etc.)

**When to create**: Ad-hoc, after each successful inference:
```swift
if let container = modelContext?.container {
    let profileActor = ProfileDatabaseActor(modelContainer: container)
    let updatedAwards = await profileActor.calculateAwards()
    await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
}
```

---

### `FileIOActor` (`Core/Data/Database/FileIOActor.swift`)

**Declaration**: `public actor FileIOActor`

**Responsibilities:**
- `writeTemporaryImages(imageDatas:)` — writes `[Data]` to `URL.documentsDirectory`, returns `[String]` filenames
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

## Ad-hoc vs Singleton: Why Ad-hoc?

All `@ModelActor` actors are created ad-hoc (per operation) rather than stored as singletons because:

1. **`ModelContext` is not thread-safe** — a singleton actor holding a `ModelContext` would need to be the *only* writer for the duration of its operation. Ad-hoc creation gives each operation its own isolated context.
2. **Backpressure is explicit** — if `syncHistoricalScansDown` creates an actor and `await`s it, the caller naturally blocks until reconciliation is complete. A singleton with a queue would make this implicit and harder to reason about.
3. **No state leakage** — each operation starts with a fresh context. There is no risk of a previous operation's unflushed changes affecting the next one.

`FileIOActor` is the only singleton because it has no `ModelContext` and manages a single shared resource (the Documents directory).

---

## Decision Guide

| Task | Actor to use |
|---|---|
| Save a live scan result | `BackgroundDatabaseActor` (ad-hoc) |
| Process an offline scan after upload | `BackgroundDatabaseActor` (ad-hoc) |
| Sync historical scans from cloud | `HistoricalDatabaseActor` (ad-hoc) |
| Calculate achievement awards | `ProfileDatabaseActor` (ad-hoc) |
| Calculate profile stats (species count, streak) | `ProfileDatabaseActor` (ad-hoc) |
| Write image files to disk | `FileIOActor.shared` |
| Delete image files from disk | `FileIOActor.shared` |
| Validate image paths | `FileIOActor.shared` |
| Push collections to Edge | `BackgroundDatabaseActor` (ad-hoc) |
