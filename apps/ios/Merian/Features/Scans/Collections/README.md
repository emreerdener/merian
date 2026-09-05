# Scans Collections

`Features/Scans/Collections` owns the private collection catalog, persisted
collection detail and membership editing, local smart collections, and the entry
card for the owner-only Scan map. It does not own SwiftData model declarations,
the Scans navigation host, map rendering, or collection-sync wire contracts.

The canonical product behavior is
[Collections (Top-Level Photo Albums)](../../../../../../docs/features-and-hardware/07-feature-modules-and-ui.md#collections-top-level-photo-albums).

## Ownership

- `Models/` contains immutable membership, catalog, cover, and smart-collection
  presentation values. Persisted `ScanCollection` and `LocalScanRecord` models
  remain under `Models/ActiveSchema/`, with versioned snapshots under
  `Models/Schema/`.
- `Services/` owns collection validation and save-first mutations, smart
  suggestion policy, local hidden-smart preferences, and the narrow live
  dependency adapters for events, share state, sync enqueueing, and feedback.
- `ViewModels/` derives catalog, detail, selection, and smart-detail state from
  values supplied by the Scans root. These types are `@MainActor @Observable`.
- `Views/` retains navigation, alert, search-focus, timer, and lifecycle timing.
  Views do not fetch SwiftData rows or resolve app-wide singletons.
- `Components/Alerts` owns collection create, rename, and delete presentation
  consumed by Collections, Scans Shell, and Insight. `Components/Cards` and
  `Components/Catalog` own Collections-local presentation.

`ScansSheetView` owns the completed-library `@Query` and passes the same
timestamp-ordered record set through `ScansSheetTabContent` to
`CollectionsView`. Collections derives membership, non-biological counts, smart
suggestions, cover candidates, and refresh identity from that set. This keeps
one authoritative observation source and avoids four duplicate queries over the
same library. Catalog and smart-detail tasks use a typed value projection of
every persisted field consumed by smart matching, ordering, and cover policy;
they do not depend on SwiftData object-array equality or lossy string
signatures. Detail and selection tasks key refreshes to the target collection's
ordered member IDs. Together these identities rederive state after in-place
model changes even if a loss-tolerant invalidation event was missed.

## Mutation Contract

`CollectionMutationService` is the only Collections owner of create, rename,
delete, remove, and toggle persistence orchestration. Its live dependency value
is small and closure-based; tests replace every side effect without introducing
a singleton or broad protocol.

- Names are trimmed, `Favorites` is reserved, and duplicates are rejected
  against non-deleted persisted collections. The protected Favorites folder
  cannot be renamed or deleted through the service boundary.
- A local save must succeed before collection sync or library invalidation is
  published.
- Failed saves first restore the captured in-memory model values, then roll back
  the context and suppress downstream event and sync effects. The explicit
  restoration keeps held SwiftData references consistent even when relationship
  rollback does not immediately rematerialize the previous value.
- Membership edits mutate `LocalScanRecord.collections`, not
  `ScanCollection.scans`, so the many-side relationship is not faulted into
  memory.
- Successful membership edits publish `scanLibraryChanged` before enqueueing
  collection sync. Create and rename enqueue the same durable collection-sync
  job after their successful save. Collection deletion uses that same save-first
  boundary and only purges locally after the matching cloud acknowledgement.

The feature does not call a network endpoint directly. The injected live sync
closure delegates to `OfflineQueueManager`, whose durable job and
`/sync-collections` behavior are documented in the
[offline sync pipeline](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md#the-collections-pipeline).

## SwiftData Tombstone Contract (V51)

The active V51 `ScanCollection` model exposes the application-owned
`isPendingDeletion` property and maps it to the unchanged `isDeleted` column
with `@Attribute(originalName:)`. This avoids SwiftData's reserved
`PersistentModel.isDeleted` lifecycle state while preserving the existing
`is_deleted` wire field.

The released V50 shape is frozen in `Models/Schema/SchemaV50Snapshots.swift`;
its historical `isDeleted` Swift property and goal-hint companion form the
immutable disk fixture. `MerianActiveSchemaV50` is the source bridge for the
custom V50→V51 preference migration; the collection shape itself remains
unchanged in V51. Released V50 stores therefore use the source-isolated V50→V51
plan. V49 stores advance through lightweight V49→V50 and custom V50→V51 hops;
V43...V48 retain source-isolated repair plans ending at V51.

The deletion marker is covered across save/refetch, disk migration, relationship
retention, outbound `is_deleted` projection, inbound tombstone shielding, and
acknowledgement-only purge. The complete `MigrationPlanTests` suite and
collection mutation suites must stay green. See the
[SwiftData schema contract](../../../../../../docs/backend-and-data/04-database-schema.md#scancollection-user-albums)
and
[SwiftData gotchas](../../../../../../docs/development-guides/11-swiftdata-and-api-gotchas.md#29-persistentmodelisdeleted-is-framework-state-not-app-storage).

## Smart Collections and Map Entry

Smart collections are local projections. They never create `ScanCollection` rows
or enter the cloud payload. `SmartCollectionSuggester` receives the public share
lookup as an injected value, and hidden smart IDs remain device-local
preferences. Authenticated historical scan sync reconciles each remote scan's
active owner-readable Explore post relationship into that lookup behind a
per-request revision fence. A later local publication mutation, deletion,
account-scoped purge, or newer response wins over stale history. When the cache
changes, the repository publishes one `exploreShareStateReconciled` invalidation
for the batch; catalog and open smart-detail views rederive membership even when
a subsequent history page or collection request fails. Eligible local biological
scans therefore recover restored or cross-device publication intent without
having been shared or opened on the current installation. Moderated or
quarantined posts can remain members while their owner-preserved active intent
exists, so this local collection is not an exact copy of the currently visible
Profile grid.

The Scan map card is also not a synchronized collection. Collections consumes
the Scans-owned coordinate snapshot and appends
`ScansNavigationRoute.privateScanMap`; `ScansSheetView` constructs the
destination in the existing navigation stack. Collections does not request
location, render a live map, or decode and cluster the library. See the
[Private Scan Map contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md)
for eligibility, privacy, rendering, reset, and release verification.

## Verification

Focused deterministic coverage lives beside the feature in
`MerianTests/Features/Scans/Collections/`:

- `CollectionMutationServiceTests` locks validation, explicit restoration plus
  rollback for every mutation kind, related-record creation, and
  save/event/sync/feedback ordering, including durable tombstone persistence and
  failed-save restoration.
- `MigrationPlanTests` locks the frozen V50 bridge and active V51 owner, the
  collection rename mapping, disk-backed tombstone, relationship, goal-hint, and
  preference-discard behavior, the linear full historical plan, and
  source-isolated startup plan selection.
- `CollectionsViewModelTests` locks catalog filtering, counts, membership,
  empty-state independence, smart/featured projections, injected share state,
  membership-sensitive refresh identity, and same-length review-payload
  invalidation for catalog and smart detail.
- `SmartCollectionTests` retains the suggestion and presentation-policy matrix.

After `make xcodegen` and build-for-testing, run those focused suites and then
the complete `merianTests` target on an available simulator. Manually regress
search, map/featured/custom card ordering, Favorites and Non-biological rows,
create/rename/delete, detail removal and multi-selection, smart hide/restore,
Back navigation, VoiceOver, and large Dynamic Type. Every production file in
this feature remains below the 600-line review guard. Do not report the
Collections matrix or release gate as green while the durable-delete, V50→V51
migration, or complete migration-plan suite fails.
