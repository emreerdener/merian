# Core Field Notes

`FieldNotesRepository.swift` is the shared `@MainActor` persistence boundary for
private field-note reads, writes, clears, and public-to-local repair.

Reads resolve an active `LocalScanRecord`, then an `OfflineQueuedScan`, then the
legacy `FieldNotesStore` bridge. A same-owner completed restored detail baseline
with nil notes proves an authoritative clear and suppresses the bridge. A
pending or completed ordinary tag-only operation does not supply that proof.
Nonempty durable notes mirror the bridge; a bridge-only value is promoted when a
matching row and mutation admission permit it.

Completed-scan edits stage an immutable owner-bound `LibraryDetailsSyncService`
operation in the same save as the model change. Queued-scan notes remain with
that capture's durable work. Writes mirror the bridge and request detail drain
only after a successful SwiftData commit. Missing-row bridge values remain
unacknowledged and block identity replacement. A failed fetch or save is logged
with private interpolation and fails closed; it must not let stale defaults
override an unreadable durable store.

Insights adapts this repository through its Field Notes Services layer. Explore
uses it to reconcile publication edits with the private local note. Callers do
not mutate both SwiftData and `FieldNotesStore` independently.

Behavior tests live in
`MerianTests/Core/Data/FieldNotes/FieldNotesRepositoryTests.swift`. Core Data
and Utilities-wide architecture suites enforce throwing fetches, focused
ownership, and the retired Utilities path.

The
[guest library transition contract](../../../../../../docs/backend-and-data/21-guest-library-transitions.md)
owns remote acknowledgment, legacy-note preparation before restoration, and
same-account recovery. `FieldNotesRepositoryTests` covers remote clears and
pending/completed tag-only bridge preservation; `LibraryMutationInventoryTests`
covers durable import and exact acknowledgment before cleanup.
