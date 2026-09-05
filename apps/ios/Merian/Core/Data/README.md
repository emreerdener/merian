# Core Data

The `Data` directory manages the local persistence and offline-first data
pipeline.

## Purpose

This area acts as the source of truth for app data. It encompasses SwiftData
configurations, the `HistoricalDatabaseActor` for cloud sync reconciliation, and
the `OfflineQueuedScan` persistence mechanism. It ensures that data remains
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
while continuing to emit the `is_deleted` wire field. V51 separately makes
preferred species names account-scoped. Foreground/background completion read
the same goal hint. Successful queue finalization preserves it as a durable
progress outbox until acknowledgement; explicit cancellation and terminal orphan
repair remove it. Persistent Insight contribution cards are server-backed and
are intentionally not cached in SwiftData.

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

`OfflineJobScheduler` owns persisted wake timing and the ordered drain: funding
reconciliation, pending uploads, inference replay, Field trip progress, cloud
deletion, then collections. Its small `DrainOperations` value keeps the six
existing live manager calls together; fresh scheduler instances can inject inert
effects without replacing global queue behavior. Mirrored
`Core/Data/OfflineSync/OfflineJobSchedulerTests.swift` verifies that future work
is armed before a suspended drain, every asynchronous effect is awaited in
order, and an offline drain cancels only its own wake without dispatching. These
are scheduler dispatch-policy proofs, not real provider-replay tests.

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
upload preparation repeats the same validation before signing. Older installed
queues may still contain local M4A/MP4 references. Before pending upload or
staged replay can claim those rows, the queue writes
`queueSchemaRepairGeneration = -1`, retreats the row to pending, clears every
old staging key and background-work generation, and records a diagnostic event.
Core Audio transcoding then runs outside the SwiftData transaction while the
same per-scan persistence coordinator used by inference claims is held. One
atomic commit rewrites both `capturedMediaJSON` and `capturedMediaEntries` to
Documents-owned mono 44.1 kHz Int16 WAV sidecars, sets generation `2`, and
returns the job to fresh signing. Cancellation removes only uncommitted sidecars
and resets generation `1`; deterministic conversion failure records
`queued_audio_upgrade_failed` and needs-attention instead of looping.

A background PUT created by a pre-WAV app can outlive the upgrade. Its terminal
callback first persists the completed manifest, then invokes the same repair and
clears those now-stale compressed-audio keys before any inference dispatch.
`tryClaimForInference` independently refuses every remaining legacy compressed
reference as a final defense. Cloud-complete local-recovery markers veto the
repair entirely, preserving server ownership and the no-redispatch fence. The
repair reuses the V49 integer field and changes no SwiftData model shape or
migration plan.

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

## Identification Review Replacement

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

## Non-Biological Bulk Deletion

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
succeeds. `FileIOActor` cleanup therefore cannot run for a row rejected by
commit-time revalidation or get ahead of durable database state.

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

- `ModelStoreRecoveryCoordinator` decides whether a `ModelContainer` startup
  failure is a verified SQLite/Core Data corruption case.
- It reads actual store metadata before container creation. Fresh and V51 stores
  open as current; known V42...V50 sources use finite, source-isolated plans;
  only unknown older stores use the full historical plan.
- A released V50 store selects `MerianRecentV50MigrationPlan` and applies the
  custom V50→V51 account-partition stage. A released V49 store selects
  `MerianRecentV49MigrationPlan` and advances through lightweight V49→V50 plus
  custom V50→V51 hops. The full historical plan remains linear through
  V42→V49→V50→V51; V43...V48 use their source-isolated plans. The
  duplicate-checksum retry ladder is ordered current store, then V50 down
  through V42.
- Only confirmed corruption may quarantine `default.store`, `default.store-shm`,
  and `default.store-wal`.
- Non-corrupt failures on legacy migration strategies may archive those same
  artifacts under `store-rescue/` before Merian rebuilds a fresh persistent
  store.
- Each quarantine or rescue directory includes `recovery-manifest.json` with
  app/build/OS metadata, archive reason, moved artifact names, and a sanitized
  error reason for support.
- Store recovery must never reference `KeychainManager`, `SupabaseManager`,
  sign-out flows, device identity resets, or profile state.

The canonical diagnostics, tests, recovery behavior, and physical-device
install-over release gate are documented in
[`docs/backend-and-data/08-startup-store-recovery.md`](../../../../../docs/backend-and-data/08-startup-store-recovery.md).
