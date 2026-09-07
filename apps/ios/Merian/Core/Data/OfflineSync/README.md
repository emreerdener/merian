# Offline Sync

`Core/Data/OfflineSync` owns durable scan admission, upload staging, inference
replay, retry scheduling, and background URLSession recovery. It is a Core Data
boundary: feature views may request work through the existing queue APIs, but
must not duplicate queue state or infer completion from transient network state.

The canonical behavioral contract is the
[offline sync pipeline](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md).

## Ownership

- `Models/` contains `Sendable` queue snapshots, media-staging values,
  generation and account-work identities, completion accumulators, and extracted
  scan results. These values do not start work or resolve services.
- `Policies/` contains stateless metadata, task-description, staging, storage,
  retry, and background-inference response/status contracts. Staging and storage
  policy may inspect local files, and retry timing may apply bounded jitter;
  these files have no observable state, actor dependency, or direct network
  work.
- `Coordinators/GenerationTaskRegistry.swift` contains the main-actor,
  compare-before-clear owner for process-local task cancellation. Its mutable
  entries remain private.
- `Persistence/` contains narrow SwiftData lookups for offline jobs, durable
  Field Trip goal-hint reads/deletion, and mapping from queued records to
  `ExtractedScanData`. Queue extensions consume these helpers instead of
  duplicating persistence reads or widening file-local manager details.
- `Services/OfflineQueueManager+Diagnostics.swift` contains diagnostics export
  and event-retention behavior. Export DTOs, redaction policy, and pruning
  helpers remain private to that implementation file.
- `Services/CloudDeletion/`, `Services/Collections/`, and
  `Services/MediaUpload/` contain the live sync orchestration for their named
  work types. Media upload keeps signing, preparation, dispatch, generation
  lifecycle, and completion/finalization separate while preserving the queue's
  existing manager API.
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
  hydration/recovery, and retry/server-poll lifetime. The recovery owner
  resolves the existing network client and scan repository for server-owned
  result hydration and persists the retryable server-status transition. Its
  retry sibling owns general transport-retry preflight/persistence and
  server-poll execution. Completion has no direct network-client or session
  access, while dispatch and watchdog use only the root manager's retained
  background session.
- `Services/BackgroundTransfer/` owns the lock-protected terminal-work tracker,
  Auth-bound lease retention and transition quiescence, relaunched-task owner
  validation/adoption, terminal callback routing, and the nonisolated URLSession
  delegate adapter. Delegate callbacks route immutable snapshots into focused
  main-actor terminal routing; accepted work then enters the existing
  upload/inference processors. The delegate adapter does not own SwiftData
  decisions.
- `OfflineQueueDurability.swift` contains live `OfflineQueueManager` durable
  state mutations and retry orchestration. It consumes the extracted policies;
  it does not own their definitions.

### Production Swift File Inventory

| File                                                                              | Ownership                                                                                                                                                                                          |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Models/OfflineScanPayloads.swift`                                                | Pending-scan snapshots and legacy queued-audio repair values.                                                                                                                                      |
| `Models/MediaStagingModels.swift`                                                 | Staging manifests, media/object-key values, upload-task identity, and exact completion accumulation.                                                                                               |
| `Models/InferenceOwnershipModels.swift`                                           | Inference task and generation identities, foreground persistence fences, funding reservations, and account-work ownership.                                                                         |
| `Models/ExtractedScanData.swift`                                                  | Durable replay snapshots and background processing results.                                                                                                                                        |
| `Policies/OfflineScanJobMetadataContract.swift`                                   | Generation and funding metadata composition that preserves unrelated job metadata.                                                                                                                 |
| `Policies/InferenceURLSessionTaskContract.swift`                                  | Current owner-scoped inference task descriptions and legacy parsing.                                                                                                                               |
| `Policies/MediaStagingContract.swift`                                             | Filename and object-key construction, staging manifests and budgets, upload task descriptions, and compatibility parsing.                                                                          |
| `Policies/OfflineQueueRetryPolicy.swift`                                          | Retry classification, capped base delays, and bounded jitter.                                                                                                                                      |
| `Policies/OfflineQueueStoragePolicy.swift`                                        | File-backed queue admission and available-capacity checks.                                                                                                                                         |
| `Policies/BackgroundInferencePolicy.swift`                                        | Actor-independent response, route, status-recovery, restaging, dispatch-admission, retry-date, and consent-attention decisions.                                                                    |
| `Coordinators/GenerationTaskRegistry.swift`                                       | Compare-before-clear process-local generation task cancellation.                                                                                                                                   |
| `Persistence/ModelContext+FieldTripGoalHints.swift`                               | Durable Field Trip goal-hint reads and deletion shared by replay, recovery, progress acknowledgement, and queue cleanup.                                                                           |
| `Persistence/ModelContext+OfflineJobs.swift`                                      | Shared `ModelContext` lookup and job-creation helpers.                                                                                                                                             |
| `Persistence/OfflineQueueManager+QueuedScanExtraction.swift`                      | Main-actor mapping from a queued SwiftData row to the Sendable inference-replay snapshot.                                                                                                          |
| `Services/OfflineQueueManager+Diagnostics.swift`                                  | Bounded, redacted diagnostics export and event retention.                                                                                                                                          |
| `OfflineJobScheduler.swift`                                                       | Persisted wake restoration and the ordered foreground drain.                                                                                                                                       |
| `OfflineQueueManager.swift`                                                       | Observable queue facade, connectivity/lifecycle state, background-session setup, and retained transfer state.                                                                                      |
| `OfflineQueueManager+AudioQueue.swift`                                            | Single-audio convenience admission into the shared nonvisual queue path.                                                                                                                           |
| `Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift`              | Durable cloud-deletion drain, explicit confirmation, job recovery, and bounded retry persistence.                                                                                                  |
| `Services/Collections/OfflineQueueManager+CollectionSync.swift`                   | Collection dirty-revision tracking, persisted job state, serialized drain, and auth-transition quiescence.                                                                                         |
| `Services/MediaUpload/OfflineQueueManager+UploadSync.swift`                       | Upload eligibility, durable claims, signing, and whole-generation orchestration.                                                                                                                   |
| `Services/MediaUpload/OfflineQueueManager+UploadLifecycle.swift`                  | Generation validation/invalidation plus generation-aware upload latch completion and expiry.                                                                                                       |
| `Services/MediaUpload/OfflineQueueManager+UploadPreparation.swift`                | Legacy queued-audio repair, staging-owner resolution, media preparation, and bounded batch selection.                                                                                              |
| `Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift`                   | Signed-manifest validation, request policy, background task dispatch, and signing-failure recovery.                                                                                                |
| `Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift`                 | Generation-fenced upload callback accumulation, durable staging finalization, legacy-audio repair handoff, and inference dispatch handoff.                                                         |
| `Services/QueueMaintenance/OfflineQueueManager+QueueState.swift`                  | Main-context flushes, automatic-work count projection, and failed-state tombstoning.                                                                                                               |
| `Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift`               | Persistence-fenced explicit deletion, task cancellation, retained-media policy, and failed-record purging.                                                                                         |
| `Services/Funding/OfflineQueueManager+Funding.swift`                              | Funding restoration, deferred-reservation reconciliation, and durable proven-failure release.                                                                                                      |
| `Services/FieldTripProgress/OfflineQueueManager+FieldTripProgress.swift`          | Durable preferred-goal acknowledgement and replay through the milestone coordinator.                                                                                                               |
| `Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift`              | Coalesced uploaded-scan and staged-scan inference replay, status recovery, and dispatch handoff.                                                                                                   |
| `Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift`       | Exact process-local inference generation claim, validation, retirement, and observable sync completion.                                                                                            |
| `Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift`        | Generation-fenced server preflight, hard-bounded request preparation, durable ownership activation, and background download dispatch.                                                              |
| `Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift`      | Generation-fenced task-result processing, compare-before-clear completion ownership and diagnostics, transport-failure handling, final persistence handoff, and private status-probe cancellation. |
| `Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift`        | Generation-fenced delayed status probing, exact background-task inspection/cancellation, and watchdog retirement/retry handoff.                                                                    |
| `Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift`        | Server-status lookup, durable result evidence, retryable-status persistence, durable-wake-first post-save fencing, hydration, cleanup, and server-owned orphan detection.                          |
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
completion, delayed watchdog/task retirement, server-result recovery, and
retry/server-poll lifetime. The completion and watchdog owners preserve actor
isolation, generation fencing, persistence-before-cleanup ordering, queue-state
transitions, and OS-owned background task recovery. The retired queue, sync, and
URLSession aggregates have no replacement catch-all; each live path is owned by
the focused service files above.

## Compatibility

This organization pass preserves the existing public and persistence contracts.
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
- `OfflineQueueSyncArchitectureTests` freezes the seven live sync service files,
  their declaration and import ownership, completion-helper containment,
  responsibility boundaries, mirrored upload-completion tests, retired
  aggregate, and 600-line ceiling.
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
  generation lifecycle, dispatch, completion, watchdog, recovery, and retry
  owners; exact declarations, imports, and cross-file consumers; lack of direct
  network-client/session access in completion; exact task-session containment in
  dispatch/watchdog; post-enumeration probe/generation revalidation;
  generation/persistence/retirement ordering; durable-wake restoration without
  an intervening suspension before post-persistence revalidation in both retry
  paths and before process-local replacement; direct-generation-map containment;
  the 600-line production-file ceiling; and mirrored test ownership.
- `scripts/test-ios-build-and-test-workflow.sh` follows those focused owners: it
  requires the two upload-task reconciliation scans in `UploadSync`, the third
  in `UploadDispatch`, and keeps request policy plus activation-before-resume
  ordering checks with the dispatch owner.
- `CloudDeletionSyncTests`, `CollectionSyncTests`, `LegacyAudioRepairTests`,
  `MediaUploadSyncTests`, and `MediaUploadCompletionTests` mirror the
  corresponding live service owners. The completion suite preserves sibling
  fencing across a whole generation, exact all-key staging commits, token
  ownership, legacy-audio ordering, retry persistence, and stale-generation
  rejection. `OfflineSyncTestSupport` owns their shared isolated-store and
  repository-source fixtures. Creating an isolated store has no singleton side
  effect; each serialized test explicitly installs and restores its manager
  context plus any other mutable singleton state it changes.
- `MediaStagingContractTests`, `MediaStagingBudgetTests`,
  `MediaStagingIdentityTests`, and `MediaStagingCompletionStateTests` cover
  manifests, resource bounds, server-authoritative ownership, and exact
  completion accumulation.
- `InferenceURLSessionTaskContractTests` covers current and legacy inference
  task identities.
- `OfflineQueueRetryPolicyTests` covers retry eligibility, deterministic base
  delay caps, and jitter bounds.
- `GenerationTaskRegistryTests` covers compare-before-clear cancellation.
- `QueuedScanExtractionTests` owns deterministic gallery timestamp, legacy
  visual/audio, sparse identity, and mixed-timeline mapping coverage without
  installing process-wide manager state. The foundation architecture suite
  freezes its test ownership plus the exact mapper and preferred-goal consumer
  allowlists.
- `QueueMaintenanceTests` covers tombstoning, fresh-context automatic-work
  counts, non-actionable failed-record purging, and queue/goal-hint flushes. Its
  cases snapshot and restore both the manager context and published unsynced
  count because maintenance intentionally mutates both.
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
