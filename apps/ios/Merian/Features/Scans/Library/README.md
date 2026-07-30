# Scans Library

The `Library` directory handles the primary grid view of all personal biological captures.

## Structure

- **Views**: Contains the main scan grid, search interfaces, and filtering menus.
- **ViewModels**: Handles semantic search, filtering, sorting (newest, oldest,
  alphabetical), and category filtering (Plants, Fungi, Insects, Birds,
  Mammals, Reptiles, Other).
- **Models**: Defines view-specific representations of scans and queued
  captures. `SearchableScan.swift` owns the text/category posting index.
  `ScanLibraryFilterIndex.swift` owns the immutable advanced-filter projection,
  normalized query, cached option dimensions, and detached matching engine.

## Purpose
This is the core browsing experience for a user's identified biological scans. It includes the semantic search engine that can resolve plain-English queries against taxonomy, as well as handling the presentation of pending queued captures that haven't yet finished inference or upload.

## Queued scan routing contract

- Queued value snapshots render above completed scans and remain outside
  selection mode.
- `LibraryView.openQueuedScan` first checks for a completed local record,
  resolving a queue-completion race between grid render and tap.
- Otherwise the library reads the queue row through a fresh `ModelContext`,
  copies it into `QueuedScanContext`, and emits `onQueuedInsight`. If the row
  disappeared, it builds a safe fallback context from `QueuedScanSnapshot`.
- The library does not present an Insight sheet or retain a live queued
  SwiftData model. `ScansSheetView` owns the pushed navigation destination.
- Completion handoff must preserve playable queued media and expose the
  completed observation's Field Chat and Share toolbar controls without
  replacing the pushed destination.
- Media kinds and approximate queued bytes remain copied internal metadata.
  The scanning UI does not expose a media/file-size summary.
- Needs-attention rows remain visible for explicit retry or deletion, but they
  do not drive the library's periodic queue refresh or automatic upload/replay
  kicks. They are also excluded from `unsyncedItemsCount`, which represents
  automatically runnable work rather than every visible queue row. That count
  uses a fresh SwiftData read context so background-actor transitions cannot
  be hidden by a cached main-context fault. A successful explicit retry posts
  `libraryDidUpdate`, changes the state-bearing refresh identity, and
  re-enables monitoring. The serialized queue actor rechecks the same
  attention fence and persisted retry deadline while claiming upload or
  inference work and excludes attention rows from orphan reset, so a stale
  Library/worker snapshot cannot bypass the pause. Pending selection pages
  through older future-dated retries, deferred live uploads, and
  network-blocked videos, preventing them from hiding newer runnable scans
  while retaining the explicit user-forced video override. Global
  server-status recovery excludes attention-paused inference rows.
- Automatic Library recovery additionally requires an online, unconstrained
  path. Pending playback video requires an unmetered large-upload path unless
  the user explicitly requested that scan; staged/uploaded video can still run
  its lightweight status or inference work on expensive unconstrained paths.
  The refresh task identity observes online, constrained, expensive, and
  explicit-override policy. Offline, Low Data Mode, and cellular-blocked rows
  therefore remain visible without keeping the 1.5-second poll or queue-kick
  logs alive, while an eligible policy transition restarts recovery even when
  reachability stayed satisfied.
- `externalImport` is a persisted legacy non-runnable state. It may remain
  visible when it needs user cleanup, but neither queue surface offers Retry
  and the queue mutation API rejects it because scan-ingestion workers
  intentionally cannot advance it.

## Performance and concurrency contract

- SwiftData `LocalScanRecord` instances never cross actor boundaries.
  `ScansManager` extracts `RawScanSnapshot` and `RawScanFilterSnapshot` value
  types on `@MainActor` in 128-record batches, yielding between batches.
- Advanced-filter values are normalized once per library generation into
  `ScanLibraryFilterIndexSnapshot`. Opening the filter sheet reads cached
  dimensions; it must not rescan `allScans`.
- Each filter change creates one `ScanLibraryFilterQuery`, so selected taxonomy,
  weather, tag, and status values are normalized once rather than once per
  record. Matching and sorting run together in a detached task over immutable
  values.
- Search, filter, and sorted-ID commits compare `searchCacheGeneration` before
  mutating visible state. A cancelled worker from an older library generation
  must never populate a newer result.
- Targeted reindexes coalesce pending scan IDs. A replacement task carries IDs
  from any superseded task, preventing a rapid A→B update from dropping A from
  the search index.
- `ScanRequiresSearchIndexUpdate` and `exploreShareStateChanged` both refresh
  the cached filter projection and rerun the current query so custom-tag and
  Explore-share filters remain live.
