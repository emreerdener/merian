# Scans Non-Biological

`NonBiological/` owns the dedicated review and correction surface for captures
identified as inanimate or otherwise non-biological. It does not own another
SwiftData query: the Scans Shell passes its timestamp-sorted `rawRecords` into
the typed `ScansNavigationRoute.nonBiologicalScans` destination, and the feature
filters that shared record set for presentation.

## Ownership

- `Models/` owns stable visible copy, the typed correction route, refresh
  identity, and immutable `Sendable` erasure snapshots.
- `Services/` owns the narrow live adapters for retention purge, actor-isolated
  database deletion, file cleanup, library invalidation, deletion sync, route
  requests, and haptics.
- `ViewModels/` owns non-biological filtering, purge and bulk-delete lifecycle,
  overlap prevention, routing effects, and typed toast state.
- `Views/` retains navigation, alerts, selected scan IDs, SwiftUI task timing,
  and the shared single-scan deletion presentation.
- `Components/` owns the retention banner and non-blocking progress badge.

Views and components perform no persistence reads, file operations, background
actor construction, app-container lookup, or networking. The shared
`scanDeletionDialog` remains the single-scan mutation owner; Core repository,
database-actor, file-actor, and offline-queue tests remain with those
lower-level owners.

## Routing and lifecycle

The Collections card appends `ScansNavigationRoute.nonBiologicalScans` to the
Shell-owned path. A cross-feature `AppRoute.nonBiologicalScans` seeds the same
typed route when the Scans root is presented. Both paths therefore use one
destination and one Back behavior.

Opening the destination asks the injected service to purge records older than
`MerianConfig.nonBiologicalRetentionDays`. Correction does not mutate the
original record; it requests
`AppRoute.refinement(..., entryPoint: .nonBiologicalCorrection)` so the existing
replacement pipeline remains authoritative.

## Bulk deletion

Delete All copies record IDs and ordered media paths into lightweight erasure
snapshots on the main actor. The service passes those values to
`BackgroundDatabaseActor`, which re-fetches each ID and skips any row that was
reclassified as biological after the snapshot was taken. It then sends only the
committed deletion paths to `FileIOActor`. Only after database and file work
finish does the view model publish `scanLibraryChanged`, success feedback, a
typed toast, and pending-deletion sync. Failure restores interaction and
suppresses commit-only effects.

The compact progress badge has hit testing disabled. The affected grid and
destructive toolbar action are disabled during the operation, while unrelated
navigation chrome remains available.

## Verification

`NonBiologicalScansViewModelTests` locks copy and route parity, Shell-record
filtering, refresh identity, mixed-media erasure mapping, ordered completion
effects, failure restoration, overlap rejection, retention purge, correction
routing, and single-delete feedback.
`BackgroundDatabaseActorTests.testBulkDeleteNonBiologicalScansRevalidatesEligibilityBeforeCommit`
locks the commit-time fence that preserves a scan reclassified as biological,
its local paths, and the absence of a cloud-deletion task. The UI regression
`merianUITests.testNonBiologicalCollectionBackReturnsToCollectionsTab` seeds the
typed destination, uses the native Back action, verifies that Collections stays
selected, and confirms that the Non-biological card is visible and hittable.

These automated cases do not replace manual checks for both entry paths,
retention purge, single and bulk deletion, correction, progress interactivity,
VoiceOver, large Dynamic Type, and light/dark appearance. Run commands and the
full ownership matrix live in the canonical
[testing strategy](../../../../../../docs/development-guides/08-testing-strategy.md#scans-non-biological)
and product behavior remains in the
[feature contract](../../../../../../docs/features-and-hardware/07-feature-modules-and-ui.md#scans-library-ui).
