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
  retry, and background-inference response/status contracts. The storage policy
  is the sole Offline Sync owner of admission, capture-file, and deduplicated
  queued-media byte estimates. Staging and storage policy may inspect local
  files: storage sizing reads file attributes through `FileManager`, and
  capacity checks use URL resource values. Retry timing may apply bounded
  jitter; these files have no observable state, actor dependency, or direct
  network work.
- `Coordinators/GenerationTaskRegistry.swift` contains the main-actor,
  compare-before-clear owner for process-local task cancellation. Its mutable
  entries remain private.
- `historyEnrollmentOwner` retains explicit parent enrollment independently of
  scheduled sync and child preparation. It coalesces exact owner/generation/
  container requests with the same captured review/display baseline and admits
  at most four observations. Auth cancels and awaits it before account-lease
  drain; committed repository deletion cancels only the matching
  parent/container. Durable retry remains in the existing enrollment intent,
  with no timer or implicit History/status admission. See the
  [enrollment owner](../AnalysisHistory/README.md#prepared-native-enrollment).
- `publicationConsentPreparationOwner` retains bounded, exactly scoped
  foreground community-help preflight reads. Account transitions cancel and
  await actual lease release before Auth drains; cancelled or joined callers
  cannot retire another scope's task. This owner has no timer, durable
  publication admission or ordinary UI caller. See the
  [foreground consent owner](../AnalysisHistory/README.md#retained-foreground-consent-preparation).
- `Persistence/` contains narrow throwing SwiftData lookups for offline jobs,
  idempotent cloud-deletion task/job creation, durable Field Trip goal-hint
  reads/deletion, one fresh-context projection of mirrored scan/job retry
  authority, the main-actor detached `QueuedScanContext` route projection with
  its storage estimate, and mapping from queued records to `ExtractedScanData`.
  Queue extensions and feature read boundaries consume these helpers instead of
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
  admission, unique queue-owned media copies, and generation-fenced live
  inference handoff. `onAdmission` delivers the accepted, remapped timeline
  after durable insertion; live inference uses those paths. Failed insertion
  cleans provisional queue copies and preserves caller-owned draft sources. The
  file store remains stateless; manager-owned funding and lifecycle state stay
  in focused extensions. See the
  [durable pipeline](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md)
  and
  [Capture lifecycle](../../../../../../docs/features-and-hardware/29-staged-capture-review.md).
- `Services/Funding/` owns durable funding restoration, reconciliation, proven
  pre-dispatch release, and accepted-inference settlement after exact queue
  deletion. `InferenceFundingReconciliationOwner` privately retains every
  accepted account lease, coalesces trailing reconciliation passes, and exposes
  the cancellation-and-await boundary used by Auth quiescence.
  `Services/FieldTripProgress/` owns durable goal hint acknowledgement and
  replay. `Services/InferenceReplay/` owns coalesced uploaded-scan inference
  reconciliation.
- `Services/BackgroundInference/` owns exact process-generation lifecycle,
  generation-fenced request preparation and background download dispatch,
  accepted task-result and transport-failure completion, delayed status probes,
  exact-generation background-task inspection/cancellation, server-result
  hydration/recovery, retry/server-poll lifetime, and the injected finalization
  handoff from a validated response to a fresh persistence actor. The
  finalization service owns cross-domain ordering but neither SwiftData nor
  response-decoding implementation. The recovery owner resolves the existing
  network client, preserves server ownership, and persists retryable
  server-status transitions. The hydration owner resolves the scan repository,
  promotes a compatible local result, and commits queue cleanup before
  completion effects. When background completion wins an open live presentation,
  `InferenceSessionLifecycleCoordinator` validates the exact presentation owner,
  atomically detaches and cancels that task, and only then publishes recovered
  state. The queue manager never re-reads or cancels `engine.inferenceTask`
  after that facade call because a synchronous observer may already have
  installed a replacement. The reconciliation owner projects server-owned
  inferencing IDs from durable authority, and the retry sibling owns general
  transport-retry preflight/persistence and server-poll execution. Completion
  has no direct network-client or session access, while dispatch and watchdog
  use only the root manager's retained background session.
- `Services/BackgroundTransfer/` owns the lock-protected terminal-work tracker,
  Auth-bound lease retention and transition quiescence, relaunched-task owner
  validation/adoption, terminal callback routing, and the nonisolated URLSession
  delegate adapter. The manager declaration owns URLSession protocol
  conformances; the delegate extension owns the nonisolated callbacks. Delegate
  callbacks route immutable snapshots into focused main-actor terminal routing;
  accepted work then enters the existing upload/inference processors. The
  delegate adapter does not own SwiftData decisions. Inference terminal routes
  accept a scoped Auth lease boundary and finalization/publication dependencies;
  defaults use the existing SDK validation and live completion services. Tests
  can suspend decoding and count publication without replacing queue persistence
  or installing a process-wide authentication override.
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
  `Core/Data/CapturedMedia/CapturedMediaPersistenceService` serializes ordered
  media through injected file-adoption closures.
- `OfflineQueueDurability.swift` contains live `OfflineQueueManager` durable
  state mutations and retry orchestration. It consumes the extracted policies;
  it does not own their definitions. The queue-state sibling owns the retained
  funding/account/scan query for OpenAI permission recovery. Presentation uses
  that query before showing a permission action; durable retry repeats it before
  any explicit-retry mutation. Local queue visibility does not authorize another
  account to resend its media.

### Production Swift File Inventory

| File                                                                              | Ownership                                                                                                                                                                                                                  |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Models/OfflineScanPayloads.swift`                                                | Immutable pending-scan snapshots shared across persistence and queue services.                                                                                                                                             |
| `Models/MediaStagingModels.swift`                                                 | Staging manifests, media/object-key values, upload-task identity, and exact completion accumulation.                                                                                                                       |
| `Models/InferenceOwnershipModels.swift`                                           | Inference task and generation identities, foreground persistence fences, funding reservations, and account-work ownership.                                                                                                 |
| `Models/ExtractedScanData.swift`                                                  | Durable replay snapshots and background processing results.                                                                                                                                                                |
| `Models/CollectionSyncSnapshot.swift`                                             | Immutable local collection desired state passed from persistence to the network adapter.                                                                                                                                   |
| `Policies/OfflineScanJobMetadataContract.swift`                                   | Generation and funding metadata composition that preserves unrelated job metadata.                                                                                                                                         |
| `Policies/InferenceURLSessionTaskContract.swift`                                  | Current owner-scoped inference task descriptions and legacy parsing.                                                                                                                                                       |
| `Policies/MediaStagingContract.swift`                                             | Filename and object-key construction, staging manifests and budgets, upload task descriptions, and compatibility parsing.                                                                                                  |
| `Policies/QueuedInferenceMediaPolicy.swift`                                       | Manifest-only local-WAV admission for durable queue inference; byte validation remains with media staging.                                                                                                                 |
| `Policies/OfflineQueueRetryPolicy.swift`                                          | Retry classification, capped base delays, and bounded jitter.                                                                                                                                                              |
| `Policies/OfflineQueueBatchPolicy.swift`                                          | Pending-row fetch and per-cycle scan dispatch counts.                                                                                                                                                                      |
| `Policies/OfflineQueueStoragePolicy.swift`                                        | File-backed queue admission, available-capacity checks, capture-file sizing, and deduplicated queued-media footprint projection.                                                                                           |
| `Policies/ScanConnectivityFailurePolicy.swift`                                    | Bounded, fail-closed transport classification shared by pre-durability admission and durable inference recovery.                                                                                                           |
| `Policies/BackgroundInferencePolicy.swift`                                        | Actor-independent response, route, status-recovery, restaging, dispatch-admission, retry-date, and consent-attention decisions.                                                                                            |
| `Coordinators/GenerationTaskRegistry.swift`                                       | Compare-before-clear process-local generation task cancellation.                                                                                                                                                           |
| `Persistence/ModelContext+FieldTripGoalHints.swift`                               | Durable Field Trip goal-hint reads and deletion shared by replay, recovery, progress acknowledgement, and queue cleanup.                                                                                                   |
| `Persistence/ModelContext+OfflineJobs.swift`                                      | Shared `ModelContext` job lookup/creation plus idempotent pending cloud-deletion task, job, and event insertion.                                                                                                           |
| `Persistence/OfflineQueueDurableAuthorityReader.swift`                            | One fresh throwing context for mirrored scan/job error codes, retry counts, and required-video authority.                                                                                                                  |
| `Persistence/OfflineQueueManager+QueuedScanExtraction.swift`                      | Live-row projection to the detached queued route context plus throwing main-actor lookup and mapping to the Sendable inference-replay snapshot.                                                                            |
| `Services/OfflineQueueManager+Diagnostics.swift`                                  | Bounded, redacted diagnostics export and event retention.                                                                                                                                                                  |
| `OfflineJobScheduler.swift`                                                       | Persisted wake restoration and the ordered foreground drain.                                                                                                                                                               |
| `OfflineQueueManager.swift`                                                       | Observable queue facade, connectivity/lifecycle state, background-session setup, and retained transfer state.                                                                                                              |
| `OfflineQueueManager+AudioQueue.swift`                                            | Single-audio convenience admission into the shared nonvisual queue path.                                                                                                                                                   |
| `Policies/CloudDeletionIntent.swift`                                              | Versioned requesting-account and origin metadata; invalid/legacy intent never becomes automatic delete authority.                                                                                                          |
| `Services/CloudDeletion/CloudDeletionAccountWork.swift`                           | Account lease for deletion admission/acknowledgement and stable requester capture.                                                                                                                                         |
| `Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift`              | Durable cloud-deletion drain, explicit confirmation, job recovery, and bounded retry persistence.                                                                                                                          |
| `Services/Collections/OfflineQueueManager+CollectionSync.swift`                   | Collection dirty-revision tracking, persisted job state, serialized drain, and auth-transition quiescence.                                                                                                                 |
| `Services/Collections/CollectionSyncService.swift`                                | Injected account-work lease, pre-dispatch and post-response fencing, remote snapshot push, and acknowledgement commit orchestration.                                                                                       |
| `Services/MediaUpload/OfflineQueueManager+UploadSync.swift`                       | Upload eligibility, durable claims, signing, and whole-generation orchestration.                                                                                                                                           |
| `Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift`                  | Generation validation/invalidation plus generation-aware upload latch completion and expiry.                                                                                                                               |
| `Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift`                | Staging-owner resolution, media preparation, invalid-media rejection, and bounded batch selection.                                                                                                                         |
| `Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift`                   | Signed-manifest validation, request policy, background task dispatch, and signing-failure recovery.                                                                                                                        |
| `Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift`                 | Generation-fenced upload callback accumulation, unsupported-audio quarantine, durable staging finalization, and inference dispatch handoff.                                                                                |
| `Services/QueueMaintenance/OfflineQueueManager+QueueState.swift`                  | Main-context flushes, automatic-work count projection, invalid-media quarantine, and failed-state tombstoning.                                                                                                             |
| `Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift`               | Persistence-fenced explicit deletion, task cancellation, retained-media policy, and failed-record purging.                                                                                                                 |
| `Services/Funding/OfflineQueueManager+Funding.swift`                              | Funding restoration, deferred-reservation reconciliation, and durable proven-failure release.                                                                                                                              |
| `Services/Funding/OfflineQueueManager+InferenceSettlement.swift`                  | Exact accepted-result entitlement/usage settlement plus delegation to the retained reconciliation owner.                                                                                                                   |
| `Services/Funding/InferenceFundingReconciliationOwner.swift`                      | Injected single-flight/trailing-pass reconciliation, accepted account-lease retention, and cancellation-and-await teardown.                                                                                                |
| `Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift`          | Durable preferred-goal acknowledgement and replay through the milestone coordinator.                                                                                                                                       |
| `Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift`              | Coalesced uploaded-scan and staged-scan inference replay, unsupported-audio quarantine, status recovery, and dispatch handoff.                                                                                             |
| `Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift`       | Exact process-local inference generation claim, validation, retirement, and observable sync completion.                                                                                                                    |
| `Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift`        | Generation-fenced server preflight, hard-bounded request preparation, durable ownership activation, and background download dispatch.                                                                                      |
| `Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift`      | Generation-fenced task-result processing, compare-before-clear completion ownership and diagnostics, transport-failure handling, final persistence handoff, and private status-probe cancellation.                         |
| `Services/BackgroundInference/BackgroundInferenceFinalizationService.swift`       | Cross-domain generation validation, response preparation, exact response-ID validation, and final persistence handoff through a fresh actor.                                                                               |
| `Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift`        | Generation-fenced delayed status probing, exact background-task inspection/cancellation, and watchdog retirement/retry handoff.                                                                                            |
| `Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift`        | Server-status lookup, durable result evidence, retryable-status persistence, durable-wake-first post-save fencing, and recovery-outcome handling.                                                                          |
| `Services/BackgroundInference/OfflineQueueManager+InferenceHydration.swift`       | Completed-result history hydration, compatibility checks, local promotion, and queue cleanup before notification, milestones, and presentation.                                                                            |
| `Services/BackgroundInference/OfflineQueueManager+InferenceReconciliation.swift`  | Durable-authority projection of server-owned inferencing scan IDs for orphan reconciliation.                                                                                                                               |
| `Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift`           | Compare-before-clear poll-token validation, general transport-retry preflight/persistence, server polling, and retry wake restoration.                                                                                     |
| `Services/CaptureAdmission/DebugAudioComparisonAdmission.swift`                   | Debug simulator-only duplicate-ID lookup across queued and saved scans, before comparison funding or file effects. It persists no comparison profile and changes no schema.                                                |
| `Services/CaptureAdmission/OfflineCaptureFileStore.swift`                         | Unique Documents copies, source-to-accepted-timeline mapping, rollback of provisional copies, and captured-media serialization; consumed only by `CaptureEnqueue`. Size estimation belongs to `OfflineQueueStoragePolicy`. |
| `Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift`              | Funding-gated visual/nonvisual admission, durable record insertion, and post-insert `onAdmission` accepted-timeline handoff.                                                                                               |
| `Services/CaptureAdmission/OfflineQueueManager+DescribeEnqueue.swift`             | Description-only compatibility entry point into nonvisual admission.                                                                                                                                                       |
| `Services/CaptureAdmission/OfflineQueueManager+LiveCaptureLifecycle.swift`        | Deferred-upload release and generation-fenced foreground inference ownership.                                                                                                                                              |
| `Services/BackgroundTransfer/BackgroundURLSessionTerminalWorkTracker.swift`       | Lock-protected terminal callback registration and exactly-once system-completion fencing.                                                                                                                                  |
| `Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift`     | Auth-bound task lease retention, shared rejected-work retirement, durable-before-cancel transition quiescence, and post-commit generation completion.                                                                      |
| `Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift` | Private owner validation/adoption and accepted/rejected upload and inference terminal callback routing.                                                                                                                    |
| `Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift`        | Nonisolated upload/download callback routing and immutable task-property capture.                                                                                                                                          |
| `Services/BackgroundExecution/BackgroundTaskWrapper.swift`                        | Lock-protected UIKit background-execution window used only by durable queue admission, sync, and terminal callback work.                                                                                                   |
| `OfflineQueueDurability.swift`                                                    | Live durable manager mutations and retry orchestration that consume the focused owners.                                                                                                                                    |
| `SyncStateManager.swift`                                                          | UI-observable, generation-aware projection of active upload and inference phases.                                                                                                                                          |

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

`IdentificationReviewSyncService` aborts and logs when an outbox read,
reconciliation read, encoding, or save fails. Fresh mutation contexts disable
autosave, so partially staged authority and dependent-job deletion cannot commit
after an error. Previously saved running or waiting jobs remain retryable.
History-protected legacy review jobs are different: a staged hold, acknowledged
metadata, or the exact server `analysis_bound_review_required` code retains the
original request as `needsAttention` without a retry deadline or legacy
reconciliation. Admission, carry (both endpoints), response commit and failure
reconciliation check fresh history protection within the shared persistence
transaction. Carry saves once through the caller's save boundary and restores
only its staged review/job if that save throws, preserving unrelated context
edits.

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
`Core/Data/CapturedMedia/CapturedMediaPersistenceService` preserves canonical
media order and delegates audio/video adoption through injected `FileIOActor`
closures.

`BackgroundInferenceFinalizationService` holds the per-scan persistence fence
across durable generation validation, shared response preparation, exact
response-ID validation, and the final SwiftData commit. It intentionally does
not await `InferenceProcessingActor` while holding that fence; the stateless
`InferenceResponsePreparationService` supplies the same decode, success
validation, request-appropriate response-ID check, mapping, and immutable
settlement projection to foreground and background completion without an actor
dependency cycle or an account effect. The background path always supplies the
durable scan ID and therefore requires an exact response echo. Queue deletion
remains on the main actor after finalization so open SwiftData queries receive a
real pending deletion and stale work cannot delete a replacement generation.
Only then may the Funding owner apply the settlement and begin its Auth-drained
reconciliation task.

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

- `BackgroundTaskWrapperTests` covers idempotent ending and result-preserving
  execution. `ScanConnectivityFailurePolicyTests` covers eligible offline
  failures, nested transport chains, security-policy vetoes, bounded traversal,
  and the distinct pre- and post-durability classifications.
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
- `OfflineQueuePolicyTests` freezes the queue's 5-scan dispatch and 50-row fetch
  limits plus the 100 MiB free-space reserve and 25 MiB single-payload soft
  ceiling. It also preserves duplicate capture-file accounting, Documents-first
  relative-path resolution (including an empty file), deduplicated queued-media
  sizing, and remote-media exclusion. `MediaStagingContractTests` separately
  keeps signing counts and shared media byte budgets aligned with the executable
  upload-manifest contract.
- `InferenceURLSessionTaskContractTests` covers current and legacy inference
  task identities.
- `OfflineQueueRetryPolicyTests` covers retry eligibility, deterministic base
  delay caps, and jitter bounds.
- `GenerationTaskRegistryTests` covers compare-before-clear cancellation.
- `QueueActorCacheTests` locks replacement of the manager's long-lived queue
  database actor when the exact `ModelContainer` changes. It complements the
  Profile actor cache regression and shares the serialized Offline Queue
  process-state lease.
- `QueuedScanExtractionTests` owns deterministic gallery timestamp, legacy
  visual/audio, sparse identity, mixed-timeline mapping, and complete detached
  queued-route projection without installing process-wide manager state. The
  foundation architecture suite freezes its test ownership plus the exact mapper
  and preferred-goal consumer allowlists.
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
- Direct background completion and server-result recovery invoke Core
  Notifications' `BackgroundScanNotificationService` only after successful queue
  cleanup and before awaiting milestones. Its tests cover alert opt-out,
  unseen-scan suppression, shared deduplication, and scheduling retry;
  `BackgroundInferenceArchitectureTests` locks the two caller admission points.
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

Exact `client_update_required` denials retain queued media and present the
shared app update prompt. Manual retry on the same blocked build reopens that
prompt without resetting attempts or claiming funding. Completed-result
hydration uses `server_result_local_recovery_update_required`, preserving the
completed-owner prefix and stopping the full-history fallback and recovery
polling. Updating the app permits an explicit retry from Scans; it does not
automatically start paid identifications. See the
[compatibility recovery contract](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md).

Cloud deletion's account/provenance quarantine, bounded discovery and wake rules
are defined by the
[canonical deletion contract](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md#2-cloud-deletion-tasking-pendingclouddeletiontask).
New intent uses existing job metadata; ambiguous old tasks remain held and no
whole-history deletion action is enabled.

## Library transition inventory

`Persistence/LibraryMutationInventory.swift` owns the fresh fail-closed
inventory used after Auth closes producer admission.
`Services/LibraryDetailsSyncService` owns immutable owner-bound detail
operations and receipt acknowledgment; it does not equate an empty runnable
queue with durable synchronization. Its drain imports legacy notes before
unrelated detail edits can clear them and re-reads pending batches after
coalesced producer wake-ups. Failed acknowledgments retain their immutable
operation and use the scheduler's five-second fallback when persistence cannot
record another deadline. Earlier queue deadlines take precedence, and a fenced
or cancelled attempt does not consume that retry. The canonical
[guest library transition contract](../../../../../../docs/backend-and-data/21-guest-library-transitions.md)
defines each operation's cleanup/merge boundary and recovery evidence.

Prepared history enrollment uses an exact `observation-history-enrollment:`
namespace in the existing `.future` job store. Active owner-bound intents are
`.needsAttention` without deadlines and count as pending library mutations.
Explicit erasure of held/acknowledged observations retains a metadata-free
`.cancelled` identity fence; ordinary cloud deletion cleanup must not remove it.
The scheduler excludes the entire namespace, including malformed rows. Account
purge clears both states. The
[Analysis History owner](../AnalysisHistory/README.md#prepared-native-enrollment)
defines restoration, acknowledgment and deletion semantics; no worker dispatches
these jobs automatically.

Prepared selection/Undo uses a separate
`observation-history-selection:<lower UUID>` `.future` job: `.needsAttention`
while pending, `.complete` after atomic success/current-state admission, or
`.cancelled` after a validated version-2 rejection/current-state admission. No
state has a deadline. Bare cancellation is not a terminal proof. Pending rows
count as library mutation obligations. The scheduler excludes the namespace even
with damaged status/deadline metadata; no drain is connected. Explicit scan
erasure removes its request/receipt payload while the history enrollment owner
retains the identity-only deletion fence. Account purge removes every row. The
[selection owner](../AnalysisHistory/README.md#prepared-selection-and-undo)
defines explicit replay and revision-bound Undo; generic job retry helpers must
not reopen or replace these records.

## Prepared publication job boundary

`observationPublicationSync` is a raw kind in the existing job store, with no
SwiftData shape change. AnalysisHistory owns strict immutable consent, minimal
terminal receipts and same-ID replay; generic `ensureOfflineJobRecord` must not
reopen these jobs. Direct/bulk scan deletion and acknowledged cloud deletion
remove their scan-qualified namespace atomically with erasure state. The
account-transition inventory counts unfinished work, with the existing settings
summary labeling it Identification sharing.

`ObservationPublicationDeliveryService` recovers status before exact admission
replay under an expected-owner account lease, rechecking after every await.
`ObservationPublicationDeliveryOwner` coalesces callers, retains cancellation
ownership and is awaited at entry to the queue's Auth-quiescence method, before
background transport retirement or any early failure. Connectivity loss cancels
it. `OfflineQueueManager+ObservationPublication` connects the owner to the
scheduler; there is no ordinary UI enqueue caller yet. Discovery validates
owner-bound envelopes and suppresses wakes while that owner is running.
Persisted claim deadlines recover interrupted work; save failures also request a
bounded process-local wake. A fresh claim clears that fallback only after
acquiring the account lease. Account changes suppress another owner's work and
fallback wakes. The retained pass emits one completion callback only after its
actual task exits and releases its lease; joined callers do not emit another
completion. The manager advances `publicationDeliveryGeneration` only when the
captured owner and exact model context remain current, then rearms scheduling.
This prepares local status refresh without polling or an idle Auth lease; it
does not assert that an operation succeeded or remains publicly visible.

Unknown raw kinds and unrecognized `future` namespaces are excluded without
deleting them. Known `library-details:` retries retain their deadlines. This is
a client capability boundary, not rollout activation; older binaries must remain
excluded before admission becomes available.

## Qualified reanalysis queue boundary

V58 persists the work kind and parent/source/owner linkage on
`OfflineQueuedScan`. `OfflineQueueWork` is the routing policy: ordinary work
requires nil linkage; reanalysis requires canonical, distinct
parent/source/child identities and an owner. Missing job metadata cannot change
that classification. Legacy upload, replay, account-work activation, inference,
retry and completion owners reject qualified or damaged rows, while explicit
read/deletion APIs retain access. The ordinary runnable count also excludes
those rows. Late offline completion requires a surviving ordinary row after
taking the finalization lock.

Atomic staging creates held qualified work with its exact request and
child-owned photo paths. Explicit submission uses current owner-bound preflight
and atomically binds a processor plus pristine `pending` execution admission.
Drafts and attempted remediation holds never auto-activate.
`ObservationReanalysisExecutionOwner` retains a single pass and awaits
cancellation through actual lease release;
`ObservationReanalysisExecutionService` processes at most eight due children.
The manager also owns `ObservationReanalysisPreparationOwner`, shared explicitly
with the prepared Capture producer and targeted local file recovery. It reserves
the child before metadata access and retains cancelled work until task exit.
Queue Auth quiescence cancels and awaits this owner before the final account
lease drain. `ObservationReanalysisAdmissionRuntime` now owns its separate
eight-child advisory pass and timer, allowing local file recovery offline while
ready admission requires current consent and network eligibility. Pre-claim
failures get two delayed retries before waiting for an external opportunity;
timer callbacks do not reset that budget. Explicit owner-qualified grant events
rearm only consent holds. Auth also cancels and awaits this runtime and all its
timers. Foreground recovery precedes inference consent checks so stored results
can still recover. Fresh execution separately checks saved-processor consent.

Scheduler dates come from strict owner-qualified snapshots, with due pending,
waiting and interrupted running states. The generic raw-job exclusion remains;
invalid, held and orphan work cannot create wake-only loops. Local read/commit
uncertainty uses a five-second fallback floor, suppressed while a pass is
active. Offline/constrained paths cancel bound execution and ready advisory
admission; local files-pending verification can continue under its own account
and file fences. Auth awaits retained tasks before account lease drain.
Completion wakes permanent-receipt erasure without selection changes. Ordinary
UI submission remains disconnected; server admission owns funding and all
activation gates remain disabled. See the
[V58 contract](../../../../../../docs/backend-and-data/04-database-schema.md#v58-qualified-queued-reanalysis-storage)
for migration invariants and test ownership.

### Parent-bound reanalysis erasure

`ObservationReanalysisErasure` removes exact canonical parent-linked children,
their ingestion jobs and preferred-goal hints inside the parent's local deletion
transaction. Classification and optional job metadata are not erasure authority:
damaged children with a valid parent link are still removed. Direct deletion and
explicit non-biological deletion use this boundary; retention keeps its existing
enrolled-history protection. Save failure rolls back the rows and returns no
cleanup work. A minimal `observationReanalysisErasure` job is committed with
each canonical child removal. It preserves canonical parent/child namespace
ownership after the ingestion metadata disappears and prevents reuse of that
child ID. These local receipts have no retry deadline and are excluded from the
network scheduler. `ObservationReanalysisErasureOwner` now drains them locally
after deletion, at repository configuration and on foreground activation before
consent gates. It requires an exact receipt and fresh child absence under the
same filesystem lock used by preparation, and marks the receipt complete only
after successful erasure. Failures remain pending for a later local opportunity;
malformed or failed receipts cannot starve later pages. Completed receipts
retain the identity tombstone but never reauthorize cleanup. No network or Auth
work is started by this owner.

After commit, `finishReanalysisErasure` refetches child absence and checks the
same model container before cancelling exact transport and process ownership. It
never cancels a surviving row, releases a funding hold or requests remote child
deletion. Parent cloud erasure remains observation-scoped. Private queue file
cleanup is receipt-bound to the entire `ReanalysisQueue/<canonical-child-ID>`
namespace, including interrupted preparation files. Generic observation-media
cleanup no longer receives child paths. No qualified UI producer is enabled yet;
complete-cohort recovery and admitted execution have dedicated automatic owners.
The ordinary UI submission action remains disabled. Full-account cleanup now
drains the local eraser and awaits exclusive-lock namespace purge before
preferences/runtime reset or recovery-marker retirement.

The ordinary permission-resume affordance and automatic failed-queue purge also
require ordinary classification. Held children cannot borrow legacy funding
metadata to enable a permission action, or disappear through automatic cleanup.
The library's standalone queue-card projection excludes all nonordinary rows;
owner/parent-scoped progress remains a separate, not-yet-connected presentation.

## Prepared analysis-bound review delivery

`ObservationAnalysisReviewDeliveryService` accepts one already-persisted exact
intent per call, with an explicitly injected cloud client and mutation
transport. It retains the expected account lease while claiming, submitting or
recovering, and reconciling. No current-state preflight can replace a saved
request: an ambiguous response retries that same operation. The closed transport
requires the caller's claim validator after asynchronous Auth preparation and
immediately before dispatch, so deletion, expiry and claim replacement prevent a
new send.

Acknowledgement saves the immutable receipt before projection and invalidates
the mutation claim. Delivery obtains a fresh receipt-phase claim before paired
reconciliation. All later failure writes use that new claim; received receipts
never dispatch again. Network uncertainty and revision races retain a bounded
retry date. Exact permanent wire errors, invalid immutable state or missing
display provenance hold work without a deadline. Error responses never fabricate
receipt outcomes. The service translates SDK errors into plain code/message
inputs; the policy imports no networking or persistence framework. Cancellation
and account changes leave durable work for its rightful owner; save failures
propagate to bounded fallback scheduling.

`ObservationAnalysisReviewDrain` holds an outer account lease and delivers at
most eight due saved operations sequentially. QueueManager retains its task in
`ObservationAnalysisReviewDeliveryOwner`; cancellation invalidates authority
immediately and retains the slot until actual task exit. Offline and constrained
network transitions cancel it, and both Auth quiescence boundaries await it. The
common scheduler starts this pass without blocking other drains. Current owner,
captured context, token and account lease fence all work. Reviews do not require
inference consent.

Only dedicated validated candidate dates feed review wakes; the raw kind stays
excluded from generic discovery. Interrupted valid running claims wake at their
original expiry. A damaged running claim without its start or fixed expiry
cannot wake or be directly reclaimed. Received waiting work may reconcile
immediately; waiting mutations require their saved retry deadline. Malformed,
held, deleted and wrong-owner work stays inert. Genuine database read errors
propagate instead of silently appearing empty. Read/save uncertainty gets a
five-second process fallback qualified by manager, owner and captured container,
cleared only after valid account work starts. Active retained passes suppress
duplicate timers; actual task exit restores remaining durable deadlines.

Delivery and scheduling do not stage decisions or authorize inference. Ordinary
UI access and all activation gates remain disabled. The
[native persistence contract](../AnalysisHistory/README.md#prepared-analysis-bound-review-persistence)
owns exact requests, receipt claims and atomic projection completion.

## Prepared protected Field Chat delivery

`ProtectedInsightChatDeliveryService` accepts an exact persisted intent and an
explicit initial or same-attempt replay admission. Only a terminal local receipt
can bypass claiming; the HTTP endpoint may dispatch and is never used as a
read-only probe. The injected cloud boundary retains the expected account lease
through request and durable acknowledgement. Response validation and saving use
the original running claim without an expiry or task-cancellation check, while
new dispatch requires live permission. Account, container, child, deletion and
claim replacement still deny settlement. The exact validated response bytes
preserve required nulls through atomic acknowledgement.

Unknown errors and cancellation hold the original claim without a deadline. A
save error first checks whether the exact local receipt committed; it never
reopens that receipt or overwrites another attempt. Held and orphaned work can
only be replayed explicitly with its saved identity. A generic HTTP error does
not prove no server admission and cannot release the observation's unfinished
chat occupancy. That remediation requires a separate durable server proof.

QueueManager retains one `ProtectedInsightChatDeliveryOwner` task until actual
lease release. Connectivity cancellation closes dispatch but preserves the
same-scope settlement predicate for a known answer. Auth invalidation closes
both predicates, and both account-transition quiescence paths await actual exit.
The explicit queue entry injects its service and account identity; there is no
hidden client resolution. Only actual task exit advances the owner/context
qualified refresh generation. UI lifetime never owns this task. Generic
scheduler exclusion remains, with no automatic chat wake, timer or idle Auth
lease. Send UI and all ordinary access remain disabled.
