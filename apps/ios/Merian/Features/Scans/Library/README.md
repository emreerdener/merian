# Scans Library

The `Library` directory handles the primary grid view of all personal biological
captures.

## Ownership boundary

- `Models/ScanLibraryFilters.swift` owns sort/filter values and active-filter
  counting. `SearchableScan.swift` owns the text/category posting index.
  `ScanLibraryFilterIndex.swift` owns the immutable advanced-filter projection,
  normalized query, cached option dimensions, and detached matching engine.
  `ScanLibrarySearchModels.swift` owns the Sendable search/sort projections and
  pure sort policy. `ScansFilterPresentation.swift` owns user-facing title
  normalization, grouped selection summaries, and taxonomy section visibility;
  the filter component keeps its expansion-group identity private.
- `Services/ScanLibrarySearchActors.swift` owns the ad-hoc SwiftData delta
  reader and actor-isolated text filter. `ScansLibraryDependencies.swift` is the
  only Library layer that resolves live app events, media export, Explore
  publication, durable local share state, error formatting, or haptics.
- `ViewModels/ScansManager.swift` retains the existing UI-facing interface,
  selection state, filter input, action feedback, and event subscription.
  `ScansLibrarySearchCoordinator.swift` contains the private generation-fenced
  tasks, model lookup maps, posting/filter snapshots, and sorted-ID caches.
- `Views/LibraryView.swift` owns rendering, filter-sheet occupancy, queued-row
  hydration, and view-local feedback timing.
  `Components/Filters/ScansFilterSheet.swift` owns advanced-filter rendering and
  view-local expansion state. Library views and components perform no endpoint
  or singleton lookup.

Production Library files remain below the pass's 600-line review guard. The
existing `ScansManager` initializer signature and all production Shell/Library
call sites remain unchanged.

## Purpose

This is the core browsing experience for a user's identified biological scans.
It includes the semantic search engine that can resolve plain-English queries
against taxonomy, as well as handling the presentation of pending queued
captures that haven't yet finished inference or upload.

## Batch media export conflict domain

Saving selected media retains a bounded snapshot of at most 20 completed scans
and shows a compact bottom progress capsule with hit testing disabled. The
library remains scrollable and unrelated navigation remains available; there is
no full-screen progress blocker. Until export completes, individual and bulk
selection changes, Cancel/Select All, share, download, delete, queued-scan
deletion, and Explore-publication mutations are fenced. This prevents the export
snapshot and the visible selection/record set from diverging while still
allowing nonmutating use of the sheet.

## Explore media incident contract

- `ScansShellViewModel` loads the authenticated owner's active Explore media
  incidents and supplies prepared incident/filter state to `LibraryView`.
  Profile `Review scans` is only a route intent that initially enables the
  `Unavailable media` advanced filter; it is not the source of the alert count.
- The unavailable row is derived from the live, deduplicated incident scan IDs.
  The server queue contains only active published posts, so private scans do not
  contribute. The row disappears when no incidents remain.
- Dismissing the unavailable row hides only the Library overview presentation
  for that account and incident set. `Unavailable media` remains available in
  the Explore posts group in the filter sheet, and a new incident set surfaces
  the overview row again.
- `Refresh` only reloads server-authoritative health status. It must not be
  labeled as a recovery retry unless an asset-typed owner recovery API actually
  uploads or repairs the missing image, playback video, or standalone audio.
- When refresh proves the incident queue is empty, the unavailable-media filter
  is removed so a resolved Profile route cannot strand the Library in an empty
  filtered state.

## Queued scan routing contract

- Queued value snapshots render above completed scans and remain outside
  selection mode.
- `LibraryView.openQueuedScan` first checks for a completed local record,
  resolving a queue-completion race between grid render and tap.
- Otherwise the library reads the queue row through a fresh `ModelContext`,
  copies it into `QueuedScanContext`, and emits `onQueuedInsight`. If the row
  disappeared, it builds a safe fallback context from `QueuedScanSnapshot`.
- The library does not present an Insight sheet or retain a live queued
  SwiftData model. `ScansSheetView` owns the pushed navigation destination, and
  `ScansShellDataStore` owns the queue-to-value projection supplied to Library.
- Completion handoff must preserve playable queued media and expose the
  completed observation's Field Chat and Share toolbar controls without
  replacing the pushed destination.
- Media kinds and approximate queued bytes remain copied internal metadata. The
  scanning UI does not expose a media/file-size summary.
- Needs-attention rows remain visible for explicit retry or deletion, but they
  do not drive the library's periodic queue refresh or automatic upload/replay
  kicks. They are also excluded from `unsyncedItemsCount`, which represents
  automatically runnable work rather than every visible queue row. That count
  uses a fresh SwiftData read context so background-actor transitions cannot be
  hidden by a cached main-context fault. A successful explicit retry sends
  `.scanLibraryChanged`, changes the state-bearing refresh identity, and
  re-enables monitoring. The serialized queue actor rechecks the same attention
  fence and persisted retry deadline while claiming upload or inference work and
  excludes attention rows from orphan reset, so a stale Library/worker snapshot
  cannot bypass the pause. Pending selection pages through older future-dated
  retries, deferred live uploads, and network-blocked videos, preventing them
  from hiding newer runnable scans while retaining the explicit user-forced
  video override. Global server-status recovery excludes attention-paused
  inference rows.
- Automatic Library recovery additionally requires an online, unconstrained
  path. Pending playback video requires an unmetered large-upload path unless
  the user explicitly requested that scan; staged/uploaded video can still run
  its lightweight status or inference work on expensive unconstrained paths. The
  refresh task identity observes online, constrained, expensive, and
  explicit-override policy. Offline, Low Data Mode, and cellular-blocked rows
  therefore remain visible without keeping the 1.5-second poll or queue-kick
  logs alive, while an eligible policy transition restarts recovery even when
  reachability stayed satisfied.
- `externalImport` is a persisted legacy non-runnable state. It may remain
  visible when it needs user cleanup, but neither queue surface offers Retry and
  the queue mutation API rejects it because scan-ingestion workers intentionally
  cannot advance it.

## Performance and concurrency contract

- SwiftData `LocalScanRecord` instances never cross actor boundaries.
  `ScansLibrarySearchCoordinator` extracts `RawScanSnapshot` and
  `RawScanFilterSnapshot` value types on `@MainActor` in 128-record batches,
  yielding between batches. Full text-payload and posting-index construction is
  cancellation-aware and runs in one detached utility task.
- Advanced-filter values are normalized once per library generation into
  `ScanLibraryFilterIndexSnapshot`. Opening the filter sheet reads cached
  dimensions; it must not rescan `allScans`.
- Each filter change creates one `ScanLibraryFilterQuery`, so selected taxonomy,
  weather, tag, and status values are normalized once rather than once per
  record. Matching and sorting run together in a detached task over immutable
  values.
- Search, filter, and sorted-ID commits compare the coordinator's captured
  generation before mutating visible state. A cancelled worker from an older
  library generation must never populate a newer result.
- Targeted reindexes coalesce pending scan IDs. A replacement task carries IDs
  from any superseded task, preventing a rapid A→B update from dropping A from
  the search index.
- `AppEvent.scanSearchIndexInvalidated` and `exploreShareStateChanged` both
  refresh the cached filter projection and rerun the current query so custom-tag
  and Explore-share filters remain live.

## Focused tests

Tests mirror this owner under `MerianTests/Features/Scans/Library/`:

- `ScansManagerTests` locks text/category indexes, full and incremental builds,
  generation fencing, targeted-reindex coalescing, advanced filters, sorting,
  and selection limits.
- `ScansLibraryActionsTests` injects every export/publication/feedback action
  and verifies batch-save success and failure, selection teardown, missing and
  ineligible publication rejection, ordered local share-state/event/feedback
  commit only after endpoint success, and failure-state preservation.
- `CompositeLibraryTests` locks queued/completed grid identity and selection
  isolation.
- `ScansFilterPresentationTests` locks title normalization, selected/grouped
  summaries, and taxonomy option visibility independently of the rendered sheet.

Shell queue, incident, navigation, data-store, and thumbnail-pipeline tests live
beside their owner under `MerianTests/Features/Scans/Shell/`; see the
[Shell README](../Shell/README.md) for that matrix.

Run the focused matrix after changing Library models, Services, view models, or
views:

```bash
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/ScansManagerTests \
  -only-testing:merianTests/ScansLibraryActionsTests \
  -only-testing:merianTests/CompositeLibraryTests \
  -only-testing:merianTests/ScansFilterPresentationTests \
  -only-testing:merianTests/ScansShellViewModelTests \
  -only-testing:merianTests/ScansShellDataStoreTests \
  -only-testing:merianTests/ScansThumbnailPipelineTests test
```

Manual parity covers empty/loading/search/filter/sort states; queued and
completed rows; selection limits; batch share/save/delete; Explore publication;
unavailable-media refresh/dismissal; VoiceOver; large Dynamic Type; and
light/dark appearance.
