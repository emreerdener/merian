# Core Data

The `Data` directory manages the local persistence and offline-first data
pipeline.

`Database/BackgroundDatabaseActor.swift` is now the declaration-only
`@ModelActor` owner. Focused sibling extensions own every bounded persistence
surface without changing the actor's live scan entry points.
`BackgroundDatabaseActor+CollectionSync.swift` owns collection snapshot and
acknowledgement persistence, `BackgroundDatabaseActor+QueueSelection.swift` owns
pending upload selection and empty-media quarantine, and
`BackgroundDatabaseActor+UploadLifecycle.swift` owns upload claim, staging, and
orphan-release persistence.
`BackgroundDatabaseActor+BackgroundAccountWork.swift` owns durable
background-account activation, validation, candidate selection, and retirement.
`BackgroundDatabaseActor+InferenceLifecycle.swift` owns durable inference
eligibility, claims, retreats, generation validation, telemetry hydration, and
orphan recovery, including ordered per-scan fencing and a fresh durable
eligibility read after any fence wait.
`BackgroundDatabaseActor+InferenceRetry.swift` owns the two generation-fenced
retry commits. `BackgroundDatabaseActor+RetryMirror.swift` keeps the
retry-mirror mutation actor-isolated while sharing it across upload and
inference persistence owners.
`BackgroundDatabaseActor+LiveScanPersistence.swift` owns visual and nonvisual
foreground record commits; `BackgroundDatabaseActor+OfflineFinalization.swift`
owns generation validation/adoption and prepared background-result commits; and
`BackgroundDatabaseActor+ScanRecordSupport.swift` contains only their shared
actor-isolated fetch/insert support. `LocalScanRecordFactory` owns value
mapping, while `CapturedMediaPersistenceService` owns ordered media
serialization and delegates file adoption through narrow injected closures.
`BackgroundDatabaseActor+SpeciesMetadata.swift` owns Wikipedia/reference-image
patches, inference enrichment, lookalike-cache recovery, and identification
review persistence. `BackgroundDatabaseActor+NonBiologicalRetention.swift` owns
the non-biological erasure values, bounded retention purge, and atomic
record/cloud-tombstone commit. Actor extensions perform no networking,
authentication, direct file I/O, or UI work.

`Database/HistoricalSync/` separates cloud-history request/DTO values,
row-isolated decoding, the sole live Auth/PostgREST adapter, and actor-isolated
SwiftData reconciliation. `ScanRepository` retains only ordering, pagination,
account fencing, and app-event orchestration. See the
[Historical Sync README](Database/HistoricalSync/README.md) for the layer
invariants and canonical contract links.

`Images/` separates loader orchestration from decode admission, URL/retry
policy, local recovery evidence, and the owner-authenticated cloud-repair
service. A focused actor rebuilds legacy mappings after startup in bounded,
throwing, cancellation-aware pages, with strong evidence completed before
timestamp fallback. The mapping registry also enforces that priority when
bounded Historical Sync, Scan Library, and post-startup callers interleave, and
it admits or evicts each multi-image timestamp group atomically. Only live
dependency adapters resolve network or app-event effects; the recovery layer
remains read-only with respect to cloud metadata. See the
[Core Data Images README](Images/README.md) for ownership and verification
details.

## Purpose

This area acts as the source of truth for app data. It encompasses SwiftData
configurations, the layered Historical Sync boundary for cloud reconciliation,
and the `OfflineQueuedScan` persistence mechanism. It ensures that data remains
durable even when inference fails or network connectivity is absent.

`SpeciesPreferences/` owns the smaller cross-feature preferred-common-name data
boundary. Its repository performs account-scoped SwiftData CRUD and fail-closed
legacy cleanup; its policy owns normalization, resource limits, and timestamp
conflicts; its focused local-recovery service repairs interrupted
SwiftData/UserDefaults mutations; and its injected client plus main-actor
coordinator isolate the existing `user_species_preferences` PostgREST
reconciliation. Only the live client resolves Supabase. The coordinator
generation-acknowledges tombstones and refetches local state after an upsert
suspension before applying the earlier remote page. See the
[Species Preferences README](SpeciesPreferences/README.md) for ownership and
verification details.

Accepted account deletion routes through `ScanRepository.purgeAllData`, which
explicitly deletes every model in `CurrentSchema` and then invokes the verified
`Core/Preferences/AccountScopedPreferences` cleanup. A schema-inventory test
fails when a newly active model is not added to that erasure boundary. Only
after both durable steps succeed does the repository invoke the injected
`AccountScopedRuntimeState` reset for observable settings, gamification, app
badge, and RAM image-cache projections. This synchronous boundary deletes rows;
it does not replace the SQLite store file or traverse unreferenced files in the
app container. Any broader disk-erasure policy needs a separate inventory of
file owners and must not infer ownership from a broad directory alone.

V50 introduced `OfflineQueuedScanGoalHint`, a scan-keyed companion that stores
the optional standard-outing and checklist-item IDs selected in a qualifying
live Capture. Keeping this separate preserved the released V49 queue entity. The
current V51 schema retains that companion through
`ActiveOfflineQueuedScanGoalHint` and keeps the collection tombstone
`ScanCollection.isPendingDeletion` mapped to the released `isDeleted` column
while the Core Network adapter continues to emit the `is_deleted` wire field.
V51 separately makes preferred species names account-scoped.
Foreground/background completion read the same goal hint. Successful queue
finalization preserves it as a durable progress outbox until acknowledgement;
explicit cancellation and terminal orphan repair remove it. Persistent Insight
contribution cards are server-backed and are intentionally not cached in
SwiftData.

Authenticated historical reconciliation treats a nonempty `scans.captured_media`
projection as authoritative only when domain mapping yields a usable image or
video. New canonical manifests contain every image, standalone audio clip,
playback video, and description in submitted order. The reader also dual-reads
durable image/audio/video URL columns and `user_observation_context` for older,
empty, device-only, or incomplete rows, so an audio-plus-description scan cannot
become an empty visual placeholder. Those compatibility columns carry no
cross-modal positions: missing audio URLs are appended in stored-array order,
followed by the stored context, and they are supplemental rather than deletion
authority. Standalone audio carries the same `sourceIndex` in local and cloud
`capturedMediaJSON`; reconciliation replaces a local clip only when that unique
identity or its exact path matches. Unindexed legacy/restore media is merged
conservatively rather than assigned by ordinal guess, so ambiguous recovery can
retain an alias but cannot delete the wrong recording. `capturedMediaJSON`
remains the primary read source, so the expanded JSON union does not change the
SwiftData schema.

`CapturedMediaWireDTOs.swift` is the generated PostgREST boundary for Captured
Media Wire V1. It maps into the existing `SerializedMediaItem` domain only after
strict wrapper, URL, and size validation. Its compatibility decoder accepts
legacy aliases, ignores retired description timestamps without attempting a date
decode, and safely drops legacy `localFile` references from server rows so the
durable URL columns can supply the media instead. Strict V1 requires at least
one item, while the compatibility decoder treats historical `[]` as a missing
manifest. Historical pages decode rows independently, quarantining malformed
rows while reconciling valid neighbors. Targeted completed-result hydration
returns a typed contract mismatch; the queue immediately pauses that scan as
needs-attention while preserving the cloud-complete no-redispatch fence.

Local historical reconciliation is a throwing persistence boundary. A failed
scan, collection, membership, or save operation rolls back pending work and
stops the current sync; targeted completed-result hydration reports a transient
failure so the durable queue retries instead of claiming success. Cancellation
is handled separately from storage failure and rolls back before collection
deletion, preventing a partially traversed cloud collection page from deleting
unprocessed local rows. The inserted-record count includes only rows that passed
timestamp validation and reached the successful save path.

The historical scan projection also selects the existing `is_biological_subject`
column. New local records use that value when it is present, and existing
records reconcile it only from a non-null cloud value; older rows that predate
the field retain the compatibility default of biological. This prevents current
non-biological audio from being re-imported as biological without adding a
SwiftData field, schema version, or migration, and the repository never infers
the value from stored reasoning.

Each accepted historical scan row also projects its owner-readable
`explore_posts(id, unshared_at)` relationship. After the account work lease is
revalidated, `ScanRepository` reconciles active post IDs into the existing
per-scan Explore share-state cache and removes stale markers for rows proven
unshared. The relation key is required but nullable: explicit `null` proves that
the scan has no post, while an omitted key quarantines that row instead of
clearing a valid cache entry. Each request captures a reconciliation revision; a
later local share, unshare, deletion, purge, or newer history response fences
out stale results. When that projection changes, a batched
`exploreShareStateReconciled` invalidation is published as soon as reconciled
scan pages are durable, including when a later page or collection request fails.
The Scans filter and local **Explore posts** smart collection can therefore
recover server-backed publication intent after reinstall without issuing one
request per scan or waiting for unrelated collection sync.

Live inference and offline replay build audio upload paths, `audioMediaItems`,
observation contexts, video paths, and `ownerMediaTimeline` from one
chronological projection. `audioInputIndex` names the matching raw upload
position while `sourceIndex` names the standalone clip. The Edge Function may
delete an inference-only companion only after validating the complete owner
timeline; legacy or incomplete metadata retains audio conservatively. Queue
replay omits the authoritative timeline when an older visual row lacks aligned
`visualMediaItemsJSON`, or when a partial snapshot has sparse standalone-audio
identities; it preserves any stored `sourceIndex` instead of renumbering it.

## Scan replacement and deletion

Reanalysis first uses Core AI's `InferenceScanReplacement` to verify a durable
replacement and save the original's tags, collections, and field notes. A
confidence-zero/no-record result, missing replacement, or failed metadata save
keeps the original. Only then does `ScanRepository.eradicateScan` commit local
deletion and the cloud-deletion outbox. It returns an optional task covering its
post-commit file cleanup and immediate cloud attempt; callers may ignore that
handle without delaying local deletion, while tests await it before restoring
their shared queue context. A nil handle means the local deletion commit failed.
The task is not proof of remote deletion: failed cloud work remains durably
queued. See the
[deletion contract](../../../../../docs/backend-and-data/01-offline-sync-pipeline.md#1-transactional-destruction-scanrepositoryeradicatescan).

Network status and deletion calls live in
[`Core/Network/Endpoints/MerianNetworkClient+ScanLifecycle.swift`](../Network/Endpoints/MerianNetworkClient+ScanLifecycle.swift).
Its decoder requires explicit cloud-deletion confirmation; endpoint extraction
does not move the local commit, pending-task persistence, drain latch, or capped
retry scheduling out of Core Data. The
[scan lifecycle matrix](../Network/README.md#scan-lifecycle-verification) joins
endpoint checks with the existing queue and deletion-service tests.

## Offline Scan Durability Boundary

The [Offline Sync README](OfflineSync/README.md) defines the focused ownership
inside this boundary. Sendable values live under `OfflineSync/Models`, stateless
metadata/staging/storage/retry and background-inference policy under
`OfflineSync/Policies`, process-local task ownership under
`OfflineSync/Coordinators`, shared SwiftData lookups plus queued-record
extraction under `OfflineSync/Persistence`, and diagnostics under
`OfflineSync/Services`. The same service boundary gives cloud deletion,
collection sync, media-upload preparation/dispatch/completion, queue
maintenance, capture admission, funding, Field Trip progress, inference replay,
background inference, and background transfer focused subdirectories. Queue
maintenance separates count/tombstone/flush state from persistence-fenced
deletion. Capture admission separates stateless file staging from manager-owned
admission and foreground lifecycle state. The internal `OfflineCaptureFileStore`
may be referenced only by its own declaration and the capture-enqueue owner.
Background Transfer separates lock-protected terminal tracking, Auth quiescence,
private terminal owner validation/adoption, terminal routing, and nonisolated
delegate routing from the remaining result pipeline. Background Inference
separates exact process-generation lifecycle, generation-fenced request
dispatch, accepted task completion, response-to-persistence finalization,
generation-fenced watchdog probing/task retirement, server-result recovery plus
retryable-status persistence, durable-authority orphan reconciliation, and
general transport-retry/server-poll lifetime into focused owners. Reusable
offline-job and Field Trip goal hint lookups, the one-context mirrored
queue-authority reader, and the throwing queue-to-inference snapshot mapper
remain in `Persistence`. Upload completion owns callback accumulation and
durable staging handoff; generation validation/invalidation stays in upload
lifecycle. `OfflineQueueDurability.swift` retains only the live manager
mutations that consume those owners.

Collection sync specifically keeps job/revision/single-flight state in the
manager extension and moves the snapshot/request/commit transaction into the
initializer-injected `CollectionSyncService`. The immutable desired-state value
lives under `OfflineSync/Models`; persistence projection and commit-time
tombstone revalidation live in
`Database/BackgroundDatabaseActor+CollectionSync.swift`; and Core Network alone
owns the private snake-case request DTO and authenticated endpoint call. The
service checks the same account-work lease before dispatch and after the remote
response, then uses a fresh actor so a locally reactivated collection cannot be
purged from a stale snapshot. A classified `401` remains a durable job failure:
starting Auth recovery inside collection sync would recursively await the same
task and outer lease during Auth quiescence.

`OfflineSyncFoundationArchitectureTests`, `OfflineQueueSyncArchitectureTests`,
`OfflineQueueMaintenanceArchitectureTests`, and
`OfflineQueueAdmissionArchitectureTests`, plus
`BackgroundTransferArchitectureTests` and
`BackgroundInferenceArchitectureTests`, freeze relocated declarations, exact
focused-file/framework-import inventories, private mutable state, ordering,
responsibility boundaries, retired aggregates, mirrored test ownership, and
focused 600-line ceilings. Background Inference additionally freezes shared
response preparation without a finalization-to-processing-actor hop. The
foundation and sync suites additionally freeze queued scan extraction and
upload-completion test ownership plus exact mapper/goal-hint consumer
allowlists. The admission suite additionally freezes the three mirrored test
types and display names, their serialized/shared-process-state traits, and the
exact file-store consumer allowlist. The background-transfer suite freezes
delegate conformance, tracker/lease-state and rejected-retirement consumer
allowlists, the exact inference-completion consumers, registration and
quiescence ordering, and private terminal validation in the focused routing
owner. It prevents failed durable retirement from finishing an undispatched
inference generation ahead of its SwiftData owner and requires a later
successful retirement to close that observable generation immediately; Auth
quiescence does so before cancellation. The background-inference suite freezes
its policy, lifecycle, dispatch, completion, and watchdog owners; exact
result/failure, task-inspection, probe-registry, and generation consumers; lack
of direct network-client/session access in completion; and
persistence-before-cleanup plus exact-generation retirement ordering. It also
freezes both inference retry paths' durable save, immediate central wake
restoration without an intervening suspension, post-save
cancellation/poll/generation revalidation, and optional process-local poll/retry
replacement in that order. `QueueMaintenanceTests` covers state transitions,
fresh automatic-work counts, purging, and flush behavior;
`SyncStateManagerTests` retains generation-aware upload, inference, finalizing,
and forced-idle projection coverage. Queue-maintenance and capture-admission
cases snapshot and restore the shared manager state they mutate; creating an
isolated store alone does not mutate a singleton field. `CaptureAdmissionTests`,
`LiveCaptureLifecycleTests`, and `InferenceReplayTests` mirror the newly focused
owners. `BackgroundTransferOwnershipTests` mirrors terminal tracking, delegate
routing, Auth quiescence, relaunched lease adoption, and durable retirement. The
background-inference lifecycle, dispatch, and policy suites mirror exact
generation fencing, a hard preparation deadline that does not await a
non-cooperative loser, caller-cancellation identity, durable dispatch ordering,
and actor-independent response/status decisions. The completion suite mirrors
exact cancellation retirement, stale callback fencing, and task-result file
cleanup without disturbing a replacement generation. The watchdog suite mirrors
exact probe replacement, parsed open-task identity, exact probe/generation
revalidation after both task-enumeration suspensions, and
recovery/cancellation/retirement/retry ordering. The recovery and retry suites
mirror durable result evidence, terminal contract mismatch handling,
replacement-token fencing, durable marker recovery, and cancellation-independent
restoration of a committed general-retry wake.

`OfflineJobScheduler` owns persisted wake timing and the ordered drain: funding
reconciliation, pending uploads, inference replay, Field trip progress, cloud
deletion, then collections. Its small `DrainOperations` value keeps the six
existing live manager calls together; fresh scheduler instances can inject inert
effects without replacing global queue behavior. Mirrored
`MerianTests/Core/Data/OfflineSync/OfflineJobSchedulerTests.swift` verifies that
future work is armed before a suspended drain, every asynchronous effect is
awaited in order, and an offline drain cancels only its own wake without
dispatching. These are scheduler dispatch-policy proofs, not real
provider-replay tests.

Admission is durable state, not a read of an entitlement boolean. Before this
layer writes capture files or allows foreground inference, `EntitlementManager`
claims an account/scan-keyed `ScanFundingReservation`. The corresponding
`OfflineJobRecord.metadataJSON` can contain both `funding_reservation` and
`inference_generation`; property-specific helpers preserve the other value
during generation handoff or funding reclassification. Relaunch restores
nonterminal claims and conservatively treats active pre-protocol-3 jobs without
funding metadata as potential complimentary blockers.

A proven pre-dispatch local failure first removes the funding payload and saves
`funding_reservation_released: true` while preserving unrelated metadata. If
that save fails, the reservation remains in memory and capacity stays blocked.
An explicit retry of a released job derives exact Flash eligibility from the
persisted capture timeline and makes a new synchronous funding claim before it
clears needs-attention. Ambiguous network outcomes never use this local release
path.

A completed background PUT is evidence for one upload member, not permission to
start analysis. The generation accumulator must equal the duplicate-free exact
expected key set; missing, extra, or duplicate manifest members fail closed.
Sanitized filename and object-key collisions are rejected before signing or
upload. Every structured media file must also have a positive nonzero size on
both iOS and Edge before signing. `BackgroundDatabaseActor.markScanAsStaged`
then persists those keys, normally resets upload retry state, updates the queue
job, and transitions `.uploading → .staged` in one save. Only `.staged` after
that commit—or a serialized owner with the same staged manifest—may proceed
toward an inference claim. The one exception is an exact scheduled
server-failure retry. Its `server_retryable_failure` marker, attempt count, and
last attempt are mirrored on `OfflineQueuedScan` and the corresponding
`OfflineJobRecord`. Successful re-stage preserves them; every serialized
claim/retry/staging transition first repairs a drifted copy from the surviving
marker and monotonic maximum. A cloud-complete recovery marker has higher
authority than either retry copy. A transient signer or PUT failure while
performing that re-stage also preserves the machine marker and increments from
the maximum committed attempt; its precise failure remains in the queue event
stream.

Inference audio has an additional durable admission boundary. A newly enqueued
audio reference must be a local, structurally valid PCM/Float WAV within the
inference byte budget before funding is claimed or a queue row is persisted;
upload preparation repeats the same validation before signing. Source and
release-history review found no supported iOS producer of compressed queue
audio: standalone capture and video companions have always used WAV, and the
watchOS M4A sender has no iOS receiver. The speculative conversion state machine
was therefore removed.

Unexpected non-WAV or remote audio references still fail closed. Pending upload
preflight rejects them before signing, staged replay and surviving upload
callbacks move them to the existing needs-attention boundary, and
`tryClaimForInference` independently refuses them as a final defense.
`QueuedInferenceMediaPolicy` owns this manifest-only storage/format decision.
Documents references must be relative, scheme- and host-free, and free of parent
traversal. Absolute references must be slash-rooted paths or credential-free
local `file://` URLs with no host other than `localhost`; remote references are
unsupported even with a `.wav` suffix. An ordinary row receives
`queued_media_invalid`; a known completed cloud result retains its
higher-authority recovery marker and funding evidence so retry can hydrate that
result without a second provider request. Historical playback and explicit
`scan_share_restore` publication recovery may still use M4A; those contracts do
not make M4A valid queue inference input. The V49 `queueSchemaRepairGeneration`
field remains in the V51 model as inert persisted compatibility storage and is
not read or mutated by the current queue runtime.

Fetch, job-read, manifest-mismatch, or save failure returns a retry-required
outcome before inference. Once the callback token releases, timestamp-fenced
orphan reconciliation restarts signing for a still-uploading row; a staged row
replays only its persisted keys. A missing, failed, or external-import row is
discarded and never resurrected.

Upload policy is checked both before and immediately after the serialized
`.pending → .uploading` claim. If connectivity, Low Data Mode, live ownership,
or video cellular eligibility changed during the actor suspension, the exact
scan claim and its durable running job return to runnable state atomically
without spending retry budget. Signed members for one scan are preflighted as a
complete manifest and all resumed in one main-actor turn or not at all; any
no-task claim is released through the same timestamp- and URLSession-fenced
recovery.

The replay/orphan driver is process-local single-flight. Library, scheduler,
reconnect, and URLSession completion wakes share one active reconciliation.
Wakes received while it is running coalesce into at most one trailing pass, so
state changes are not dropped without allowing duplicate status probes, orphan
transitions, retry-budget inflation, or Library log storms. Upload/inference
claims revalidate `queueNeedsAttention` and the persisted retry deadline inside
the serialized actor immediately before mutation. Orphan reconciliation excludes
needs-attention rows entirely; only explicit retry may clear that fence and
return them to automatic work. Pending selection is ordered by timestamp and
stable ID and pages through future-dated retries, process-local live-upload
deferrals, videos blocked on the current network, and media-less legacy rows
until it either fills the runnable-media limit or exhausts the eligible set.
Media-less rows consume a separate bounded quarantine budget, so old locally
blocked or malformed rows cannot starve newer runnable work; an explicit
user-forced video remains eligible. The worker rechecks those process-local
inputs after the actor read and refetches if they changed. Global
server-ownership probes likewise exclude needs-attention inferencing rows
through the serialized queue actor, so a cached main-context fault or unrelated
recovery wake cannot resume their polling. Network monitoring treats
constrained/expensive policy changes as first-class transitions even while
reachability stays satisfied. Low Data Mode disarms automatic drains and
constrained background-session access; returning to an eligible path wakes
durable work. The uploader repeats its policy check after Auth/filesystem
preparation and immediately before the actor claim, preventing a stale WiFi
snapshot from dispatching video after a cellular handoff. These path values are
observable: the Scan Library includes them in its refresh-task identity and
applies the same online/constrained/large-upload rules before polling or kicking
workers. Offline, constrained, and cellular-blocked pending video rows therefore
stay visible without producing a refresh/log loop. Final background PUT requests
always reject constrained transport; non-forced video scans reject expensive
transport for every manifest member, and dispatch repeats the live-policy check
immediately before resume. A WiFi-started mixed-media video scan therefore
cannot partially continue over cellular unless the user explicitly authorized
that scan. Inference preparation and every delayed queue-owned status/poll/retry
or completed-owner history-recovery entry recheck the same
online-and-unconstrained predicate after suspension. Entering Low Data Mode
mid-preparation cannot start another automatic foreground request or consume
retry budget; durable orphan reconciliation resumes the row on the next eligible
path. The upload packer scans the full bounded candidate window rather than only
its first batch-size rows, continues past a non-fitting row when later work can
fit, and quarantines a malformed `.pending` row with no upload media as visible
needs-attention. The quarantine rechecks state, attention, and all canonical
upload paths in the serialized actor before committing the failed state and
job/event ledger together.

The first `failed_retryable` status observation writes that marker and
increments retry accounting atomically. After its persisted delay, only that
exact marker lets the next generation-fenced status preflight reclaim the
backend generation and dispatch Identify; all marker-free, active, completed,
manual, and terminal states still refuse duplicate inference. Marker and attempt
reads use a fresh `ModelContext`, consult both durable copies, and use the
monotonic maximum so a migrated-store snapshot cannot hide or roll back a
background-actor commit. Exhaustion keeps the row for manual attention and
cancels polling instead of cycling through signing, PUT, and status
indefinitely. An explicit user retry resets the bounded automatic counter under
the same scan UUID before re-entering the atomic claim path. This matters for
description-only staged work, which has no successful upload transition to reset
the counter. A known cloud-complete result is the exception: manual retry
preserves its owner-result marker and cannot re-enable provider dispatch.

`ScanQueueState.isManualRetryEligible` is only the shared value-presentation
baseline used by queued grid and Insight snapshots. It does not claim queue
ownership: retry mutation code must re-fetch the current row, revalidate its
attention/deadline/state contract, and then enter the existing serialized claim
path.

`OfflineQueueRetryPolicy` separates scan analysis from maintenance work. Scan
analysis uses a five-second minimum, jittered exponential growth, a 30-second
ordinary local maximum, and ten automatic attempts. A safe HTTP `Retry-After` or
status `retry_after` is an authoritative minimum and may exceed 30 seconds
within the existing server-directed safety bound. Maintenance and reconciliation
retain the 15-minute maximum; each maintenance workflow continues to own its
existing attempt or no-expiration contract. Existing stored deadlines are read
as written; this policy introduces no SwiftData migration.

The foreground generation and the open Insight's local presentation generation
serve different purposes. Connectivity loss may synchronously retire durable
provider ownership so the queue can recover, but that retirement must not erase
the exact still-current sheet's authority to acknowledge the handoff as **Queued
for later**. Conversely, local presentation authority never permits a retired
task to persist a provider result, delete queue state, record transport failure,
or overwrite a newer/completed presentation. The current joined-source repair
and its remaining exact-SHA/device acceptance gates are tracked in the
[live scan connectivity handoff incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).

Consent-policy rejection is outside that retry-budget state machine. Foreground
request preparation and background response classification treat only exact
handler-owned `403 ai_consent_required` as `.consentRequired`. The queue records
the original row as needs-attention while retaining every media file, invokes
the account-scoped consent fence, and returns without a retry deadline or
automatic redispatch. A generic `403` remains ordinary needs-attention. Manual
retry becomes meaningful only after Ready records fresh head-anchored evidence
and `ConsentManager` completes another authoritative cloud proof under the same
account; the stable scan UUID is retained throughout.

After foreground or background result persistence, inference-driven queue
deletion writes the scan job's `.complete` status, clears transient errors,
inserts the completed event, and removes the exact guarded queue row in one
main-context save. Explicit user/system deletion instead records `.cancelled`. A
crash or save failure therefore cannot leave successful inference durably
classified as cancellation, and local file cleanup runs only after this save. If
crash replay reaches the same proven generation after the queue row is gone, an
already-complete job is accepted without appending a duplicate completion event.

## Queue Selection Persistence

`Database/BackgroundDatabaseActor+QueueSelection.swift` is the focused
persistence owner for pending upload selection and empty-media quarantine. Its
actor and method signatures are unchanged. Selection pages through the complete
pending set so delayed, locally excluded, video-blocked, or media-less rows
cannot starve newer runnable work. It preserves stable oldest-first order within
the existing funding tiers, excludes deferred Flash work, and returns a
separately bounded set of media-less candidates for quarantine. An unreadable
funding-job query fails selection closed instead of treating every row as
legacy/unfunded work.

Quarantine re-fetches each candidate inside the actor and mutates only a row
that is still pending, not already marked for attention, and still has no local
image, audio, or video. The scan failure, any existing matching offline-job
attention state, and diagnostic event commit in one context save; a scan, job,
or save failure rolls back the batch. The extension reuses the shared
`ModelContext.fetchOfflineJob` lookup and performs no networking,
authentication, file I/O, or UI work.

`OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift` is the
only production consumer and retains live-transfer exclusions, network policy,
and upload orchestration. `QueueSelectionPersistenceTests` covers actor
isolation, state filtering, full-set paging, funding priority, and atomic
state-bound quarantine with both existing and legacy-missing matching jobs.
`QueueSelectionArchitectureTests` freezes sole declaration and test ownership,
the consumer allowlist, shared-helper use, narrow imports and dependencies, and
the 600-line focused-file ceilings.

## Upload Lifecycle Persistence

`Database/BackgroundDatabaseActor+UploadLifecycle.swift` is the focused
persistence owner for upload claim, staging commit, and orphaned-upload release.
Its actor method signatures and callers are unchanged. `markScansAsUploading`
revalidates pending state, attention, and retry deadlines before committing the
claim; `markScanAsStaged` requires the exact upload source state or an already
advanced matching manifest; and `reconcileOrphanedUploadingScans` retains the
existing task-snapshot cutoff and optional candidate fence. A matching-job read
failure aborts and rolls back the complete claim or orphan-recovery batch;
genuinely absent legacy job rows remain supported.

The owner performs no signing, endpoint access, URLSession enumeration, file
I/O, authentication, or UI work. Media Upload retains preparation, dispatch,
callback accumulation, live-network policy, and task recovery. Inference Replay
retains the cross-transfer orphan scan that wakes durable work.
`BackgroundDatabaseActor+RetryMirror.swift` keeps the mirrored scan/job attempt
and server-recovery marker mutation on the database actor; an architecture
allowlist limits its production consumers to the focused inference lifecycle,
inference retry, and upload-lifecycle extensions.

`UploadLifecyclePersistenceTests` owns the ten rehomed actor regressions for
claim source-state filtering, staging outcomes and retry-marker preservation,
durable-job orphan release, empty active-task recovery, and timestamp/candidate
fencing. `UploadLifecycleArchitectureTests` freezes declaration, outcome,
consumer, throwing job-lookup, actor-isolated retry support, dependency,
test-ownership, 600-line focused-file, and 1,900-line residual-aggregate
boundaries.

## Background Account Work Persistence

`Database/BackgroundDatabaseActor+BackgroundAccountWork.swift` is the focused
persistence owner for exact Auth-account and generation ownership of background
upload and inference tasks. Its actor method signatures and callers are
unchanged. Activation commits the owner marker before task resume; current-owner
validation joins that marker to the required queue state; candidate selection
projects the durable work that must be quiesced; and retirement commits pending
state, clears source-account staging keys, and removes the marker before
transport cancellation.

Every scan/job lookup is throwing and fail-closed. An unreadable record is not
treated as an absent legacy row, persistence failures retain private diagnostic
context, and a stale expected owner cannot mutate newer durable work. A
genuinely absent legacy ingestion job is created in the same activation save as
its owner marker. The owner performs no Auth SDK work, networking, URLSession
enumeration or cancellation, file I/O, or UI work. Background Transfer retains
account leases, transition quiescence, terminal routing, and cancellation; Media
Upload retains dispatch and its signing-failure retirement call site.

`BackgroundAccountWorkPersistenceTests` contains the three rehomed actor
regressions for upload retirement, rejected inference dispatch, and the staged
upload-callback race, plus the missing-job compatibility case that proves a
legacy scan still receives a durable ingestion job during activation.
`BackgroundAccountWorkArchitectureTests` freezes sole declaration and test
ownership, exact Offline Sync consumers, throwing reads, balanced per-scan
persistence fences, dependency exclusions, a 400-line focused owner/test
ceiling, and a 1,600-line residual-aggregate non-growth cap.

## Inference Lifecycle and Retry Persistence

`Database/BackgroundDatabaseActor+InferenceLifecycle.swift` is the focused
persistence owner for server-owned eligibility reads, `.staged → .inferencing`
claims, `.inferencing → .staged` retreats, background/live durable-generation
validation, timestamp-fenced orphan recovery, and pre-dispatch telemetry
hydration. `Database/BackgroundDatabaseActor+InferenceRetry.swift` owns both the
general inference retry and completed-server-result hydration retry commits.
Offline Sync call-site spelling is unchanged; orphan reconciliation is now
explicitly asynchronous so it can wait for the shared persistence fences.

Every scan/job decision now uses a throwing SwiftData read and fails closed with
private diagnostics. A genuinely absent legacy ingestion job is still created
for an unfenced claim or relaunch retry, but a read failure can no longer
masquerade as absence. Orphan recovery acquires candidate fences in stable ID
order, rereads durable eligibility in a fresh context after waiting, and loads
every matching job before mutating any row. Newer deletion, completion, or retry
work therefore wins, while one unreadable job still aborts the complete batch
rather than committing split scan/job state. Both serialized mutation owners
release `ScanInferencePersistenceCoordinator` after cancellation as well as
normal completion. They perform no networking, Auth, URLSession inspection, file
I/O, or UI work; Background Inference, Inference Replay, Media Upload, and Queue
Maintenance retain those orchestration responsibilities.

`InferenceLifecyclePersistenceTests` owns the rehomed claim, retreat,
generation-validation, and orphan-reconciliation regressions—including a
fence-wait overlap—plus missing-job compatibility and cancellation fence
release. `InferenceRetryPersistenceTests` owns monotonic mirror repair,
cloud-complete veto, media-restaging, server-result evidence, both missing-job
compatibility paths, and cancellation fence release.
`InferencePersistenceArchitectureTests` freezes sole declaration and test
ownership, exact production consumers, throwing reads, batch preload, private
helpers, balanced persistence fences, dependency exclusions, respective 600- and
400-line focused owner ceilings, 600-line behavior suites, and a 1,000-line
residual actor cap.

## Scan Finalization Persistence

`Database/BackgroundDatabaseActor+LiveScanPersistence.swift` preserves the
existing `saveLiveScanRecord` and `saveNonVisualRecord` entry points while
sharing their fence, media, replacement, cancellation, rollback, and commit
flow. `BackgroundDatabaseActor+OfflineFinalization.swift` accepts only prepared
domain data and owns the durable generation validation/adoption plus final
background record commit. Shared SwiftData reads and insert/replace operations
remain actor-isolated in `BackgroundDatabaseActor+ScanRecordSupport.swift`;
complete model construction is centralized in the stateless
`LocalScanRecordFactory`.

`CapturedMediaPersistenceService` preserves canonical timeline order and
standalone-audio source identity. Its live dependencies delegate audio/video
adoption to `FileIOActor`; deterministic tests inject closures and never touch
Documents storage. Background URLSession completion is coordinated by
`OfflineSync/Services/BackgroundInference/BackgroundInferenceFinalizationService`.
That service holds the per-scan persistence fence across durable generation
validation, shared response preparation, and the SwiftData commit, but it never
awaits `InferenceProcessingActor` while holding the fence. Completion supplies a
fresh persistence actor so a failed save cannot contaminate the long-lived queue
state-machine context. The stateless
`Core/AI/Inference/Services/InferenceResponsePreparationService` gives live and
background completion one decode, success-validation, mapping, and entitlement
reconciliation policy without creating another actor or singleton with mutable
state. Its prepared value, the complete `SpeciesData` graph, and the foreground
and background result carriers use compiler-checked `Sendable` conformances.

`CapturedMediaPersistenceServiceTests` covers explicit/default timeline order,
invalid-item filtering, source-index preservation, and the generic-constrained
compile check for the complete finalization response/result graph.
`ScanFinalizationArchitectureTests` freezes declaration ownership, narrow
dependencies, coordinator containment, shared response preparation, the
no-finalizer-to-processing-actor dependency, explicit checked-sendability
declarations, rejection of an unchecked prepared-response conformance, and
focused production-file ceilings. Existing end-to-end finalization behavior
remains in `BackgroundDatabaseActorTests`. No SwiftData schema, DTO, endpoint,
queue-state, media-order, or UI contract changes in this slice.

## Core Data Integration Guardrails

The Core Data-wide integration audit makes absence and storage failure distinct
across this directory. Production `fetch` and `fetchCount` calls under
`Core/Data` must not use `try?`: a successful read with no row may take a
documented compatibility path, while an unreadable store must log privately,
roll back or abort its mutation, and leave durable work eligible for a later
retry. `ScanRepository` follows the same rule when reconciling scans,
collections, memberships, and Favorites state, so a failed read cannot
manufacture an empty local snapshot.

`OfflineSync/Persistence/OfflineQueueDurableAuthorityReader.swift` projects the
mirrored scan/job error markers, retry attempts, and video count from one fresh,
throwing `ModelContext`. Missing queue context is an error rather than an empty
authority. Queued-scan extraction is also throwing: Background Inference turns
an unreadable snapshot into the existing durable retry path, Media Upload arms
the persisted scheduler wake, and only a successful read returning no row is
treated as an already-removed scan.

Durable mutations stay ahead of external effects. Collection sync starts its
network task only after the `.running` job claim saves; an unreadable job
remains conservatively pending but is not dispatchable. Cloud deletion resolves
and claims every task/job pair before transport, and retains the deletion task
if the result-side job cannot be read or updated. Offline finalization checks
cancellation again after acquiring the per-scan persistence fence, and its
record/species/Field Trip hint helpers propagate read failures instead of
substituting absence.

Store Recovery's later image-reconnection handoff follows the same rules.
`MerianApp` does not inspect the legacy rescue index or fetch the scan library
while constructing the app. `ScanRepository` schedules a cancellable utility
task after queue configuration, and the Images registration actor uses two
fresh-context, 200-row passes: complete-library strong evidence first, then
globally timestamp-ordered fallback. Fetch failures throw and log privately
instead of masquerading as an empty library. Reconfiguration cancels the old
task and fences completion to the exact current `ModelContainer`. The
process-local registry separately prevents an interleaved timestamp guess from
retaining either a URL or local file once strong evidence claims it. If one
member conflicts, the complete timestamp group is rejected or evicted rather
than leaving a partial mapping. The strong pass also reserves direct filename
matches for scans with no rescued row. Recovery revisions invalidate cache and
coalescing identities for affected URLs, and the shared Core UI modifier reloads
retained images. Timestamp evidence permits local display only; cloud repair
requires an exact local URL backed by direct filename or registered strong
evidence. The
[image pipeline](../../../../../docs/system-architecture/03-image-pipeline.md)
is canonical for these evidence and refresh rules.

`CoreDataIntegrationArchitectureTests` freezes the exact bounded
`BackgroundDatabaseActor` file/import inventory, declaration-only aggregate,
directory-wide no-silent-fetch rule, single-context durable-authority read,
bounded authority consumers, cross-surface throwing contracts, and the exact
four-file Historical Sync production inventory. It also freezes the mirrored
Historical Sync test inventory, post-startup media-recovery handoff, and
600-line ceilings. `ScanRepositoryTests` remains the selector-compatible suite
root; its focused decoding, ingestion, reconciliation, model-persistence, and
deletion extensions preserve the existing tests, while
`HistoricalSyncCloudClientTests` verifies injected lease and request forwarding.
Focused queue, collection, inference, and finalization suites retain the
remaining behavioral evidence. This audit changes no SwiftData schema or
migration, API payload, endpoint, queue state, feature flag, navigation route,
or visible UI contract.

## Identification Review Replacement

All persistence operations in this section live in
`Database/BackgroundDatabaseActor+SpeciesMetadata.swift`. Its shared
fetch-mutate-save helper and identification-presentation replacement helper are
private implementation details; moving them out of the aggregate does not widen
mutable state or alter the existing method signatures.

Identification review changes species identity without changing
`LocalScanRecord.scientificName`, which remains the original AI reset key.
`BackgroundDatabaseActor.beginScanIdentificationOverride` atomically writes the
new override state, clears confirmation, and replaces prior-species presentation
fields with a scientific-name placeholder before any network lookup.
`BackgroundDatabaseActor.updateScanWithOverride` therefore treats `.unreviewed`
as an atomic replacement boundary: it clears override-owned common-name, hazard,
taxonomy, Wikipedia, reference-image, conservation, habitat, GBIF, lookalike,
and alternate-name fields in the same mutation that clears the review state.
Follow-up Species Dictionary hydration repopulates either placeholder; failure
leaves a coherent scientific-name placeholder rather than mixed-species data.

`updateScanWithOverrideSpeciesData` receives an explicit identity-replacement
flag. When interactive override/reset passes `true`, nil taxonomy clears prior
taxonomy and the write also clears prior lookalikes/alternate names because
those values belong to the previous species. A historical refresh of the
already-active override passes `false`, preserving valid taxonomy and
collections when the Species Dictionary row is sparse. These are data
replacements only; they add no SwiftData field or migration.

`SpeciesMetadataPersistenceTests` owns the matching actor behavior, including
the stale-identification fence, complete enrichment-field persistence, bounded
lookalike-cache clearing, override/reset replacement, sparse historical refresh,
confirmation, and legacy unflagging. The companion species-metadata architecture
suite scans every Swift file under `Merian` and `MerianTests` to freeze sole
declaration and test ownership. It also locks narrow imports, private helpers,
and the 600-line focused-file ceiling.

## Long-Lived Actor Cache Boundaries

`OfflineQueueManager` lazily retains both its queue database actor and the
Profile award actor to avoid repeated `ModelContext` construction during burst
completion. Each cache records the exact `ModelContainer` object that created
the actor. Store recovery, tests, or another container replacement therefore
replace the corresponding actor instead of reusing a context bound to an old
store.

The Profile actor cache is an execution optimization, not a value-cache
authority. `ProfileDatabaseActor.calculateAwards()` invalidates its compact
projection before every post-inference evaluation because inference can mutate
an existing scan without changing the projection fingerprint's count, latest ID,
or timestamp. Feature rendering continues to create an ad-hoc actor through
`ProfileTabDependencies`.

`QueueActorCacheTests` and `ProfileActorCacheTests` independently prove reuse
for the same container and replacement for a distinct container. Both suites are
serialized under the shared Offline Queue process-state lease.

## Non-Biological Bulk Deletion

`Database/BackgroundDatabaseActor+NonBiologicalRetention.swift` is the focused
persistence owner for `ScanErasurePayload`, `ExpiredNonBiologicalPurgeResult`,
the bounded retention purge, and bulk deletion. The actor and method signatures
remain unchanged. The internal payload member is named `mediaPaths` because the
value carries image, audio, and video paths.

The UI's non-biological erasure snapshots are advisory values, not deletion
authority. `BackgroundDatabaseActor.bulkDeleteNonBiologicalScans` re-fetches
each supplied scan ID in its actor-isolated context immediately before mutation.
An existing row that is now biological is skipped completely: its record and
local files remain, and no cloud-deletion task is created. Existing eligible
rows are deleted; a missing row retains the idempotent cleanup path by ensuring
its pending cloud-deletion task and returning only local paths for the caller to
remove.

The actor saves the record deletions and pending cloud-deletion tasks together,
rolls back the context on failure, and returns local paths only after the commit
succeeds. A retention result distinguishes accepted erasure work from records
actually deleted. An accepted row that disappeared after selection still drains
its local paths and cloud tombstone, while only a real row deletion publishes a
library change. A candidate rejected by commit-time biological revalidation
triggers neither effect. `FileIOActor` cleanup therefore cannot run for a
rejected row or get ahead of durable database state.

`NonBiologicalRetentionPersistenceTests` owns the six matching actor
regressions: commit-before-path-return, idempotent tombstone reuse, biological
reclassification fencing, missing-row retry cleanup, expired-only purge, and
oldest-first batch limiting. The companion architecture suite scans the complete
production and test Swift trees for sole declaration and test ownership, narrow
imports and dependencies, committed-count fencing, repository effect routing,
and the 600-line focused-file ceilings.

Cloud-deletion draining uses a process-local single-flight latch in addition to
durable restartable job state. Competing scheduler, repository, and UI wake
sources therefore cannot delete the same `PendingCloudDeletionTask` object
concurrently, while process termination still leaves `.running` work eligible
for idempotent replay.

## Reference Thumbnail Recovery

`Images/ScanThumbnailBackfillCandidate.swift` owns the immutable,
coordinate-free request value and eligibility mapping consumed by
`ScanThumbnailBackfillActor`. Keeping both declarations in Core Data prevents
the recovery actor from depending on a feature UI file. Scans Shell and Map
services decide when to schedule candidates; Core UI only projects and renders
the resulting local/reference state.

The actor injects
`Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift` for the
shared Wikipedia mobile-sections and GBIF taxon-key transport/parser. Core Data
continues to own candidate selection, dictionary-cache fallback, miss cooldown,
URL admission, SwiftData persistence, and image prefetching; none of those
policies move into the shared service.

## External Image Import Inbox

`Images/ExternalImageImportStore.swift` owns the app-sandbox copy of an image
received through the iOS document-opening path. The actor copies the source
after security-scoped access begins, coordinates provider-backed reads, records
an atomic FIFO recovery journal in Application Support, and keeps the receipt
across cold launch or onboarding. Interrupted temporary copies are removed,
completed orphan copies are adopted, and acknowledged files use durable
tombstones so cleanup can resume after suspension. The capped inbox is excluded
from backups. It never stores the external source URL or opens the app's
SwiftData store.

Capture acknowledges the receipt after one staged image is committed. Quota and
capacity blocks retain it for retry; missing or unreadable files are terminal
and are removed. Intake failures are journaled until the Capture workspace can
show feedback. EXIF capture date and a complete signed GPS pair are extracted
from the inbox copy before `MediaPreparationActor` strips source metadata. See
`docs/features-and-hardware/26-photos-share-import.md` for the routing, privacy,
and QA contract.

## Store Recovery

`StoreRecovery/` owns launch-time SwiftData store repair. It is deliberately
part of Core Data, not app shell code, because recovery policy belongs to local
persistence.

- `ModelStoreRecoveryCoordinator` remains the source-compatible façade for the
  production store configuration. `Models/`, `Policies/`, and `Services/`
  separately own migration values and diagnostics, error/privacy decisions, Core
  Data metadata inspection, and artifact archiving. See the
  [Store Recovery README](StoreRecovery/README.md) for the focused boundaries.
- `ModelStoreRecoveryPolicy` decides whether a `ModelContainer` startup failure
  is a verified SQLite/Core Data corruption case.
- It resolves the store URL from the same automatic SwiftData configuration used
  by the production container, then reads actual metadata before container
  creation. This keeps App Group-backed stores aligned with migration,
  diagnostics, quarantine, and rescue. Fresh and V51 stores open as current;
  known V42...V50 sources use finite, source-isolated plans; only unknown older
  stores use the full historical plan.
- The current automatic App Group location is a shipped-store compatibility
  constraint, not an extension data-sharing contract. Extensions never open the
  SwiftData database; a future move to private Application Support requires a
  data-preserving store relocation first.
- V50 shipped two model graphs under the same schema identifier. The coordinator
  fingerprints `NSStoreModelVersionChecksumKey` and selects either
  `MerianRecentV50MigrationPlan` for the original frozen graph or
  `MerianReleasedActiveV50MigrationPlan` for the processed release's
  `isPendingDeletion` graph. Both apply a source-exact custom V50→V51
  account-partition stage; unknown V50 signatures are preserved through rescue
  instead of guessed. A released V49 store selects
  `MerianRecentV49MigrationPlan` and advances through lightweight V49→V50 plus
  custom V50→V51 hops. The full historical plan remains linear through
  V42→V49→V50→V51; V43...V48 use their source-isolated plans. The
  duplicate-checksum retry ladder is ordered current store, both V50 graphs,
  then V49 down through V42.
- Only confirmed corruption may quarantine `default.store`, `default.store-shm`,
  and `default.store-wal`.
- Non-corrupt failures on legacy migration strategies may archive those same
  artifacts under `store-rescue/` before Merian rebuilds a fresh persistent
  store. Archive success requires every artifact move and the atomic manifest
  write; a failure rolls completed moves back before startup continues.
- Successful persistent opens and lossless migrations are silent. Recovery and
  safe-mode notices remain visible only after an actual fallback boundary.
- Each quarantine or rescue directory includes `recovery-manifest.json` with
  app/build/OS metadata, archive reason, moved artifact names, error code, an
  allowlisted stable error domain or its fingerprint, and deterministic
  fingerprints instead of raw error description or failure text. Captured Core
  Data metadata keys and string identifiers are likewise fingerprinted before
  persistence or telemetry.
- Store recovery must never reference `KeychainManager`, `SupabaseManager`,
  sign-out flows, device identity resets, or profile state.

The canonical diagnostics, tests, recovery behavior, and physical-device
install-over release gate are documented in
[`docs/backend-and-data/08-startup-store-recovery.md`](../../../../../docs/backend-and-data/08-startup-store-recovery.md).
