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
