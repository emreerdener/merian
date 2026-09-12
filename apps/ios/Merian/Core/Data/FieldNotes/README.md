# Core Field Notes

`FieldNotesRepository.swift` is the shared `@MainActor` persistence boundary for
private field-note reads, writes, clears, and public-to-local repair.

Reads resolve an active `LocalScanRecord`, then an `OfflineQueuedScan`, then the
legacy `FieldNotesStore` bridge. Successful SwiftData reads mirror the bridge; a
bridge-only value is promoted into SwiftData when a matching row exists. Writes
save explicitly and mirror the bridge only after a successful SwiftData commit.
A failed fetch or save is logged with private interpolation and fails closed; it
must not let stale defaults override an unreadable durable store.

Insights adapts this repository through its Field Notes Services layer. Explore
uses it to reconcile publication edits with the private local note. Callers do
not mutate both SwiftData and `FieldNotesStore` independently.

Behavior tests live in
`MerianTests/Core/Data/FieldNotes/FieldNotesRepositoryTests.swift`. Core Data
and Utilities-wide architecture suites enforce throwing fetches, focused
ownership, and the retired Utilities path.
