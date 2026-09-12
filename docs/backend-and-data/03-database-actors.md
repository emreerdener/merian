# Database Actors

Merian uses multiple Swift `@ModelActor` and `actor` types to safely perform
SwiftData and disk I/O work off the main thread. This document explains which
actor to use when, how `@ModelActor` isolation works, and why each actor is
created ad-hoc rather than reused as a singleton.

---

## Why Actors?

The main thread owns the SwiftUI view hierarchy and the primary `ModelContext`.
Performing bulk SwiftData fetches, large ingests, or disk I/O on the main thread
causes visible UI stuttering and risks JetSam termination. Actors provide
compile-time-enforced isolation: work inside an actor runs on that actor's
executor, never blocking the main thread.

---

## Shared DTOs And Coordination

`Sendable` value types shared across the offline sync pipeline live in focused
files under `Core/Data/OfflineSync/Models`; stateless wire-adjacent and
state-transition contracts live under `OfflineSync/Policies`. The
[Offline Sync README](../../apps/ios/Merian/Core/Data/OfflineSync/README.md)
keeps the complete ownership inventory discoverable without coupling unrelated
declarations in one aggregate file:

| Type                                  | Purpose                                                                                                                                                                                                                                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PendingScanPayload`                  | Minimal snapshot of a queued scan returned by `fetchPendingScans(limit:)`, including local image, audio, and video paths. Safe to pass across actor boundaries.                                                                                                                                        |
| `CollectionSyncSnapshot`              | Immutable desired state projected from a non-Favorites collection and its direct scan relationships. Core Network maps it to the private wire DTO.                                                                                                                                                     |
| `ScanUploadItem`                      | One local media file ready for a presigned R2 PUT — `scanId`, per-scan `uploadIndex`, `mediaKind`, `fileName`, `fileURL`, `contentType`, and expected `objectKey`.                                                                                                                                     |
| `ExtractedScanData`                   | Full `OfflineQueuedScan` snapshot captured on the main actor for handoff to background inference. Carries the canonical ordered `capturedMediaItems: [SerializedMediaItem]` timeline, from which image paths, audio paths, prompt text, and serialized observation contexts are derived on demand.     |
| `OfflineQueueDurableAuthority`        | Immutable projection of mirrored scan/job error codes, attempt counts, and required-video count read through one fresh throwing context.                                                                                                                                                               |
| `OfflineScanProcessingResult`         | Result of `BackgroundInferenceFinalizationService.processAndCleanupOfflineScan` — species name, discovery flag, `speciesData` for engine hydration, and `wasCleaned` commit proof controlling main-actor queue deletion.                                                                               |
| `ScanStagingTransitionOutcome`        | Durable result of upload-manifest promotion: committed staging, matching serialized advance, retry required, or discarded non-runnable work. It lives beside the focused upload-lifecycle persistence methods.                                                                                         |
| `ScanFinalizationCoordinator`         | Per-scan async lock used by live visual, live non-visual, and background URLSession finalizers before they write `LocalScanRecord.id`. Prevents Core Data unique-constraint merge policy from merging no-inverse media relationships when the two inference paths complete the same scan concurrently. |
| `ScanInferencePersistenceCoordinator` | Per-scan async lock shared by every `BackgroundDatabaseActor` instance and the main-actor queue deletion path. It keeps the durable inference-generation check, URLSession cancellation, retry retreat/finalization, and SwiftData save inside one compare-before-mutate critical section.             |

Both per-scan coordinators live in `ScanPersistenceCoordinators.swift` beside
`BackgroundDatabaseActor`, while the process-local generation task registry
lives under `OfflineSync/Coordinators`. They are executable coordination rather
than transport DTOs. The in-memory lock is not the ownership authority:
`OfflineJobRecord.metadataJSON` stores the UUID generation transactionally with
`.staged → .inferencing`, and every late retry, completion, or delete must match
that durable value. A `nil` value may be adopted only for work already in flight
during the rollout; a non-`nil` generation is never overwritten by a different
attempt.

---

## Actor Inventory

### `BackgroundDatabaseActor` (`Core/Data/Database/BackgroundDatabaseActor*.swift`)

**Declaration**: `@ModelActor actor BackgroundDatabaseActor`

`BackgroundDatabaseActor.swift` contains only that declaration. Every operation
is grouped in a focused sibling extension; cross-domain orchestration remains in
the service that owns the workflow.

**Responsibilities:**

_Upload state machine (V33):_

Pending selection and empty-media quarantine are implemented in the focused
`Core/Data/Database/BackgroundDatabaseActor+QueueSelection.swift` extension. The
extension owns SwiftData reads and mutations only; Media Upload's
`Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift`
is its sole production consumer and retains live-transfer exclusions,
video-network policy, and orchestration.

Upload claim, durable staging, and orphaned-upload release are implemented in
`Core/Data/Database/BackgroundDatabaseActor+UploadLifecycle.swift`. That
extension owns only the serialized SwiftData transitions; Media Upload and
Inference Replay retain signing, URLSession inspection, network policy, and
orchestration. A matching-job fetch failure rolls back the complete claim or
orphan-recovery batch instead of committing split scan/job state; an absent
legacy job remains a supported lookup result.
`BackgroundDatabaseActor+RetryMirror.swift` supplies an actor-isolated helper
shared only with upload lifecycle and focused inference persistence so both
sides apply the same scan/job retry-authority repair without exposing unisolated
model mutation.

Durable background-account ownership is implemented in
`Core/Data/Database/BackgroundDatabaseActor+BackgroundAccountWork.swift`. The
extension owns only SwiftData activation, current-owner validation, transition
candidate projection, and retirement. Background Transfer retains Auth leases,
transition quiescence, terminal routing, and URLSession cancellation; Media
Upload retains request dispatch. All scan/job reads are throwing and fail
closed, so persistence failure cannot masquerade as an absent legacy record;
failures retain private diagnostic context. Activation creates a genuinely
absent legacy ingestion job in the same save as its owner marker.

Inference lifecycle and retry persistence are implemented in
`Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift` and
`BackgroundDatabaseActor+InferenceRetry.swift`. The lifecycle owner contains
durable eligibility, claims, retreats, generation checks, telemetry hydration,
and timestamp-fenced orphan recovery. The retry owner contains general and
server-result recovery retry commits. Background Inference, Inference Replay,
Media Upload, and Queue Maintenance retain process ownership, scheduling,
URLSession/network effects, and orchestration. Every scan/job read is throwing;
genuinely missing legacy jobs remain supported. Orphan recovery locks candidates
in stable ID order, rereads eligibility from a fresh context after waiting, and
loads every candidate job before mutating its batch.

Scan creation and finalization are split by responsibility.
`BackgroundDatabaseActor+LiveScanPersistence.swift` retains the existing visual
and nonvisual save entry points.
`BackgroundDatabaseActor+OfflineFinalization.swift` owns durable generation
validation/adoption and commits already-prepared background results.
`BackgroundDatabaseActor+ScanRecordSupport.swift` contains only their shared
actor-isolated reads and inserts, while `LocalScanRecordFactory` owns complete
value mapping without a `ModelContext`. `CapturedMediaPersistenceService`
preserves ordered media serialization and delegates audio/video adoption to
`FileIOActor` through injected closures. Cross-domain background orchestration
lives in
`OfflineSync/Services/BackgroundInference/BackgroundInferenceFinalizationService.swift`;
shared foreground/background response preparation lives in the stateless
`Core/AI/Inference/Services/InferenceResponsePreparationService.swift`.

- `fetchPendingScans(limit:)` — pages the complete `.pending` (state 0),
  non-attention set in deterministic timestamp/ID order, moving past future
  retry deadlines, process-local exclusions, and video rows that are ineligible
  on the current network. It returns up to `limit` runnable-media payloads plus
  a separately bounded empty-media quarantine set. Complimentary Pro and legacy
  rows retain the first funding tier, followed by paid Pro and immediate Flash;
  deferred Flash is excluded. Order remains stable within each tier. An
  unreadable funding-job query fails selection closed and returns no candidates
  instead of treating every row as legacy/unfunded work. Scans in `.uploading`,
  `.staged`, `.inferencing`, or `.failed` remain excluded.
- `quarantineEmptyPendingScans(scanIds:)` — re-fetches each candidate on the
  actor and changes only a row that is still pending, is not already marked for
  attention, and still has no local image, audio, or video. The scan failure,
  any existing matching offline-job attention state, and diagnostic event commit
  in one save. Scan/job fetch or save failure rolls back the complete batch and
  returns no accepted IDs. A genuinely absent matching job remains a supported
  legacy case: the scan and event still commit atomically.
- `markScansAsUploading(scanIds:)` — transitions scans from
  `.pending → .uploading`, persists before URLSession tasks are dispatched, and
  returns the claimed scan IDs. Source-state guard: predicate restricts the
  fetch to `.pending` records only, so in-flight or tombstoned scans cannot be
  double-dispatched. Fetch/save failures rollback the actor context and return
  an empty set so the caller does not sign or dispatch unclaimed files.
- `markScanAsStaged(scanId:r2Keys:)` — called once the last media upload for a
  scan confirms HTTP 200. Persists the confirmed image/audio R2 object keys into
  `stagedR2Keys`, normally resets upload retry metadata, updates the queue job,
  and transitions `.uploading → .staged` in one save. Source-state guard: only
  advances from `.uploading` and never intentionally advances a tombstone the
  actor already observes. It returns `.staged` only after save,
  `.alreadyAdvanced` for a serialized matching staged manifest or inferencing
  owner, `.retryRequired` for retryable fetch/state/manifest/save failure, and
  `.discarded` for missing or non-runnable rows. Save failure rolls back every
  part of the transaction, and the upload callback cannot continue to an
  inference claim from uncommitted or mismatched keys. An exact scheduled
  `server_retryable_failure` reclaim preserves its marker, count, last attempt,
  and matching job metadata through a required re-stage.
- `tryClaimForInference(scanId:generation:)` — atomic local-persistence lock for
  inference. It transitions `.staged → .inferencing` and saves the generation in
  the same transaction; returns `false` if the scan is already `.inferencing`,
  not found, cancelled while waiting, or if a read/save fails and rolls back. A
  genuinely absent legacy job is inserted only after both durable reads succeed;
  storage failure cannot masquerade as that compatibility case.
  `ScanInferencePersistenceCoordinator` serializes independent SwiftData
  contexts for that scan, so only one pipeline can win the claim. The race
  between the focused media-upload completion owner
  (`Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift`) and the
  uploaded-scan replay owner
  (`Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift`) is
  closed at the persistence boundary.
- `transitionScanToStaged(id:)` — retreats `.inferencing → .staged` on transient
  inference failure so `replayInferenceForUploadedScans` can reclaim the scan on
  the next connectivity restore. Source-state guard: only retreats from
  `.inferencing` and does not intentionally retreat a `.failed` row already
  visible to the actor. Cross-context ordering and visibility require the
  separate persistence-fence/fresh-read rules below. Save failure rolls back the
  actor context.
- Generation-aware claims persist the attempt UUID in the scan-ingestion job.
  Retry scheduling, retreat, final record persistence, and queue deletion
  acquire `ScanInferencePersistenceCoordinator`, compare that UUID, and discard
  stale callbacks before they can save or cancel URLSession work.
- `reconcileOrphanedUploadingScans(activeScanIds:observedThrough:)` — resets
  `.uploading → .pending` for scans with no active URLSession task and returns
  `true` only when that save commits. The caller captures `observedThrough`
  before enumerating tasks; rows claimed after that snapshot have a newer
  `queueUpdatedAt` and cannot be reset by the delayed reconciliation pass.
- `reconcileOrphanedInferencingScans(activeInferenceScanIds:observedThrough:)` —
  cross-references current and legacy inference URLSession tasks before
  selecting `.inferencing → .staged` candidates. It uses the same snapshot
  cutoff, acquires candidate persistence fences in stable ID order, and rereads
  eligibility through a fresh context after waiting. Only stable IDs cross that
  suspension; SwiftData models are fetched afterward on the shared actor. All
  candidate jobs are preloaded before the first mutation, so newer terminal or
  retry state wins and any read or save failure aborts and rolls back the
  complete batch.

`QueueSelectionPersistenceTests` mirrors state filtering, complete-set paging,
stable funding priority, actor-isolated payload extraction, and empty-media
quarantine with both an existing matching job and the supported missing-job
case. `QueueSelectionArchitectureTests` freezes sole declaration/test ownership,
the exact Upload Sync consumer allowlist, fail-closed funding/job reads, shared
offline-job lookup, narrow dependencies, and 600-line focused-file ceilings.

`UploadLifecyclePersistenceTests` mirrors the three extracted transitions,
including every staging outcome, retry-marker preservation, durable-job orphan
release, and task-snapshot/candidate fencing. `UploadLifecycleArchitectureTests`
freezes the declarations and outcome owner, exact Offline Sync consumer
allowlists, throwing matching-job reads, the actor-isolated retry-mirror support
boundary, mirrored behavior-test ownership, 600-line focused-file ceilings, and
a 1,900-line non-growth cap on the residual actor aggregate.

`BackgroundAccountWorkPersistenceTests` owns the three extracted
background-account regressions—exact upload-owner retirement, rejected
inference-dispatch requeue, and retirement after an upload callback advances to
staged—plus activation-time ingestion-job creation for a legacy scan without
one. `BackgroundAccountWorkArchitectureTests` freezes sole declaration and test
ownership, the exact Background Transfer and Media Upload consumer allowlists,
throwing reads, balanced per-scan persistence fences, dependency exclusions,
400-line focused-file ceilings, and a 1,600-line non-growth cap on the residual
aggregate.

`InferenceLifecyclePersistenceTests` mirrors claims, retreats, durable
generation checks, timestamp-fenced orphan release, missing-job compatibility,
post-wait terminal-state revalidation, and cancellation fence release.
`InferenceRetryPersistenceTests` mirrors general and server-result retry
commits, monotonic authority, cloud-complete veto, missing-job compatibility,
and cancellation fence release. `InferencePersistenceArchitectureTests` freezes
sole declaration/test ownership, exact Offline Sync consumers, throwing reads,
orphan-batch preload, private helpers, balanced persistence fences, dependency
exclusions, focused source/test ceilings, and a 1,000-line cap on the residual
aggregate.

`CapturedMediaPersistenceServiceTests` locks explicit/default timeline order,
invalid-item filtering, standalone-audio source identity, and the
generic-constrained compile check for the complete finalization response/result
graph. `ScanFinalizationArchitectureTests` freezes the declaration-only actor
file, sole declaration ownership, dependency direction, coordinator containment,
shared foreground/background response preparation, explicit checked-sendability
declarations, rejection of an unchecked prepared-response conformance, and the
rule that background finalization must not await `InferenceProcessingActor`
while holding the scan persistence fence. Existing finalization and dual-path
race behaviors remain in `BackgroundDatabaseActorTests`.

### Core Data-wide Read and Mutation Invariant

An optional SwiftData result represents absence only after a successful fetch.
Production files under `Core/Data` do not use `try?` with `fetch` or
`fetchCount`. A storage failure retains private diagnostic context and aborts
the related mutation, network dispatch, or reconciliation pass. This rule also
applies to `HistoricalDatabaseActor`/`ScanRepository`, so failed library,
collection, membership, or Favorites reads cannot be converted into an empty
authoritative snapshot.

`OfflineQueueDurableAuthorityReader` constructs one fresh `ModelContext` and
reads both the scan row and matching ingestion job before returning their
mirrored retry/completion authority. Missing manager persistence throws rather
than returning an all-empty value. `extractedQueuedScanData(scanId:)` likewise
throws on read or goal-hint failure and returns `nil` only for a proven missing
queue row. Background completion persists retry state for an unreadable
snapshot; upload completion restores the scheduler wake instead of dispatching
from incomplete metadata.

Durability gates the side effects surrounding these actors. Collection sync
starts no service or endpoint work unless its `.running` job claim saves. Cloud
deletion loads task/job pairs and commits their claims before dispatch, then
removes a task only after its result can be applied to the corresponding job.
Offline finalization checks cancellation after acquiring the scan persistence
lock, and its support lookups remain throwing across any file-adoption
suspension. `CoreDataIntegrationArchitectureTests` freezes the exact 13-file
actor surface, imports and 600-line ceilings, declaration-only root, silent-read
ban, durable-authority owner/consumer bounds, and cross-surface throwing
contracts.

_Unsupported queued audio:_

`BackgroundDatabaseActor` does not transcode or rewrite persisted inference
media. Pending upload validation, surviving upload completion callbacks, and
staged replay quarantine any row whose audio reference is remote or not a local
WAV. `tryClaimForInference(scanId:)` independently repeats that format fence as
the final serialized transition guard. Quarantine preserves the scan and job as
needs-attention work with `queued_media_invalid`, allowing explicit retry or
cancellation without forwarding an unsupported manifest to signing or inference.
The released `queueSchemaRepairGeneration` property remains an inert V49+
compatibility field until a future intentional schema migration removes it.

_Offline scan processing:_

- `BackgroundInferenceFinalizationService.processAndCleanupOfflineScan(...)` —
  the top-level background orchestration boundary. It acquires
  `ScanInferencePersistenceCoordinator`, asks the injected persistence actor to
  validate or adopt the exact durable generation, delegates decode, success
  validation, domain mapping, and entitlement reconciliation to
  `InferenceResponsePreparationService`, rejects a mismatched provider scan ID,
  then hands prepared `SpeciesData` to the actor. It does not await
  `InferenceProcessingActor`, preventing a lock/actor dependency cycle with
  foreground parsing.
- `persistOfflineScanResultAssumingPersistenceLock(...)` — the focused
  actor-isolated commit. It resolves species identity, acquires
  `ScanFinalizationCoordinator`, rechecks for an existing record after any wait,
  maps through `LocalScanRecordFactory`, and saves. It includes candidates,
  inference tier, image quality, alternative names, both captured-media
  representations, and the original capture timestamp. Save failure rolls back
  and clears the result identity so callers cannot publish ghost notifications
  or hydrate an engine without a committed UUID.
- The background actor intentionally does **not** delete `OfflineQueuedScan`.
  After a successful commit, the main actor calls `deleteQueuedScan` with
  adopted media paths and the exact generation expectation. That produces a real
  pending deletion in the main `ModelContext` for reliable `@Query`
  reevaluation, removes queue-only inference frames, preserves media adopted by
  the final record, and denies stale work deletion authority. The legacy
  `wasCleaned` result name is a commit proof; it does not claim the queue row
  was already removed.
- `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:videoFilePaths:mediaTimeline:persistenceFence:)`
  — persists a real-time scan result after live inference. Accepts the current
  media timeline and legacy-derived arrays. Queue-backed live callers also
  provide `LiveInferencePersistenceFence(scanId:generation:)`; a stale durable
  owner or mismatched provider scan ID is rejected before writing. The method
  writes the mixed-media payload into both `capturedMediaJSON` and
  `capturedMediaEntries`. The JSON mirror is the preferred hot read path for
  `CapturedMediaSnapshot`; the relationship mirror remains populated for
  migration/debugging/fallback durability. Persists `imageQualityScore`
  (Gemini's photographic quality score, 0–100) from `SpeciesData`. Unlike
  `blurScore` (ephemeral, live-only, never written to disk), `imageQualityScore`
  is stored permanently for future community reference-photo curation. It
  acquires `ScanFinalizationCoordinator` for `mappedData.scanId`, then reuses
  `scanRecordSpeciesIdentity(...)`, `CapturedMediaPersistenceService`,
  `LocalScanRecordFactory`, and `insertReplacingLocalScanRecord(...)`; this
  preserves an existing species UUID and staged field notes while replacing any
  queued/offline collision row with the richer foreground result. The durable
  generation is revalidated while holding the per-scan persistence coordinator
  before finalization and save. Save failure rolls back and returns `.notSaved`,
  suppressing downstream new-discovery side effects for an uncommitted record.
- `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:videoFilePaths:mediaTimeline:persistenceFence:)`
  — persists description-only, audio-only, or mixed non-visual results after
  `/identify-multimodal` inference when there are no local image files. Uses the
  same ordered media timeline, live persistence fence, media service, record
  factory, and replacement helper as visual saves, but keeps its
  modality-specific `coverImagePath == nil` / `isLiveCapture == false` behavior.
  It also acquires `ScanFinalizationCoordinator` before species resolution and
  replacement so audio/description live completion cannot race the background
  completion for the same queued scan. Save failure rolls back and returns
  `.notSaved`.

_Non-biological retention and deletion:_

These operations and their result/input values live in
`Core/Data/Database/BackgroundDatabaseActor+NonBiologicalRetention.swift`. The
focused extension retains the actor and method signatures and has no endpoint,
Auth, file-system, or UI dependency.

`ScanErasurePayload.mediaPaths` intentionally carries image, audio, and video
paths. `ExpiredNonBiologicalPurgeResult` separately exposes committed erasure
work and actual row deletion so its repository caller can route durable cleanup
and presentation invalidation correctly.

- `bulkDeleteNonBiologicalScans(payloads:)` — re-fetches each candidate at
  commit time, skips a row now classified as biological, deletes eligible
  records, and creates or reuses their `PendingCloudDeletionTask` values in the
  same save. It returns only local media paths, and only after the save commits;
  save failure rolls back the entire actor context.
- `purgeExpiredNonBiologicalScans(cutoffDate:limit:)` — fetches an oldest-first,
  bounded batch of expired non-biological records and delegates to the same
  atomic deletion boundary. Its result distinguishes accepted erasure work from
  rows actually deleted. `ScanRepository` uses the first count to drain files
  and cloud tombstones and the second to publish the library change, so a
  missing row finishes idempotent cleanup while commit-time reclassification
  publishes no false effects. Foreground cleanup can process another batch later
  instead of materializing a pathological library at once.

`NonBiologicalRetentionPersistenceTests` mirrors commit ordering, idempotent
tombstone reuse, missing-row retry cleanup, biological reclassification fencing,
expired-only selection, and oldest-first batch limiting.
`NonBiologicalRetentionArchitectureTests` inventories the complete production
and test Swift trees for sole declaration/test ownership, exact narrow imports,
committed-count fencing, repository effect routing, forbidden dependencies, and
600-line focused-file ceilings.

_Enrichment and metadata:_

These operations are implemented together in
`Core/Data/Database/BackgroundDatabaseActor+SpeciesMetadata.swift`. The focused
extension retains the existing actor and method signatures, and keeps its
fetch-mutate-save and identification-presentation reset helpers private. It owns
no request DTO, endpoint call, Auth lease, file access, or UI presentation.

- `beginScanIdentificationOverride(scanId:scientificName:)` — atomically
  persists the local override state, clears confirmation/legacy flag state, and
  replaces prior-species presentation fields with a scientific-name placeholder
  before asynchronous Species Dictionary hydration.
- `updateScanWithOverride(scanId:override:confirmed:newConfirmedSpeciesId:userReviewState:)`
  — atomic persistence for user review states. Saves the explicit user
  Identification Override locally, captures truth signals, and synchronously
  persists the verified Edge taxonomy target directly into `confirmedSpeciesId`
  bridging the `userReviewState` explicitly. An `.unreviewed` mutation also
  atomically replaces common-name, hazard, taxonomy, Wikipedia, reference,
  conservation, habitat, GBIF, lookalike, and alternate-name values with the
  original scientific-name placeholder.
- `updateScanWithWikipedia(scanId:extract:url:imageUrl:expectedScientificName:)`
  — retroactively hydrates a scan with Wikipedia or GBIF data. By accepting
  optional `String?` parameters, this method permits selective patching (e.g.,
  updating only `referenceImageUrl` from GBIF without overwriting an existing
  `wikipediaOverview`). When supplied, `expectedScientificName` must match the
  record's effective override-or-original identity; stale work returns `false`
  without saving. Save failure rolls back the actor context, matching the shared
  `mutateScan(...)` containment used by enrichment and override point-updates.
- `updateScanWithOverrideSpeciesData(scanId:commonName:hazardType:wikipediaOverview:wikipediaUrl:referenceImageUrl:iucnRedListStatus:habitatDescription:gbifTaxonKey:taxonomy:replacingSpeciesIdentity:)`
  — persists species-dictionary data fetched for an identification override or
  reset so the corrected fields survive sheet dismissal and reopen.
  Intentionally excludes `scientificName` — that column is preserved as the
  original-AI identifier and is reused as `aiScientificName` in
  `InferenceEngine.load(from:)`. Interactive replacement passes `true` to clear
  prior taxonomy/lookalikes; historical refresh passes `false` so a sparse row
  preserves valid same-species values.
- `updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:alternativeCommonNames:expectedScientificName:)`
  — retroactively persists enrichment data returned by the `enrich-scan` Edge
  Function. Called by `InferenceEngine.fetchAndApplyEnrichment` after the async
  enrichment call completes. Updates `habitatDescription`, `gbifTaxonKey`,
  `lookalikesData` (a JSON-encoded `[SimilarSpeciesEntry]` blob, added in
  `MerianSchemaV27`), and taxonomic ranks (`Kingdom` through `Genus`) on
  `LocalScanRecord`. When `alternativeCommonNames` is non-nil, the method also
  writes it to `record.alternativeCommonNames` on the `LocalScanRecord`. The
  caller is responsible for encoding `[SimilarSpeciesEntry]` to `Data` via
  `JSONEncoder` before calling this method. A supplied `expectedScientificName`
  must match the record's original AI scientific name, preventing a stale
  enrichment response from mutating a replacement record.
- `clearAllLocalLookalikesCache()` — recovery path for stale similar-species
  caches. Fetches only biological records with `lookalikesData` or
  `similarSpecies` present, in 200-record batches, saving after each batch. Save
  failure rolls back the current batch and exits. It must not use an unbounded
  `FetchDescriptor<LocalScanRecord>()`.
- `updateScanAsUnflagged(scanId:)` — clears the legacy manual-review flag
  through the shared fetch-mutate-save helper when an identification changes or
  resets.
- `collectionSyncSnapshots()` / `purgeSyncedCollectionTombstones(ids:)` live in
  `BackgroundDatabaseActor+CollectionSync.swift`. The projection fetches only
  non-Favorites `ScanCollection` rows, prefetches their direct inverse `scans`
  relationships, and emits deterministic, sorted membership IDs. It does not
  enumerate unrelated `LocalScanRecord` rows or use OFFSET pagination. After a
  successful remote response, a fresh actor purges only requested rows that are
  still application tombstones at commit time. A save failure rolls back and
  returns failure through `CollectionSyncService`, so `OfflineQueueManager`
  retains the pending job. The actor owns no request DTO, Auth lease, or network
  call. Callers must use the shared collection drain
  (`syncCollectionsIfPending()` / `drainCollectionSyncIfPossible()`), never an
  unsynchronised side path.

`SpeciesMetadataPersistenceTests` mirrors the species-metadata behavior above.
`SpeciesMetadataArchitectureTests` inventories every Swift file in the iOS
production and test trees, requiring each of the seven extracted persistence
methods and each rehomed behavior test to have exactly one focused owner. It
also locks the private helper boundary, exact framework imports, dependency
exclusions, and 600-line ceilings.

**When to create**: Two patterns — ad-hoc for most operations, long-lived for
the offline queue state machine:

```swift
// Ad-hoc: for live saves, metadata, retention deletion, or collections.
// Focused sibling extensions own metadata, retention, and collection operations.
let container = modelContext.container
let dbActor = BackgroundDatabaseActor(modelContainer: container)
let fence = LiveInferencePersistenceFence(
    scanId: scanId,
    generation: foregroundGeneration
)
await dbActor.saveLiveScanRecord(
    mappedData: data,
    localImagePaths: paths,
    observationContextsJSON: obsJSONs,
    audioFilePaths: audioPaths,
    mediaTimeline: mediaTimeline,
    persistenceFence: fence
)

// Long-lived: for pending selection/quarantine, upload/inference claims,
// retries, and orphan recovery. Focused extensions own queue selection and
// upload-lifecycle persistence.
// OfflineQueueManager maintains one instance via resolvedQueueDbActor(container:).
// The shared executor plus observedThrough cutoffs keep a stale reconcile from
// overwriting a replacement upload or inference claim.
// Never call resolvedQueueDbActor directly from outside OfflineQueueManager.
let queueActor = resolvedQueueDbActor(container: container)
guard await queueActor.tryClaimForInference(scanId: scanId) else { return }
```

---

### `HistoricalDatabaseActor`

**File**:
`Core/Data/Database/HistoricalSync/Persistence/HistoricalDatabaseActor.swift`

**Declaration**: `@ModelActor actor HistoricalDatabaseActor`

Historical hydration has four bounded owners. `HistoricalSyncModels.swift`
contains request values and unchanged wire DTOs,
`HistoricalScanPageDecoder.swift` owns row-isolated PostgREST decoding,
`HistoricalSyncCloudClient.swift` is the sole live Auth/PostgREST adapter, and
this actor owns only SwiftData reconciliation. `ScanRepository.swift` retains
push-before-pull ordering, pagination, account-lease checks, and app-event
orchestration.

**Responsibilities:**

- `reconcileScanPage(responses:)` — primary entry point for streaming
  reconciliation; called once per page fetched from the cloud. Computes the
  existing-ID set fresh each call via a chunked `FetchDescriptor` with
  `propertiesToFetch = [\.id]` (ID-only column projection), then delegates to
  `updateExistingScans` and `ingestScans` for the page. Returns the count of
  validated, inserted records and throws when a local read or save fails.
- `syncCollectionsDown(remoteCollections:)` — called once, after all scan pages
  have been streamed. Delegates to the throwing `syncCollections` boundary.
  Cancellation rolls back before any absent-remote deletion can commit.
- `updateExistingScans` (private) — **chunk-process-save** loop: for each stride
  of 500 IDs, fetches that chunk's full `LocalScanRecord` objects, mutates
  changed fields, calls `modelContext.save()` if any field changed, then lets
  the chunk's references fall out of scope so ARC reclaims the heap before the
  next stride. Save failures rollback the historical actor context and abort the
  current reconciliation so callers can retry. A single `JSONEncoder` is hoisted
  above both loops to avoid per-record allocation overhead. Prevents IN-clause
  planner degradation and bounds peak faulted-object count to one chunk.
- `ingestScans` (private) — inserts new `LocalScanRecord` rows; checkpoint-saves
  every `HistoricalSyncPolicy.ingestCheckpointInterval` (100) records.
  Checkpoint and final save failures rollback the pending insert batch so failed
  historical ingestion cannot poison later sync attempts; the failure is
  rethrown rather than returned as an empty successful page.
- `syncCollections` (private) — upserts `ScanCollection` records; fetches local
  scans referenced by incoming collections and builds current membership from
  bounded inverse-side `LocalScanRecord.collections` batches. Read failures
  abort rather than substituting an empty collection or membership snapshot.
  Save failures rollback the actor-isolated `ModelContext` so partial inbound
  names, deletes, or membership rewrites do not remain pending after
  reconciliation fails. Cancellation follows the same rollback rule without
  being logged as a storage error. **When to create**: Ad-hoc, once per
  `syncHistoricalScansDown` call. The repository and its focused cloud adapter
  stream and decode one page at a time; the persistence actor accepts
  already-decoded values and performs no network or Auth work:

```swift
let dbActor = HistoricalDatabaseActor(modelContainer: container)

// ScanRepository supplies one decoded page, then releases it before fetching
// the next raw page through HistoricalSyncCloudClient.
try await dbActor.reconcileScanPage(responses: decodedPage.responses)

// Collections are small in count — still fully accumulated, then synced once
try await dbActor.syncCollectionsDown(remoteCollections: allCollections)
```

The design principle is page-at-a-time streaming: each page is processed and
released before the next is fetched, keeping the in-memory scan accumulation
O(page_size) rather than O(total_library_size) regardless of how many scans the
user has.

---

### `ProfileDatabaseActor` (`Features/Profile/UserProfile/Services/ProfileDatabaseActor.swift`)

**Declaration**: `@ModelActor actor ProfileDatabaseActor`

**Responsibilities:**

- `calculateAll()` — **preferred Profile render entry point**. Loads one compact
  scalar `propertiesToFetch` projection covering stats, heatmap, and awards and
  returns `ProfileAllStatsPayload`. It replaces separate Profile render fetches.
- `calculateProfileStats()` — fetches with `[\.scientificName, \.timestamp]`
  values from the shared cached projection; computes species count and streak.
- `calculateHeatmapData()` — computes the 52-week scan heatmap from the shared
  cached projection.
- `calculateAwards()` — invalidates the cached analytics projection, then
  delegates to `AchievementsCalculator.calculate(from:)`. The post-inference
  milestone path calls it after every successful inference, not only a new
  discovery, because inference can update an existing record without changing
  the projection fingerprint and awards can trigger on time-of-day, taxonomy,
  elevation, and other conditions.
- `calculateAchievementDetail(for:)` — lazily loads a separate detail projection
  containing the media-adjacent fields needed by the achievement sheet. It does
  not widen the default Profile render projection.

**When to create**: Ad-hoc for profile tab; long-lived shared instance for
post-inference award refresh:

```swift
// ProfileTabDependencies.live — one ad-hoc actor behind the injected adapter.
let actor = ProfileDatabaseActor(modelContainer: modelContainer)
let payload = await actor.calculateAll()

// InferenceEngine — post-inference award refresh only (long-lived shared instance)
// OfflineQueueManager.shared.resolvedProfileDbActor(container:) returns a cached
// ProfileDatabaseActor, reusing the same ModelContext across consecutive inferences
// instead of allocating a fresh actor per scan.
let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: container)
let updatedAwards = await profileActor.calculateAwards()
await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
```

> **Why long-lived for `calculateAwards()`?** On a burst of offline scan
> completions (or rapid successive live scans), `analyze()` calls
> `calculateAwards()` after every result. Allocating a fresh
> `ProfileDatabaseActor` — and with it a fresh `ModelContext` — per scan wastes
> actor setup overhead and generates unnecessary SQLite context churn.
> `resolvedProfileDbActor` maintains one actor per `ModelContainer` identity;
> Swift actor serialization ensures concurrent callers queue safely.
> `calculateAwards()` refreshes the value projection on every call, so this
> reuse saves actor/context setup without carrying award inputs across
> completions.

---

### `SpeciesObservationStatsDatabaseActor` (`Features/SpeciesReference/Services/SpeciesObservationStatsDatabaseActor.swift`, reducer in `Features/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`)

**Declaration**: `@ModelActor actor SpeciesObservationStatsDatabaseActor`

**Responsibilities:**

- `fetchLocalStats(scientificName:speciesId:now:)` — computes private local
  chart overlays for the Species Observation Charts card without blocking
  `@MainActor`.
- Fetches biological candidate rows with filtered `#Predicate` descriptors: one
  descriptor for `speciesId` / `confirmedSpeciesId` when a dictionary species
  UUID exists, and one descriptor for exact `scientificName` /
  `userIdentificationOverride` fallback.
- Merges candidates by `LocalScanRecord.id`, sorts deterministically by
  timestamp/id, then delegates to `SpeciesObservationStatsReducer` so
  seasonality, history, life-stage filtering, and effective-name matching remain
  identical to the previous behavior.
- Uses a narrow `propertiesToFetch` projection containing only reducer fields,
  avoiding full `LocalScanRecord` materialization for large local libraries.

**When to create**: Ad-hoc per chart load from the current `ModelContainer`,
behind `SpeciesObservationStatsDependencies`. Do not fetch the user's entire
biological library from `SpeciesObservationStatsViewModel` on the main actor.

```swift
SpeciesObservationStatsDependencies.live
// Its local closure creates SpeciesObservationStatsDatabaseActor from the
// supplied ModelContainer and awaits fetchLocalStats(...).
```

---

### `SearchDatabaseActor` (`Features/Scans/Library/Services/ScanLibrarySearchActors.swift`)

**Declaration**: `@ModelActor actor SearchDatabaseActor`

**Responsibilities:**

- `extractSearchablePayloads(from:)` — Generates `SearchableScan` structures for
  indexed library text filtering. It batch-fetches requested string IDs with one
  `FetchDescriptor` and restores caller order through an ID map; it does not
  issue one `model(for:)` fault per record.
- Full library rebuilds do not create this actor for a second fetch.
  `ScansLibrarySearchCoordinator` cooperatively extracts `RawScanSnapshot`
  values from its already-resident query, then builds both text payloads and the
  posting-index snapshot in one cancellation-aware detached task.
- Advanced filters are a separate value-type pipeline in
  `ScanLibraryFilterIndex.swift`; they do not dereference SwiftData models from
  `SearchDatabaseActor`.
- `commonGroupName(for:)` — Generates semantic mapping strings from taxonomy
  class limits (e.g. "Aves" -> "bird", "Insecta" -> "insect", "Mammalia" ->
  "mammal") to augment layperson searchability alongside AI reasoning text.

**When to create**: Created ad-hoc by `ScansLibrarySearchCoordinator` for
incremental additions and targeted index hot-swaps. Full rebuilds use
`RawScanSnapshot` values and do not instantiate this actor for a second fetch.
The typed `AppEvent.scanSearchIndexInvalidated(scanId:)` event carries only the
stable ID; the actor reloads the authoritative durable scan before rebuilding
its payload.

```swift
let dbActor = SearchDatabaseActor(modelContainer: container)
let newPayload = await dbActor.extractSearchablePayloads(from: [scanID])
```

---

### `FileIOActor` (`Core/Data/Database/FileIOActor.swift`)

**Declaration**: `public actor FileIOActor`

**Responsibilities:**

- `writeTemporaryImages(imageDatas:)` — `async` method that writes `[Data]` to
  `URL.documentsDirectory` and returns `[String]` filenames in the same order as
  the input. Writes are parallelised: each image is dispatched to a
  `Task.detached` worker so all files are written concurrently rather than
  sequentially. On a 3-frame scan this reduces wall-clock write time from
  `3 × write_time` to `max(write_times)`. Filenames are UUID-based and
  guaranteed unique.
- `deleteImages(at:)` — deletes files by filename from `documentsDirectory`
  (skips `http://` paths — those are cloud-owned)
- `deleteFiles(at:)` — generalized deletion entry point for absolute file paths,
  `documentsDirectory` filenames, and mixed cleanup lists captured during
  queue/tombstone cleanup.
- `validPaths(from:)` — filters a list of paths/URLs down to those that actually
  exist on disk or are remote URLs

**When to use**: Always use `FileIOActor.shared` — it is a singleton. Never
write or delete scan media from `BackgroundDatabaseActor`, `@MainActor`, or
ad-hoc `Task.detached` blocks. Image writes still use
`writeTemporaryImages(imageDatas:)`; mixed cleanup for images, video files,
thumbnails, extracted audio, and queue-only inference frames should flow through
`deleteFiles(at:)`.

```swift
let savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
await FileIOActor.shared.deleteImages(at: failedPaths)
```

**Why isolated from SwiftData actors**: Disk I/O and SQLite writes contend for
different OS resources. Keeping them on separate actors prevents either from
starving the other.

### `ArchiveManager` (`Core/Data/Images/ArchiveManager.swift`)

**Declaration**: `@MainActor @Observable final class ArchiveManager`

**Responsibilities:**

- Downloads generated dataset archive ZIP files via an isolated media session.
- Reuses local Documents files for repeat archive opens.
- Exposes disk-space diagnostics without owning SwiftData rescue work.

---

## `@ModelActor` Isolation Explained

`@ModelActor` is a Swift macro that:

1. Creates an actor with its own `ModelContext` bound to the provided
   `ModelContainer`.
2. Ensures all methods on the actor use that isolated `modelContext` — never the
   main thread's context.
3. Makes the actor `Sendable`, so it can be passed across task boundaries
   safely.

```swift
@ModelActor
actor BackgroundDatabaseActor {
    func doWork() throws {
        // `modelContext` here is isolated to this actor — safe to call fetch/save/insert
        let records = try modelContext.fetch(FetchDescriptor<LocalScanRecord>())
    }
}
```

**Critical rule**: Never share a `ModelContext` across actors or threads. Always
create a new actor instance with the `ModelContainer` (which IS thread-safe),
not the `ModelContext`.

---

## Ad-hoc vs Singleton: Why Ad-hoc (and When Not)

Most `@ModelActor` actors are created ad-hoc (per operation) rather than stored
as singletons because:

1. **`ModelContext` is not thread-safe** — a singleton actor holding a
   `ModelContext` would need to be the _only_ writer for the duration of its
   operation. Ad-hoc creation gives each operation its own isolated context.
2. **Backpressure is explicit** — if `syncHistoricalScansDown` creates an actor
   and `await`s it, the caller naturally blocks until reconciliation is
   complete. A singleton with a queue would make this implicit and harder to
   reason about.
3. **No state leakage** — each operation starts with a fresh context. There is
   no risk of a previous operation's unflushed changes affecting the next one.

**Exception — long-lived queue actor**: `OfflineQueueManager` stores a single
`BackgroundDatabaseActor` instance in `_queueDbActor` (accessed via
`resolvedQueueDbActor(container:)`). This is intentional:

- **Serialization**: Upload claims/reconciliation and inference transitions
  (`markScansAsUploading`, `markScanAsStaged`, `tryClaimForInference`,
  `transitionScanToStaged`, and both orphan reconcilers) execute on the _same_
  actor executor. Snapshot cutoffs then remain meaningful even if replacement
  work reaches the actor before an older reconciliation call.
- **Performance**: Offline upload bursts can complete multiple scans in rapid
  succession. Reusing one actor avoids repeated `ModelContainer → ModelContext`
  setup cost per completion.
- The shared actor is still safe for concurrent callers — Swift actors serialize
  all calls through their executor automatically.

`FileIOActor` is also a singleton because it has no `ModelContext` and manages a
single shared resource (the Documents directory).

## 2026-07 Collection Projection Rule

Collection upload reads must begin with the changed relationship owners.
`BackgroundDatabaseActor.collectionSyncSnapshots()` fetches the bounded
non-Favorites `ScanCollection` set and prefetches each row's inverse `scans`
relationship. Do not restore the former 200-row `LocalScanRecord.collections`
OFFSET walk: it scanned unrelated records, repeated progressively more SQLite
work, and rebuilt the same memberships on every collection job. The Edge
endpoint reads current `collection_scans` membership with a stable
`(collection_id, scan_id)` keyset cursor and writes only its delta; range/OFFSET
pagination is not part of this upload path. Historical download reconciliation
remains independently page-bounded because it is ingesting remote scan history
rather than projecting an existing local relationship.

## 2026-08 Collection Tombstone Boundary (V51 Current Shape)

The projection and acknowledgement-purge code reads the active
`ScanCollection.isPendingDeletion` Boolean, which survives `ModelContext.save()`
and is mapped to the released `isDeleted` column with
`@Attribute(originalName:)`. `collectionSyncSnapshots()` carries this domain
value without wire naming; `MerianNetworkClient+Collections.swift` maps it to
the unchanged `is_deleted` field. The inbound shield ignores delayed cloud
upserts while the local marker is set. After remote acknowledgement, a fresh
actor refetches by ID plus `isPendingDeletion == true`, so a collection
reactivated during the request cannot be removed by a stale snapshot.

The two checksum-distinct V50 source graphs are frozen under
`Models/Schema/SchemaV50Snapshots.swift` and
`Models/Schema/SchemaV50ReleasedActiveSnapshots.swift`. The active V51 model
retains the mapped source name; each exact V50 graph has a separate source
bridge for the preferred-name ownership migration. Disk-backed fixtures prove
checksum-based selection, true/false values, relationship retention, and V51
relaunch. Keep persistence projection and conditional purge in the actor, wire
mapping in Core Network, and account-lifecycle orchestration in
`CollectionSyncService`; do not synthesize snapshots from transient view state
or hard-delete before server acknowledgement.

## 2026-06 Smart Collection Boundary

Smart default collections are local, auto-managed UI projections. The Scans-root
`@Query` observes `LocalScanRecord` rows once and passes its main-actor model
values to `CollectionsViewModel`; `SmartCollectionSuggester` then derives
private presentation snapshots without performing a database read or creating
`ScanCollection` objects or cloud payloads. Hidden smart collection ids are
stored only in `UserDefaultsKeys.hiddenSmartCollectionIDs`. The Edge sync
contract remains unchanged: only persisted `ScanCollection` records are
serialized to `/sync-collections`, and smart collections do not enter that
payload unless a future explicit conversion feature creates normal collections.

---

## Decision Guide

| Task                                                               | Actor to use                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Save a live scan result                                            | `BackgroundDatabaseActor` (ad-hoc) via `saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:videoFilePaths:mediaTimeline:persistenceFence:)`                                                                                                  |
| Save a text-only, audio-only, or mixed non-visual result           | `BackgroundDatabaseActor` (ad-hoc) via `saveNonVisualRecord(mappedData:observationContextsJSON:audioFilePaths:videoFilePaths:mediaTimeline:persistenceFence:)`                                                                                                                 |
| Select pending uploads or quarantine empty candidates              | `BackgroundDatabaseActor` via `resolvedQueueDbActor`; focused persistence lives in `BackgroundDatabaseActor+QueueSelection.swift`, called only by Media Upload's `UploadSync`                                                                                                  |
| Transition scan state for upload pipeline                          | `BackgroundDatabaseActor` via `resolvedQueueDbActor`; focused persistence lives in `BackgroundDatabaseActor+UploadLifecycle.swift`, with shared actor-isolated retry repair in `+RetryMirror.swift`                                                                            |
| Activate, validate, enumerate, or retire background task ownership | `BackgroundDatabaseActor` via `resolvedQueueDbActor`; durable ownership lives in `BackgroundDatabaseActor+BackgroundAccountWork.swift`, while Background Transfer and Media Upload retain Auth/URLSession orchestration                                                        |
| Claim a scan for inference (`tryClaimForInference`)                | `BackgroundDatabaseActor` via `resolvedQueueDbActor`; durable claim and generation state live in `BackgroundDatabaseActor+InferenceLifecycle.swift`                                                                                                                            |
| Reset scan to `.staged` or schedule a durable inference retry      | `BackgroundDatabaseActor` via `resolvedQueueDbActor`; lifecycle retreat lives in `+InferenceLifecycle.swift`, and retry commits live in `+InferenceRetry.swift`                                                                                                                |
| Process an offline scan after upload                               | `BackgroundInferenceFinalizationService` for response/fence orchestration, a fresh `BackgroundDatabaseActor` for final record persistence, and the main-actor queue path for guarded deletion                                                                                  |
| Startup/ongoing orphan reconciliation                              | `BackgroundDatabaseActor` via `resolvedQueueDbActor`, with upload persistence in `+UploadLifecycle.swift`; inference persistence in `+InferenceLifecycle.swift` adds a pre-enumeration `observedThrough` cutoff plus ordered candidate fences and fresh post-wait revalidation |
| Sync historical scans from cloud                                   | `HistoricalDatabaseActor` (ad-hoc)                                                                                                                                                                                                                                             |
| Calculate all profile data (stats + heatmap + awards)              | `ProfileDatabaseActor.calculateAll()` (ad-hoc)                                                                                                                                                                                                                                 |
| Calculate achievement awards only (post-inference)                 | `ProfileDatabaseActor.calculateAwards()` via `resolvedProfileDbActor` (long-lived)                                                                                                                                                                                             |
| Calculate profile stats (species count, streak)                    | `ProfileDatabaseActor.calculateProfileStats()` (ad-hoc)                                                                                                                                                                                                                        |
| Write scan image files to disk                                     | `FileIOActor.shared`                                                                                                                                                                                                                                                           |
| Delete scan media files from disk                                  | `FileIOActor.shared`                                                                                                                                                                                                                                                           |
| Validate scan media paths                                          | `FileIOActor.shared`                                                                                                                                                                                                                                                           |
| Commit non-biological bulk deletion or retention purge             | Fresh `BackgroundDatabaseActor`; focused persistence lives in `BackgroundDatabaseActor+NonBiologicalRetention.swift`                                                                                                                                                           |
| Project/commit a collection sync                                   | Fresh `BackgroundDatabaseActor` instances through `CollectionSyncService`; Core Network owns the Edge request                                                                                                                                                                  |
| Persist enrichment data after enrich-scan returns                  | `BackgroundDatabaseActor` (ad-hoc)                                                                                                                                                                                                                                             |

## 2026-04 Hardening Updates

- `LocalScanRecordFactory`, called by the focused offline persistence handoff,
  preserves the original capture timestamp for offline inserts. Offline replay
  no longer rewrites chronology to "time of sync", so library ordering, streaks,
  heatmaps, and analytics stay faithful to when the user actually captured the
  scan.
- The non-biological bulk-delete actor path now inserts cloud-deletion
  tombstones and deletes SwiftData rows first, then saves transactionally. Local
  files are purged only after the save succeeds. Each payload ID is re-fetched
  inside the actor, and a row reclassified as biological after the UI snapshot
  is skipped before row, file, or cloud-deletion state is changed.
- Save failures inside bulk deletion now rollback the actor `ModelContext` and
  surface the error to the caller instead of being swallowed with `try?`.
