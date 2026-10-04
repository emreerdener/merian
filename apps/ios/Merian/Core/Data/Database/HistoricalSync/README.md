# Historical Sync

This directory owns authenticated cloud-history hydration for the local scan
library. The layers are intentionally narrow:

- `Models/HistoricalSyncModels.swift` contains request values, typed outcomes,
  and PostgREST DTOs. Snake-case properties mirror the owner-history wire
  contract, including optional immutable identification provenance.
- `Decoding/HistoricalScanPageDecoder.swift` splits raw scan pages into rows and
  decodes each row with the production PostgREST decoder. Malformed rows are
  quarantined without changing raw-row pagination.
- `Services/HistoricalSyncCloudClient.swift` is the sole live Auth-lease and
  PostgREST owner for historical scans and collections. Its injected closures
  keep request forwarding deterministic in tests.
- `Persistence/HistoricalDatabaseActor.swift` owns only actor-isolated SwiftData
  scan reconciliation, checkpoint saves, rollback, and cancellation. Its
  synchronous `HistoricalCollectionReconciler` helper owns collection membership
  and reserved-name restoration within the actor-provided context.
- `HistoricalSyncPolicy.swift` owns the scan/collection page sizes and
  persistence checkpoint interval used by the repository and actor.

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
- `HistoricalScanReconciliationTests` owns update and media-repair behavior.
- `HistoricalLibraryRestorationTests` owns private details, cancellation, and
  collection reconciliation behavior.
- `HistoricalSyncCloudClientTests` owns injected account-lease and request-value
  forwarding through the service seam, plus real SDK request-header coverage
  through an isolated URLSession transport.
- `HistoricalSyncPolicyTests` freezes the exact page and checkpoint values.
- `CoreDataIntegrationArchitectureTests` freezes the production/test inventory,
  imports, dependency direction, sole query ownership, and file-size ceilings.

`ScanRepositoryTests` remains the selector-compatible suite root shared by the
focused behavior files. The canonical focused and complete-target commands live
in the
[iOS testing strategy](../../../../../../../docs/development-guides/08-testing-strategy.md).

## Result configuration

The sole scan projection selects `identification_provenance`. Accepted metadata
is stored as stable JSON bytes in the field introduced by V52 and restored
through the shared historical species projection. Legacy null or omission never
clears a present local value; malformed present metadata quarantines that row
rather than becoming legacy. Raw-row pagination and account/save fences are
unchanged. Unknown but decodable profiles remain present and receive neutral
review guidance instead of Gemini confidence bands.
`IdentificationResultProvenanceTests` verifies these paths.

`MerianSupabaseClientFactory` advertises result-reader capability 6 on SDK
requests. It uses the same constant as inference dispatch. The backend checks
that capability before returning visible V2 or explicit-primary rows, including
a single-scan projection or a page that mixes old and new results. Older readers
receive a query error; they retain existing local observations and must update
to hydrate newer cloud results. This is separate from malformed-row quarantine
and does not hide rows or rewrite metadata. The
[result-reader contract](../../../../../../../docs/backend-and-data/05-api-contracts.md#identification-result-readers)
owns rollout and rollback requirements.

`ScanRepository` recognizes only exact PostgREST `PT426` /
`client_update_required` failures after rechecking the account lease. It records
the shared update requirement and skips further history reads on that installed
build. A targeted read returns `clientUpdateRequired`, separately from transient
transport or row-decoding failures. `HistoricalSyncUpdateRequiredTests` covers
lease fencing, repeat-read suppression, retained local work, and server-owned
retry pauses. History resumes after a different installed release/build; paused
identification scans remain available for explicit retry.

The projection also selects `primary_identification`.
`HistoricalPrimaryIdentification` validates the reserved schema pairing before
any reconciliation writes. Its `mergeAIIdentificationReview` helper applies
revision-checked rejection authority while preserving pending local intent and
explicit-primary review fields. Equal-revision conflicts fail before legacy
fields are staged. The helper preserves original labels and immutable snapshots,
and clears species-only caches and stale taxonomy for broader results. Missing
metadata from an older projection cannot erase a valid stored primary answer.
Malformed required data cannot become legacy through omission. V53 stores the
snapshot and separate confirmation bytes; legacy boolean/UUID review fields are
not independent species authority for an explicit broader answer.

`HistoricalScanResponse+Decoding` uses `VerifiedSpeciesReviewProjection` to
preserve field presence. Omitted identity and revision mean an older projection;
explicit null identity with a revision is an authoritative clear. Partial,
malformed or contradictory projections are rejected per row. Legacy rows may
project null identity/revision zero without changing their existing review
rules. `ConfirmedSpeciesReviewPersistence` merges the entire server review tuple
only at a newer revision; equal conflicting revisions fail, older revisions are
ignored, and equal matching history preserves pending local intent. Both missing
local rows and targeted history recovery use this same projection.

History page reconciliation and native review prepare/apply share one bounded,
synchronous transaction gate and create fresh ModelContexts while holding it.
This covers fetch, revision comparison and save across otherwise independent
ModelActors; a cached history context cannot overwrite a newer acknowledgement.
There is no network suspension while the gate is held. Account leases, page
bounds, checkpoint saves and cancellation remain with their existing owners. The
reader header is 6 for owner-review-aware results, matching inference preflight
and dispatch.

## Private library restoration

`Models/LibraryRestorationState.swift` tracks account, restoration generation,
and `notStarted`, `restoring`, `needsAttention`, or `complete`. Only successful
scan and collection pagination with no quarantined rows can complete the full
restore. A stale generation cannot complete a newer restore. Completion does not
certify pending local edits or per-item media availability.

Before either paged or targeted fetching, `ScanRepository` durably stages legacy
local details through `LibraryDetailsSyncService`; failed preparation stops the
fetch. Targeted preparation reads only the requested scan and its operations.
The live client combines owner history with the bounded private-detail RPC.
Pending immutable detail intent wins over remote notes, tags and Favorites;
accepted remote state supplies a completed baseline for later inventory checks.

`HistoricalDatabaseActor` preserves the IDs and memberships of legacy remote
collections colliding with reserved Favorites under a restored name. Independent
private-detail evidence is required before moving a membership into the private
Favorites folder; a cancelled newer operation cannot expose an older favorite
value as current proof. The next ordinary collection sync propagates the adapted
name. See the
[canonical transition contract](../../../../../../../docs/backend-and-data/21-guest-library-transitions.md)
for exact duplicate, privacy and collision semantics.

`HistoricalLibraryRestorationTests` exercises both restoration entrypoints,
private details, stale remote snapshots, and reserved-name collisions.
`LibraryMutationInventoryTests` covers partial/stale restoration status. The
[transition validation matrix](../../../../../../../docs/development-guides/08-testing-strategy.md#guest-library-transition-validation)
separates this deterministic coverage from physical-device acceptance.

Before scan-page validation, media recovery or mutation, the actor skips pending
cloud deletions and observations protected by a history enrollment intent,
acknowledged history or terminal local deletion fence. This applies to full and
targeted scan hydration through `reconcileScanPage`. A late response cannot
recreate a history observation after its explicit erasure and cloud receipt
cleanup. Collection reconciliation remains separately owned. See the
[history admission boundary](../../AnalysisHistory/README.md#prepared-native-enrollment).
