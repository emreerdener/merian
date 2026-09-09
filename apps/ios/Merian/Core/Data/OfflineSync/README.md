# Offline Sync

`Core/Data/OfflineSync` owns durable scan admission, upload staging, inference
replay, retry scheduling, and background URLSession recovery. It is a Core Data
boundary: feature views may request work through the existing queue APIs, but
must not duplicate queue state or infer completion from transient network state.

The canonical behavioral contract is the
[offline sync pipeline](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md).

## Ownership

- `Models/` contains `Sendable` queue and collection desired-state snapshots,
  media-staging values, generation and account-work identities, completion
  accumulators, and extracted scan results. These values do not start work or
  resolve services.
- `Policies/` contains stateless metadata, task-description, staging, storage,
  retry, and background-inference response/status contracts. Staging and storage
  policy may inspect local files, and retry timing may apply bounded jitter;
  these files have no observable state, actor dependency, or direct network
  work.
- `Coordinators/GenerationTaskRegistry.swift` contains the main-actor,
  compare-before-clear owner for process-local task cancellation. Its mutable
  entries remain private.
- `Persistence/` contains narrow throwing SwiftData lookups for offline jobs,
  durable Field Trip goal-hint reads/deletion, one fresh-context projection of
  mirrored scan/job retry authority, and mapping from queued records to
  `ExtractedScanData`. Queue extensions consume these helpers instead of
  duplicating persistence reads or widening file-local manager details. A
  missing row and an unavailable persistence boundary remain distinct.
- `Services/OfflineQueueManager+Diagnostics.swift` contains diagnostics export
  and event-retention behavior. Export DTOs, redaction policy, and pruning
  helpers remain private to that implementation file.
- `Services/CloudDeletion/`, `Services/Collections/`, and
  `Services/MediaUpload/` contain the live sync orchestration for their named
  work types. Collection sync separates manager-owned durable scheduling,
  dirty-revision, and single-flight state from the initializer-injected
  account-lease transaction. Media upload keeps signing, preparation, dispatch,
  generation lifecycle, and completion/finalization separate while preserving
  the queue's existing manager API.
- `Services/QueueMaintenance/` owns observable queue counts, tombstoning,
  main-context flushes, explicit deletion, and failed-record purging. Deletion
  keeps persistence locking and database-before-file ordering in one file.
- `Services/CaptureAdmission/` owns visual, audio, video, and description queue
  admission, shared capture-file persistence, and generation-fenced live
  inference handoff. The file store is stateless; manager-owned funding and
  lifecycle state remain in focused extensions.
- `Services/Funding/` owns durable funding restoration, reconciliation, and
  proven pre-dispatch release. `Services/FieldTripProgress/` owns durable goal
  hint acknowledgement and replay. `Services/InferenceReplay/` owns coalesced
  uploaded-scan inference reconciliation.
- `Services/BackgroundInference/` owns exact process-generation lifecycle,
  generation-fenced request preparation and background download dispatch,
  accepted task-result and transport-failure completion, delayed status probes,
  exact-generation background-task inspection/cancellation, server-result
  hydration/recovery, retry/server-poll lifetime, and the injected finalization
  handoff from a validated response to a fresh persistence actor. The
  finalization service owns cross-domain ordering but neither SwiftData nor
  response-decoding implementation. The recovery owner resolves the existing
  network client and scan repository for server-owned result hydration and
  persists the retryable server-status transition. The reconciliation owner
  projects server-owned inferencing IDs from durable authority, and the retry
  sibling owns general transport-retry preflight/persistence and server-poll
  execution. Completion has no direct network-client or session access, while
  dispatch and watchdog use only the root manager's retained background session.
- `Services/BackgroundTransfer/` owns the lock-protected terminal-work tracker,
  Auth-bound lease retention and transition quiescence, relaunched-task owner
  validation/adoption, terminal callback routing, and the nonisolated URLSession
  delegate adapter. Delegate callbacks route immutable snapshots into focused
  main-actor terminal routing; accepted work then enters the existing
  upload/inference processors. The delegate adapter does not own SwiftData
  decisions.
- `Core/Data/Database/BackgroundDatabaseActor+QueueSelection.swift` remains the
  actor-isolated persistence owner for pending upload selection and empty-media
  quarantine. Media Upload's `UploadSync` is its only production consumer and
  retains live-transfer exclusions, video-network eligibility, and
  orchestration.
- `Core/Data/Database/BackgroundDatabaseActor+UploadLifecycle.swift` owns only
  pending upload claim, durable manifest staging, and timestamp-fenced orphan
  release. Media Upload and Inference Replay retain network/task inspection and
  orchestration. A focused `BackgroundDatabaseActor` extension keeps the retry
  mirror shared with focused inference persistence actor-isolated without owning
  process state.
- `Core/Data/Database/BackgroundDatabaseActor+BackgroundAccountWork.swift` owns
  only durable background-account activation, exact-owner validation, candidate
  projection, and persistence-before-cancellation retirement. Background
  Transfer retains Auth leases, transition quiescence, terminal routing, and
  URLSession cancellation; Media Upload retains dispatch orchestration.
- `Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift` owns
  only durable inference eligibility, claims, retreats, generation checks,
  telemetry hydration, and timestamp-fenced orphan recovery. Recovery orders and
  acquires every candidate's persistence fence, then rereads eligibility in a
  fresh context before its atomic batch mutation.
  `BackgroundDatabaseActor+InferenceRetry.swift` owns the general and
  server-result recovery retry commits. Background Inference, Inference Replay,
  Media Upload, and Queue Maintenance retain process state, task/network
  inspection, dispatch, scheduling, cancellation, and finalization.
- `Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift` owns
  the existing foreground visual/nonvisual save entry points.
  `BackgroundDatabaseActor+OfflineFinalization.swift` owns durable generation
  validation/adoption and prepared background-result commits, while
  `BackgroundDatabaseActor+ScanRecordSupport.swift` contains their shared
  actor-isolated fetch/insert support. `LocalScanRecordFactory` maps the
  complete record without owning a context, and
  `Core/Data/CapturedMediaPersistenceService` serializes ordered media through
  injected file-adoption closures.
- `OfflineQueueDurability.swift` contains live `OfflineQueueManager` durable
  state mutations and retry orchestration. It consumes the extracted policies;
  it does not own their definitions.

### Production Swift File Inventory

| File                                                                              | Ownership                                                                                                                                                                                          |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Models/OfflineScanPayloads.swift`                                                | Immutable pending-scan snapshots shared across persistence and queue services.                                                                                                                     |
| `Models/MediaStagingModels.swift`                                                 | Staging manifests, media/object-key values, upload-task identity, and exact completion accumulation.                                                                                               |
| `Models/InferenceOwnershipModels.swift`                                           | Inference task and generation identities, foreground persistence fences, funding reservations, and account-work ownership.                                                                         |
| `Models/ExtractedScanData.swift`                                                  | Durable replay snapshots and background processing results.                                                                                                                                        |
| `Models/CollectionSyncSnapshot.swift`                                             | Immutable local collection desired state passed from persistence to the network adapter.                                                                                                           |
| `Policies/OfflineScanJobMetadataContract.swift`                                   | Generation and funding metadata composition that preserves unrelated job metadata.                                                                                                                 |
| `Policies/InferenceURLSessionTaskContract.swift`                                  | Current owner-scoped inference task descriptions and legacy parsing.                                                                                                                               |
| `Policies/MediaStagingContract.swift`                                             | Filename and object-key construction, staging manifests and budgets, upload task descriptions, and compatibility parsing.                                                                          |
| `Policies/QueuedInferenceMediaPolicy.swift`                                       | Manifest-only local-WAV admission for durable queue inference; byte validation remains with media staging.                                                                                         |
| `Policies/OfflineQueueRetryPolicy.swift`                                          | Retry classification, capped base delays, and bounded jitter.                                                                                                                                      |
| `Policies/OfflineQueueStoragePolicy.swift`                                        | File-backed queue admission and available-capacity checks.                                                                                                                                         |
| `Policies/BackgroundInferencePolicy.swift`                                        | Actor-independent response, route, status-recovery, restaging, dispatch-admission, retry-date, and consent-attention decisions.                                                                    |
| `Coordinators/GenerationTaskRegistry.swift`                                       | Compare-before-clear process-local generation task cancellation.                                                                                                                                   |
| `Persistence/ModelContext+FieldTripGoalHints.swift`                               | Durable Field Trip goal-hint reads and deletion shared by replay, recovery, progress acknowledgement, and queue cleanup.                                                                           |
| `Persistence/ModelContext+OfflineJobs.swift`                                      | Shared `ModelContext` lookup and job-creation helpers.                                                                                                                                             |
| `Persistence/OfflineQueueDurableAuthorityReader.swift`                            | One fresh throwing context for mirrored scan/job error codes, retry counts, and required-video authority.                                                                                          |
| `Persistence/OfflineQueueManager+QueuedScanExtraction.swift`                      | Throwing main-actor lookup and mapping from a queued SwiftData row to the Sendable inference-replay snapshot.                                                                                      |
| `Services/OfflineQueueManager+Diagnostics.swift`                                  | Bounded, redacted diagnostics export and event retention.                                                                                                                                          |
| `OfflineJobScheduler.swift`                                                       | Persisted wake restoration and the ordered foreground drain.                                                                                                                                       |
| `OfflineQueueManager.swift`                                                       | Observable queue facade, connectivity/lifecycle state, background-session setup, and retained transfer state.                                                                                      |
| `OfflineQueueManager+AudioQueue.swift`                                            | Single-audio convenience admission into the shared nonvisual queue path.                                                                                                                           |
| `Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift`              | Durable cloud-deletion drain, explicit confirmation, job recovery, and bounded retry persistence.                                                                                                  |
| `Services/Collections/OfflineQueueManager+CollectionSync.swift`                   | Collection dirty-revision tracking, persisted job state, serialized drain, and auth-transition quiescence.                                                                                         |
| `Services/Collections/CollectionSyncService.swift`                                | Injected account-work lease, pre-dispatch and post-response fencing, remote snapshot push, and acknowledgement commit orchestration.                                                               |
| `Services/MediaUpload/OfflineQueueManager+UploadSync.swift`                       | Upload eligibility, durable claims, signing, and whole-generation orchestration.                                                                                                                   |
| `Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift`                  | Generation validation/invalidation plus generation-aware upload latch completion and expiry.                                                                                                       |
| `Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift`                | Staging-owner resolution, media preparation, invalid-media rejection, and bounded batch selection.                                                                                                 |
| `Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift`                   | Signed-manifest validation, request policy, background task dispatch, and signing-failure recovery.                                                                                                |
| `Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift`                 | Generation-fenced upload callback accumulation, unsupported-audio quarantine, durable staging finalization, and inference dispatch handoff.                                                        |
| `Services/QueueMaintenance/OfflineQueueManager+QueueState.swift`                  | Main-context flushes, automatic-work count projection, invalid-media quarantine, and failed-state tombstoning.                                                                                     |
| `Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift`               | Persistence-fenced explicit deletion, task cancellation, retained-media policy, and failed-record purging.                                                                                         |
| `Services/Funding/OfflineQueueManager+Funding.swift`                              | Funding restoration, deferred-reservation reconciliation, and durable proven-failure release.                                                                                                      |
| `Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift`          | Durable preferred-goal acknowledgement and replay through the milestone coordinator.                                                                                                               |
| `Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift`              | Coalesced uploaded-scan and staged-scan inference replay, unsupported-audio quarantine, status recovery, and dispatch handoff.                                                                     |
| `Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift`       | Exact process-local inference generation claim, validation, retirement, and observable sync completion.                                                                                            |
| `Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift`        | Generation-fenced server preflight, hard-bounded request preparation, durable ownership activation, and background download dispatch.                                                              |
| `Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift`      | Generation-fenced task-result processing, compare-before-clear completion ownership and diagnostics, transport-failure handling, final persistence handoff, and private status-probe cancellation. |
| `Services/BackgroundInference/BackgroundInferenceFinalizationService.swift`       | Cross-domain generation validation, response preparation, exact response-ID validation, and final persistence handoff through a fresh actor.                                                       |
| `Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift`        | Generation-fenced delayed status probing, exact background-task inspection/cancellation, and watchdog retirement/retry handoff.                                                                    |
| `Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift`        | Server-status lookup, durable result evidence, retryable-status persistence, durable-wake-first post-save fencing, hydration, and cleanup.                                                         |
| `Services/BackgroundInference/OfflineQueueManager+InferenceReconciliation.swift`  | Durable-authority projection of server-owned inferencing scan IDs for orphan reconciliation.                                                                                                       |
| `Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift`           | Compare-before-clear poll-token validation, general transport-retry preflight/persistence, server polling, and retry wake restoration.                                                             |
| `Services/CaptureAdmission/OfflineCaptureFileStore.swift`                         | Internal stateless size estimation, Documents persistence, rollback, and captured-media serialization, consumed only by `CaptureEnqueue`.                                                          |
| `Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift`              | Funding-gated visual and nonvisual admission plus durable record insertion.                                                                                                                        |
| `Services/CaptureAdmission/OfflineQueueManager+DescribeEnqueue.swift`             | Description-only compatibility entry point into nonvisual admission.                                                                                                                               |
| `Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift`        | Deferred-upload release and generation-fenced foreground inference ownership.                                                                                                                      |
| `Services/BackgroundTransfer/BackgroundURLSessionTerminalWorkTracker.swift`       | Lock-protected terminal callback registration and exactly-once system-completion fencing.                                                                                                          |
| `Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift`     | Auth-bound task lease retention, shared rejected-work retirement, durable-before-cancel transition quiescence, and post-commit generation completion.                                              |
| `Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift` | Private owner validation/adoption and accepted/rejected upload and inference terminal callback routing.                                                                                            |
| `Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift`        | Nonisolated upload/download callback routing and immutable task-property capture.                                                                                                                  |
| `OfflineQueueDurability.swift`                                                    | Live durable manager mutations and retry orchestration that consume the focused owners.                                                                                                            |
| `SyncStateManager.swift`                                                          | UI-observable, generation-aware projection of active upload and inference phases.                                                                                                                  |

The root manager retains stored observable/process state and background-session
creation because Swift stored properties must remain on the primary type. Media
upload callback finalization now has a focused owner, and its generation fences
stay with upload lifecycle. Background inference similarly separates stateless
policy, process-generation lifecycle, request dispatch, accepted task
completion, delayed watchdog/task retirement, server-result recovery,
durable-authority orphan reconciliation, and retry/server-poll lifetime. The
completion and watchdog owners preserve actor isolation, generation fencing,
persistence-before-cleanup ordering, queue-state transitions, and OS-owned
background task recovery. The retired queue, sync, and URLSession aggregates
have no replacement catch-all; each live path is owned by the focused service
files above.

### Durable Read Invariant

SwiftData absence is a valid domain result only after a successful read. No
production Swift file under `Core/Data` may use `try?` with `fetch` or
`fetchCount`; read failures log privately and abort the associated mutation or
dispatch instead of manufacturing an empty queue, job, collection, or scan.
`OfflineQueueDurableAuthorityReader` reads the mirrored scan/job error markers,
attempt counts, and video count through one fresh throwing context. A missing
manager context is an error, not an empty authority.

Queued-scan extraction follows the same rule. Background inference turns an
unreadable snapshot into its durable retry path. Upload completion restores the
persisted scheduler wake and waits for a later reconciliation. Only a successful
lookup that proves the row is absent may take the already-cleaned or
missing-metadata path. Field Trip goal-hint reads/deletion and final scan-record
support also throw, keeping optional data distinct from unavailable storage.

Durable writes precede external work. Collection transport starts only after the
`.running` job claim saves; a job-read failure remains conservatively pending
but is not runnable. Cloud deletion preloads its task/job pairs before claiming
work, and a result-side job read or mutation failure rolls back and retains the
pending deletion task. These rules tighten failure handling without changing
queue states, endpoint calls, payloads, schemas, or normal success behavior.

Collection persistence and transport deliberately remain outside this folder's
service owner. `Core/Data/Database/BackgroundDatabaseActor+CollectionSync.swift`
projects the non-Favorites relationship snapshot and purges only rows still
marked for deletion in a fresh context.
`Core/Network/Endpoints/MerianNetworkClient+Collections.swift` privately maps
that domain snapshot to the existing snake-case request and owns the
authenticated HTTP call. A classified `401` returns to the durable job instead
of starting Auth recovery inside the collection task: Auth recovery drains that
same task and outer account-work lease, so nested recovery would otherwise form
a self-wait. The bounded retry remains pending and can dispatch after Auth is
stable again.

Pending upload selection also remains outside the service owner.
`Core/Data/Database/BackgroundDatabaseActor+QueueSelection.swift` pages through
all pending rows, applies the existing retry, process-local exclusion, video,
and funding gates, and returns a bounded media-less quarantine set without
letting it consume the runnable-media limit. Empty-media quarantine revalidates
the persisted row and commits scan, any existing matching job, and event
attention state atomically. Funding lookup fails selection closed, while a scan,
job, or save failure rolls back quarantine rather than committing partial state.
`Services/MediaUpload/OfflineQueueManager+UploadSync.swift` supplies transient
policy and is the sole caller; neither owner duplicates the other's state.

The next persistence boundary is similarly focused.
`Core/Data/Database/BackgroundDatabaseActor+UploadLifecycle.swift` owns
`.pending → .uploading`, exact-manifest `.uploading → .staged`, and
task-snapshot-fenced orphan `.uploading → .pending` mutations. Media Upload
retains signing, dispatch, callback accumulation, and network policy; Inference
Replay retains the task enumeration that supplies orphan-recovery evidence.
Matching-job read failures roll back the full claim or orphan-recovery batch,
while genuinely absent legacy job rows remain supported.
`BackgroundDatabaseActor+RetryMirror.swift` may be consumed only by this
extension and the focused inference lifecycle/retry owners that repair the same
durable scan/job retry mirror; its method remains database-actor isolated.

Durable background-account state has its own persistence boundary.
`Core/Data/Database/BackgroundDatabaseActor+BackgroundAccountWork.swift` commits
the exact Auth UUID, generation, and upload/inference phase before a background
task resumes; validates callbacks against both that marker and queue state;
projects transition-retirement candidates; and returns owned runnable work to
pending while clearing source-account staging keys before transport
cancellation. All scan and job reads are throwing and fail closed. The extension
retains private diagnostics when persistence fails and creates a genuinely
absent legacy ingestion job in the same activation save. It neither resolves
Auth nor enumerates or cancels URLSession tasks; those effects stay with
Background Transfer and Media Upload.

Durable inference state has two focused persistence boundaries.
`Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift` owns
server-owned eligibility reads, the staged/inferencing transition pair,
background and live durable-generation validation, telemetry writes, and
timestamp-fenced orphan release.
`Core/Data/Database/BackgroundDatabaseActor+InferenceRetry.swift` owns both
generation-aware retry commits and shares the actor-isolated retry-mirror repair
with upload lifecycle. Every scan/job lookup is throwing and fail closed. A
genuinely absent legacy ingestion job remains supported, while a fetch failure
cannot create a replacement row. Orphan recovery acquires candidate fences in
stable order, rereads current durable eligibility after waiting, and preloads
every matching job before its first mutation so newer terminal work wins and one
failed read aborts the batch. Both async mutation owners release their per-scan
persistence fence when already cancelled. The extensions do not own
process-generation state, scheduling, task enumeration/cancellation, request
dispatch, networking, file I/O, Auth, or UI.

Scan finalization has a similarly narrow boundary.
`Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift` owns the
existing foreground visual/nonvisual save entry points, while
`BackgroundDatabaseActor+OfflineFinalization.swift` owns durable generation
validation/adoption and prepared background-result commits.
`BackgroundDatabaseActor+ScanRecordSupport.swift` contains their shared
actor-isolated fetch/insert support, and `LocalScanRecordFactory` maps the
complete record without owning a context. The stateless
`Core/Data/CapturedMediaPersistenceService` preserves canonical media order and
delegates audio/video adoption through injected `FileIOActor` closures.

`BackgroundInferenceFinalizationService` holds the per-scan persistence fence
across durable generation validation, shared response preparation, exact
response-ID validation, and the final SwiftData commit. It intentionally does
not await `InferenceProcessingActor` while holding that fence; the stateless
`InferenceResponsePreparationService` supplies the same decode, success
validation, mapping, and entitlement policy to foreground and background
completion without an actor dependency cycle. Queue deletion remains on the main
actor after finalization so open SwiftData queries receive a real pending
deletion and stale work cannot delete a replacement generation.

Queued inference audio is intentionally fail-closed. Supported iOS capture and
video-companion producers persist local WAV files, and pending upload preflight
rejects any other format before signing. `QueuedInferenceMediaPolicy` owns the
storage-aware manifest check instead of placing queue behavior on the persisted
media model. Documents storage accepts only relative, scheme- and host-free
paths without parent traversal. Absolute storage accepts a slash-rooted path or
a credential-free local `file://` URL whose host is absent or `localhost`;
remote storage is never queue-inference input even when its suffix is `.wav`. A
surviving background upload callback checks the snapshot before staging, while
staged replay quarantines unsupported audio through the shared needs-attention
transition. If either durable authority already records a completed cloud
result, quarantine preserves that marker and its funding evidence so manual
retry resumes result hydration rather than provider dispatch.
`BackgroundDatabaseActor.tryClaimForInference` repeats the format fence as the
final persistence boundary. The queue does not transcode persisted rows;
historical publication playback and restore remain separate from inference
admission.

## Compatibility

This organization pass preserves the existing public and persistence contracts.
A collection-specific follow-up also closes an existing acknowledgement race:
the service revalidates its exact account lease after snapshot extraction and
after the remote response, then uses a fresh database actor that deletes only
rows still marked `isPendingDeletion`. A local reactivation during the request
therefore survives, while the dirty revision schedules the newer desired state.
A post-extraction audit also closes one existing fail-closed state mismatch: if
retiring a newly created but unresumed inference task exhausts its durable
retries, the process-local inference generation now remains active alongside the
durable `.inferencing` owner. The task and generation are retired only after the
queue row is safely returned to pending. A later Auth sweep or rejected terminal
callback that commits retirement also closes the exact observable generation
immediately; the Auth sweep does so before transport cancellation. Normal
dispatch, completion, and retry behavior is unchanged.

The request-preparation timeout race now reports its explicit timeout outcome
and returns without waiting for the losing preparation task to cooperatively
observe cancellation. The losing task is cancelled and any late value is
ignored. Caller cancellation remains a `CancellationError`; a timeout cannot
nondeterministically surface as cancellation merely because preparation reacts
to cancellation first.

The retryable server-status path also treats durable scheduling and optional
process-local acceleration as separate commitments. After the background actor
persists the retry, Recovery restores the central persisted wake first. Only a
non-cancelled caller that still satisfies network policy and owns its inference
generation plus any supplied server-poll token may then replace the
process-local server poll. A stale poll can therefore stop its own local
continuation without stranding the durable retry or displacing a newer poll
owner.

The general inference-retry path applies the same durable-first rule. Once its
background actor commits the retry date, Retry restores the central wake before
checking task cancellation, poll-token ownership, or inference-generation
ownership. Those process-local fences still control only the optional in-memory
retry task, so cancellation or owner replacement cannot strand committed work.

The pass does not change:

- Swift type names or call-site signatures;
- JSON keys, endpoint payloads, or upload-task description formats;
- the SwiftData schema, stored columns, queue states, or retry semantics;
- authentication, funding, feature-flag, lifecycle, or navigation behavior.

New background uploads use
`upload_v2|{ownerUUID}|{scanId}|{uploadIndex}|{syncGeneration}|{serverObjectKey}`;
new inference downloads use
`inference_v3|{ownerUUID}|{syncGeneration}|{scanId}`. Parsers continue to accept
the documented structured and underscore upload formats plus `inference_v2` and
`inference_` formats so OS-owned tasks created by an older app build remain
recoverable.

## Verification

Focused tests mirror the extracted owners:

- `OfflineSyncFoundationArchitectureTests` freezes the complete relocated
  declaration inventory, exact focused-file and framework-import inventory,
  dependency direction, private mutable state, and the 600-line ceiling for this
  foundation slice.
- `OfflineQueueSyncArchitectureTests` freezes the eight live sync service files,
  their declaration and import ownership, completion-helper containment,
  responsibility boundaries, collection/cloud durable-claim-before-dispatch
  ordering, cloud job mutation before task removal, mirrored collection-sync and
  upload-completion tests, retired aggregates, and 600-line ceiling.
- `OfflineQueueMaintenanceArchitectureTests` freezes the two maintenance service
  owners, shared persistence lookup owners, private destructive helpers,
  persistence-lock ordering, database-before-file deletion, exact framework
  imports, and the 600-line ceiling.
- `OfflineQueueAdmissionArchitectureTests` freezes the seven admission, funding,
  Field Trip progress, and inference-replay files; their exact
  declaration/import ownership; private helper containment; the exact
  `OfflineCaptureFileStore` consumer allowlist; durable-before-dispatch
  ordering; the retired queue aggregate; mirrored test type/display identities
  and process-state traits; and the 600-line ceiling.
- `BackgroundTransferArchitectureTests` freezes the four background-transfer
  files, exact declarations/imports, private tracker and terminal-validation
  state, transfer-state and rejected-retirement consumer allowlists, synchronous
  registration-before-handoff, durable-before-cancel quiescence, terminal
  retirement-before-invalidation ordering, failed-retirement generation
  preservation, exact inference-completion consumers, mirrored test ownership,
  and the 600-line ceiling.
- `BackgroundInferenceArchitectureTests` freezes the stateless policy,
  generation lifecycle, dispatch, completion, finalization, watchdog, recovery,
  reconciliation, and retry owners; exact declarations, imports, and cross-file
  consumers; lack of direct network-client/session access in completion; exact
  task-session containment in dispatch/watchdog; post-enumeration
  probe/generation revalidation; generation/persistence/retirement ordering;
  durable-wake restoration without an intervening suspension before
  post-persistence revalidation in both retry paths and before process-local
  replacement; direct-generation-map containment; the 600-line production-file
  ceiling; and mirrored test ownership.
- `CoreDataIntegrationArchitectureTests` freezes the exact bounded
  `BackgroundDatabaseActor` source/import inventory, its declaration-only root,
  the Core Data-wide ban on silently discarded SwiftData fetch failures, the
  one-context durable-authority projection and its bounded consumers, and
  throwing absence/failure boundaries across scan finalization, goal hints,
  queue maintenance, cloud deletion, and historical reconciliation.
- `CapturedMediaPersistenceServiceTests` covers explicit/default timeline order,
  invalid-item filtering, and standalone-audio source identity without touching
  Documents storage. Its generic-constrained compile guard also requires the
  complete finalization response/result graph to remain `Sendable`.
  `ScanFinalizationArchitectureTests` freezes the declaration-only actor
  aggregate, exact declaration ownership, dependency direction, coordinator
  containment, shared foreground/background response preparation, explicit
  checked-sendability declarations, rejection of an unchecked prepared-response
  conformance, the no-finalizer-to-processing-actor boundary, and focused
  production-file ceilings. `BackgroundDatabaseActorTests` retains the
  end-to-end persistence and dual-path race cases.
- `scripts/test-ios-build-and-test-workflow.sh` follows those focused owners: it
  requires the two upload-task reconciliation scans in `UploadSync`, the third
  in `UploadDispatch`, and keeps request policy plus activation-before-resume
  ordering checks with the dispatch owner. It also preserves the complete
  automatic-network admission coverage while assigning eight references to
  inference Recovery and the moved ninth reference to Reconciliation.
- `CloudDeletionSyncTests`, `CollectionSyncTests`, `MediaUploadSyncTests`, and
  `MediaUploadCompletionTests` mirror the corresponding live service owners. The
  completion suite preserves sibling fencing across a whole generation, exact
  all-key staging commits, token ownership, unsupported-audio quarantine before
  durable staging, retry persistence, and stale-generation rejection.
  `OfflineSyncTestSupport` owns their shared isolated-store and
  repository-source fixtures. Creating an isolated store has no singleton side
  effect; each serialized test explicitly installs and restores its manager
  context plus any other mutable singleton state it changes.
  `CollectionSyncTests` additionally covers bounded relationship projection,
  unavailable and stale account leases, pre-dispatch and post-response fencing,
  remote failure, confirmed purge, in-flight local reactivation, dirty-revision
  retention, and retry exhaustion. `CollectionSyncEndpointTests` owns the exact
  path, snake-case body, timeout, and body-ignoring 2xx transport mapping.
- `QueueSelectionPersistenceTests` covers actor-isolated pending selection,
  blocked-row paging, stable funding priority, and state-bound atomic quarantine
  with and without an existing matching job. `QueueSelectionArchitectureTests`
  freezes its focused production and test owners, fail-closed SwiftData reads,
  shared offline-job lookup, upload-sync consumer allowlist, dependency
  exclusions, and 600-line ceilings.
- `UploadLifecyclePersistenceTests` covers pending-only upload claims, durable
  staging outcomes, retry-marker preservation, orphaned scan/job release, and
  task-snapshot fencing. `UploadLifecycleArchitectureTests` freezes its focused
  actor extension and outcome type, exact Media Upload/Inference Replay
  consumers, fail-closed matching-job reads, actor-isolated retry-mirror support
  use, mirrored tests, dependency exclusions, and production/test size ceilings.
- `BackgroundAccountWorkPersistenceTests` covers exact upload-owner retirement,
  rejected inference-dispatch requeue, the staged upload-callback race, and
  activation-time ingestion-job creation for legacy scans without one.
  `BackgroundAccountWorkArchitectureTests` freezes its focused actor extension,
  exact Background Transfer and Media Upload consumers, throwing SwiftData
  reads, balanced per-scan persistence fences, mirrored tests, dependency
  exclusions, and focused/residual size ceilings.
- `InferenceLifecyclePersistenceTests` covers inference claims and retreats,
  background/live generation checks, timestamp-fenced orphan recovery, post-wait
  terminal-state revalidation, missing-job compatibility, and cancellation fence
  release. `InferenceRetryPersistenceTests` covers monotonic retry authority,
  cloud-complete veto, media restaging, server-result evidence, missing-job
  compatibility for both retry modes, and cancellation fence release.
  `InferencePersistenceArchitectureTests` freezes sole declaration/test
  ownership, exact production consumers, throwing SwiftData reads, orphan batch
  preload, private helpers, balanced fences, dependency exclusions, focused
  source/test ceilings, and the residual actor's non-growth cap.
- `QueuedInferenceMediaPolicyTests`, `MediaStagingContractTests`,
  `MediaStagingBudgetTests`, `MediaStagingIdentityTests`, and
  `MediaStagingCompletionStateTests` cover storage-aware local-WAV admission,
  manifests, resource bounds, server-authoritative ownership, and exact
  completion accumulation.
- `InferenceURLSessionTaskContractTests` covers current and legacy inference
  task identities.
- `OfflineQueueRetryPolicyTests` covers retry eligibility, deterministic base
  delay caps, and jitter bounds.
- `GenerationTaskRegistryTests` covers compare-before-clear cancellation.
- `QueuedScanExtractionTests` owns deterministic gallery timestamp, legacy
  visual/audio, sparse identity, and mixed-timeline mapping without installing
  process-wide manager state. The foundation architecture suite freezes its test
  ownership plus the exact mapper and preferred-goal consumer allowlists.
- `QueueMaintenanceTests` covers tombstoning, fresh-context automatic-work
  counts, invalid-media quarantine, completed-result/funding preservation,
  non-actionable failed-record purging, and queue/goal-hint flushes. Its cases
  snapshot and restore both the manager context and published unsynced count
  because maintenance intentionally mutates both.
- `CaptureAdmissionTests`, `LiveCaptureLifecycleTests`, and
  `InferenceReplayTests` mirror queue admission, media ordering and identity,
  foreground generation fencing, and replay coalescing. Admission cases
  explicitly install and restore the shared manager context and observable queue
  state; their isolated-store helper has no singleton side effect. All three
  suites are serialized and lease `.offlineQueueManager` through
  `sharedProcessState`; the architecture suite freezes those traits together
  with each suite's exact Swift type and display name so XCResult selectors and
  process-wide fixture isolation cannot silently drift.
- `BackgroundTransferOwnershipTests` rehomes terminal tracker, delegate
  registration, Auth quiescence, relaunched-lease adoption, and bounded durable
  retirement coverage from the aggregate manager suite. Its tracker cases verify
  multi-token and multi-waiter drain, exactly-once completion-handler
  consumption, duplicate-finish tolerance, and the idle fast path through
  observable behavior rather than production test hooks. The suite remains
  serialized and leases `.offlineQueueManager` process state.
- `BackgroundInferenceLifecycleTests` covers exact/idempotent claims, retired
  generation rejection, legacy generation adoption, and stale-completion fencing
  under the shared offline-queue lease. `BackgroundInferenceDispatchTests`
  covers preparation success, a hard timeout that does not await a
  non-cooperative losing operation, caller-cancellation identity,
  suspension-point revalidation, and durable retirement ordering.
  `BackgroundInferencePolicyTests` covers route and response classification,
  restaging decisions, server-status recovery, and dispatch admission.
- `BackgroundInferenceCompletionTests` covers exact cancellation retirement and
  probe cleanup, stale transport-failure fencing, and stale result-file cleanup
  while preserving a replacement active generation, completion lock, dispatch
  timestamp, and status-probe owner. It is serialized and leases
  `.offlineQueueManager` process state.
- `BackgroundInferenceWatchdogTests` covers compare-before-clear probe
  replacement, current and legacy parsed task identity with terminal-state
  rejection, post-task-enumeration probe/generation revalidation, and
  recovery/cancellation/retirement/retry source ordering. It is serialized and
  leases `.offlineQueueManager` process state.
- `BackgroundInferenceRecoveryTests` covers durable server ownership before
  local hydration and terminal server-result contract mismatch without a retry
  loop. It is serialized, leases `.offlineQueueManager` process state, and
  cancels any shared scheduler wake it arms before restoring the manager
  context.
- `BackgroundInferenceRetryTests` covers durable server-failure marker recovery
  when queue-row state drifts, cancellation-independent wake restoration for a
  committed retry, and stale poll-token rejection after owner replacement. It is
  serialized and leases `.offlineQueueManager` process state.
- `SyncStateManagerTests` covers generation-aware upload, inference, finalizing,
  and forced-idle presentation state.

`OfflineQueueManagerTests` and the background database and endpoint suites
continue to own the remaining integrated upload/task-result, persistence,
networking, and replay behavior. `OfflineSyncTests` retains lightweight
lock-release, admission, weather-gate, and terminal-file-error regression
examples; it is not integration evidence. Focused policy and source-architecture
tests supplement rather than replace the integrated suites. Run the
[canonical live inference and offline-queue matrix](../../../../../../docs/development-guides/08-testing-strategy.md#live-inference-requestresult-verification)
against freshly built products, then run the complete `merianTests` target.
