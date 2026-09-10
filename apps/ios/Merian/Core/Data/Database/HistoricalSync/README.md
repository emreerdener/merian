# Historical Sync

This directory owns authenticated cloud-history hydration for the local scan
library. The layers are intentionally narrow:

- `Models/HistoricalSyncModels.swift` contains request values, typed outcomes,
  and the existing PostgREST DTOs. Snake-case properties mirror the unchanged
  wire contract.
- `Decoding/HistoricalScanPageDecoder.swift` splits raw scan pages into rows and
  decodes each row with the production PostgREST decoder. Malformed rows are
  quarantined without changing raw-row pagination.
- `Services/HistoricalSyncCloudClient.swift` is the sole live Auth-lease and
  PostgREST owner for historical scans and collections. Its injected closures
  keep request forwarding deterministic in tests.
- `Persistence/HistoricalDatabaseActor.swift` owns only actor-isolated SwiftData
  reconciliation, checkpoint saves, rollback, and cancellation.

`../ScanRepository.swift` remains the main-actor orchestrator. It drains local
collection mutations before pulling, checks the account lease after suspension,
streams scan pages through one persistence actor, accumulates the bounded
collection result before pruning, and publishes library/share-state effects.

## Invariants

- Do not move networking or Auth resolution into Models, Decoding, or
  Persistence.
- Do not move SwiftData access into Services or Models.
- Keep the scan projection, collection projection, filters, ordering, range
  semantics, and account-work lease behavior compatible with the current backend
  contract.
- Advance scan pagination by raw remote row count, not accepted DTO count.
- Reconcile collections only after every scan page has completed.
- Preserve throwing local-read/save boundaries and rollback before
  cancellation-driven collection pruning.
- Map each accepted cloud page through the shared immutable scan-media recovery
  snapshot. Historical hydration may add recovery mappings for that page, but
  the registry prevents its timestamp fallback from outranking strong evidence
  supplied by another caller. Post-startup full-library registration remains
  owned by Core Data Images and `ScanRepository`.
- Keep each production file in this directory and `ScanRepository.swift` at or
  below the 600-line review ceiling.

The canonical behavior and contract references are the
[offline-sync pipeline](../../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md),
[database actor guide](../../../../../../../docs/backend-and-data/03-database-actors.md),
and
[API contracts](../../../../../../../docs/backend-and-data/05-api-contracts.md).

## Test ownership

- `HistoricalScanDecodingTests` owns compatibility decoding, malformed-row
  quarantine, and domain projection coverage.
- `HistoricalScanIngestionTests` owns actor-backed insertion accounting,
  timestamp rejection, and historical audio rehydration.
- `HistoricalScanReconciliationTests` owns update, media-repair, cancellation,
  and collection reconciliation behavior.
- `HistoricalSyncCloudClientTests` owns injected account-lease and request-value
  forwarding through the service seam.
- `CoreDataIntegrationArchitectureTests` freezes the production/test inventory,
  imports, dependency direction, sole query ownership, and file-size ceilings.

`ScanRepositoryTests` remains the selector-compatible suite root shared by the
focused behavior files. The canonical focused and complete-target commands live
in the
[iOS testing strategy](../../../../../../../docs/development-guides/08-testing-strategy.md).
