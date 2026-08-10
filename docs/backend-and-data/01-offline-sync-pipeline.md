# The Offline Synchronization Pipeline

Naturebook's core differentiator is treating off-grid nature encounters as a
first-class citizen using native Apple offline architecture.

This scheduler and transport detail is governed by the joined
[Scan Ingestion Reliability and Recovery
Contract](./16-scan-ingestion-reliability-and-recovery.md).

## How the Queue Works

### 1. Realtime Inference Mapper (`saveLiveScanRecord`)

When a user scans a subject with an active network connection, the Gemini
response cascades back from the Edge node. To persist this inference against iOS
RAM loss,
`BackgroundDatabaseActor.saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:persistenceFence:)`
is invoked on its isolated `@ModelActor` thread. It accepts the current ordered
mixed-media timeline, the image/audio/context arrays derived from that same
source, and the exact queue-backed foreground owner. It validates that fence
under the per-scan persistence coordinator, writes both the scalar
`capturedMediaJSON` read mirror and the V41 `capturedMediaEntries` relationship
mirror, then inserts a `LocalScanRecord` and calls `modelContext.save()`.

The live mapper intentionally uses the actor's replacement helper rather than
the offline idempotent-insert helper. If the background queue already inserted a
minimal row for the same `scanId`, live persistence captures field notes and the
existing species UUID, deletes the collision row inside the actor context, and
inserts the richer live record with the current ordered media timeline.

Live visual and live non-visual persistence both acquire
`ScanFinalizationCoordinator` for the stable `scanId` before they resolve
species IDs or replace rows. This lock is shared with background URLSession
finalization. Without it, the live path and background path can save the same
unique `LocalScanRecord.id` from separate SwiftData contexts, forcing Core Data
to merge `capturedMediaEntries` during unique-constraint conflict resolution.
That relationship intentionally has no inverse, so the correct fix is to
serialize finalization per scan id rather than relying on merge-policy behavior.

### 2. Scan Submission & Immediate Durability (`submitActiveScan` → `enqueueCapture`)

Every scan — regardless of network state or what the user does after pressing
the shutter — is made durable **at the moment of submission**, not on a
best-effort rescue later. The durable unit is now a single ordered mixed-media
timeline that can contain up to 2 total user items across photos, short Pro
video clips, audio clips, and descriptions.

Timeline ordering comes from each staged item's `addedAt` value. Edits that
replace media bytes, especially manual image crops, must preserve the original
`StagedImage.addedAt` through `StagedImage.replacing(...)`; otherwise the queue
can persist a different media order than the user staged.

When `CaptureWorkspaceViewModel.submitActiveScan(modelContext:)` fires:

1. A stable `scanId` UUID and, when online, a foreground inference-generation
   UUID are generated. The scan ID identifies the durable capture; the
   generation identifies only the live attempt that currently owns it.
2. `enqueueCapture(imageDatas:displayImageDatas:audioFilePaths:videoFilePaths:telemetry:blurScore:scanId:observationContexts:mediaTimeline:visualMediaItems:preferredGoal:captureDate:foregroundInferenceGeneration:startSyncImmediately:onQueued:)`
   is called **synchronously on the main actor**, before any `async` boundary is
   crossed. It wraps its work in a `.userInitiated` priority
   `BackgroundTaskWrapper`, dispatching disk writes to `FileIOActor` to prevent
   blocking the UI and ensuring the SwiftData insert completes before the
   cooperative thread pool can be preempted by an app suspension. GPS is sourced
   from `EnvironmentContextManager.lastKnownLocation` — which returns the most
   recent accurate fix (≤30m) or falls back to the most recent inaccurate
   reading — so even scans captured during a GPS satellite acquisition carry a
   macro-region coordinate. Weather and `locationName` may be absent from the
   initial queue record. A late shutter-prefetch result is merged into
   `OfflineQueuedScan` and submitted to `/update-scan-context`; background
   replay can still backfill missing historical context before its own inference
   dispatch.
3. The visual submit path waits for `onQueued` before presenting queued/offline
   success or starting live analysis. A durable-queue rejection rolls back the
   pending live scan, shows an error, and deletes orphaned source video/audio
   files because neither the live path nor the queue now owns them.
4. **Immediate Offline Network Interceptor**: `submitActiveScan` then
   synchronously evaluates `OfflineQueueManager.shared.isOnline`. If the device
   currently lacks network connectivity, the function completely drops the
   execution thread. It blocks the UI router from presenting the
   `"Analyzing..."` skeleton `InsightSheetView` overlay and completely skips the
   creation of the live analysis `Task` below, returning control to the
   viewfinder immediately. A non-intrusive `ToastBanner` natively informs the
   user that there is no network connection and the scan is queued for upload,
   saving battery and tokens by recognizing that live inference would inevitably
   result in a network timeout.
5. Concurrently (if online and the submission is an eligible live-camera still
   with no audio or video), a `Task {}` gives the pre-fetched
   `EnvironmentContext` (GPS + WeatherKit/geocoding, started at shutter press)
   at most **150 ms** to finish. If that grace period expires, it fires
   `InferenceEngine.analyze(scanId:foregroundInferenceGeneration:imageDatas:...)`
   with shutter-time coordinates, date/time, distance, and cached telemetry. The
   late context is merged through the authenticated deferred-context endpoint
   and never causes a second identification request. This is the **live
   inference path** — it delivers results faster than the background upload +
   Gemini round-trip, directly to the open insight sheet. Before calling
   `analyze()`, the Task checks `pendingAnalyzeScanId == scanId` on the main
   actor — a property set on `CaptureWorkspaceViewModel` at scan submission
   time. If a newer scan has been submitted in the interim (overwriting
   `pendingAnalyzeScanId`), the Task returns without calling `analyze()` and the
   offline queue handles the scan independently. This replaces the weaker
   `guard isProcessing` that only detected completion (not supersession).

Gallery images and audio-bearing or video visual submissions keep their
immediate queue-sync race. Non-visual audio/video/Describe submission follows
the same durability rule as visual capture: it commits cached telemetry
synchronously, gives optional context enrichment 150 ms only after queue
acceptance, and late-merges completed context without resubmitting media.
Gallery-specific behavior remains unchanged.

The Scan Library projects two different queue concepts. Runnable
`pending`/`uploading`/`staged`/`inferencing` rows without
`queueNeedsAttention` drive its bounded periodic refresh and automatic recovery
kicks only while the device is online and unconstrained. A pending playback
video also requires the current large-upload allowance or an explicit
user-forced retry. Uploaded/staged video remains eligible for lightweight
status and inference work on an expensive but unconstrained path.
Needs-attention and path-ineligible rows remain visible for explicit retry or
deletion but must not keep polling or wake workers that cannot advance them.
The refresh task identity includes online, constrained, expensive/large-upload,
and explicit-override policy, so a satisfied-path policy transition cancels or
restarts monitoring without requiring a false offline edge. The observable
`unsyncedItemsCount` applies the same state-and-attention predicate and
therefore counts automatically runnable work, not every visible queue record.
It reads through a fresh SwiftData context so a background-actor commit cannot
remain hidden behind a cached main-context fault. Explicit retry clears the
attention fence, sends `.scanLibraryChanged`, and restarts monitoring through a
state-bearing task identity. The legacy `externalImport` state is non-runnable,
never offers an ingestion Retry action in either queue surface, and is rejected
by the retry mutation before durable state can change.
The serialized database actor enforces the same boundary after candidate
selection: upload and inference claims recheck `queueNeedsAttention` plus the
persisted retry deadline immediately before mutation, and orphan reconciliation
does not reset attention rows. A stale Library or worker snapshot therefore
cannot bypass the explicit-retry fence. Pending selection uses deterministic
timestamp/ID ordering and pages through future-dated retries, deferred live
uploads, videos blocked on the current network, and media-less legacy rows
until the runnable-media limit is filled or the eligible set is exhausted.
Media-less rows use a separate bounded quarantine budget, so older locally
blocked or malformed rows cannot starve newer ready work, while explicit
user-forced video upload remains eligible. The worker rechecks and, when
needed, refetches after a process-local policy change. Global server-owner
reconciliation reads through the serialized queue actor and excludes
attention-paused inference rows; a cached main-context fault cannot bypass that
fence.

An eligible live visual Capture can also supply a selected standard-outing goal
as `preferredGoal`. V50 stores the two goal IDs in the scan-keyed companion
model `OfflineQueuedScanGoalHint`, leaving the released V49 `OfflineQueuedScan`
entity byte-for-byte stable. The companion row is inserted in the same
model-context transaction as the queued scan, read by foreground and background
completion paths, included in the scan-ingestion request so the insert trigger
can apply the atomic preference/progress contract, and repeated by the later
`apply_scan_progress` call when it retrieves the durable receipt. It is not
inference input and never changes upload eligibility. Camera-only still evidence
may retain the hint; gallery, audio, video, Describe, Record, refinement, and
mixed camera/gallery evidence must discard it before queue insertion.

The goal hint is a ranking preference, never an evidence override. If the saved
identification is below the applicable Possible-match boundary (75% Flash /
65% Pro) and is not confirmed, the atomic progress receipt retains the complete
hint but issues no credit. A later confirmation or confirmed correction changes
the receipt revision, revalidates the hint, and can apply the pending goal
without resubmitting media or invoking the model again. A later confidence
downgrade follows the same trigger path and removes credit that no longer has
qualifying evidence.

For an eligible live-camera still, the live inference path owns the uplink
initially. The durable background path is handed off as soon as the inline
request body has finished sending:

- **Deferred background start**: `OfflineQueueManager` excludes the active live
  `scanId` from normal pending batches. `MerianRequestUploadDelegate` observes
  request-body progress and releases the row when all bytes are sent. A
  two-second fail-safe handles transports that do not provide progress
  callbacks.
- **Single inference owner**: recovery media may stage after that handoff, but
  `foregroundInferenceGenerations[scanId]` prevents staged replay from
  dispatching a second identification while the exact foreground generation
  still owns the scan.
- **Immediate recovery start**: request failure, connectivity loss, or app
  backgrounding releases both the upload hold and foreground inference claim.
  The suppression is process-local, so app termination/relaunch also leaves the
  durable row eligible for normal synchronization. Before a staged row starts
  background inference, it checks `/check-scan-status`; a processing/finalizing
  foreground ingestion remains server-owned and is polled instead of issuing a
  duplicate model call.

Every online live submission, including gallery, audio-bearing, video, and
text-only Describe paths, is queued before provider dispatch and registers the
same exact foreground-generation owner. Describe uses a zero-byte `.staged` row.
Only the eligible camera-still optimization defers the recovery upload; other
paths may stage recovery media immediately, but staged inference still waits
until the foreground generation succeeds or relinquishes ownership.

Current `/identify-multimodal` HTTP success is also a server durability fence:
moderation, required media promotion, primary species resolution, scan creation,
and owner-scoped read-back complete before `200`. The live path may persist and
clean up its queue row only after that response. Foreground inline images send
`imageBase64s` with an empty `r2ObjectKeys` array: a filename hint is not a
staged upload source and must never enter the promotion manifest. A retryable
`503 scan_persistence_failed` leaves the durable local queue source available.
When no owner row exists after a durable-stage failure, the queue clears
consumed staging keys and returns to `.pending` for a fresh signed upload; the
server marks the committed provider attempt failed so the stable idempotency key
can reserve a fenced metered retry. A terminal `400 observation_rejected`
follows the permanent failure path and cannot be converted into a successful
scan by owner-row recovery.

After handoff, either path can finish first:

- **Live wins**: `analyze()` first persists through a
  `LiveInferencePersistenceFence`, then calls `deleteQueuedScan` with the exact
  `ForegroundInferenceGenerationExpectation`. The generation is validated before
  and after URLSession task enumeration; only its current owner may cancel
  tasks, clear retry slots, remove the SwiftData row and goal hint, delete
  queue-only inference frames, or preserve media adopted by the final
  `LocalScanRecord`.
- **Background wins** (user backgrounded or dismissed): the upload completes via
  the OS-managed background URLSession, `dispatchInferenceDownloadTask` issues a
  background URLSession download task for inference, and the OS delivers the
  result to `processInferenceDownloadResult` even while the app is suspended —
  firing a push notification when ready. `deleteQueuedScan` from the live path
  is a no-op if the record is already gone.
- **Local finalization lock**: both local persistence paths use
  `ScanFinalizationCoordinator` before touching `LocalScanRecord.id`. If the
  offline path waits behind a live save, it re-fetches inside the lock and skips
  insertion when the row now exists. This keeps the local SQLite store
  idempotent before Core Data's unique-constraint merge policy becomes involved.
- **Double-hit prevention**: both paths transmit the same `scanId` as
  `client_scan_id` to the Edge function. `insertScan` uses
  `.upsert(row, { onConflict: "id", ignoreDuplicates: true })`, so a second
  successful request for the same scan is silently discarded at the database
  layer.

Once queued media has been written or adopted into `URL.documentsDirectory`, a
new `OfflineQueuedScan` SwiftData record is inserted with the available
telemetry payload attached. On a successful `context.save()`,
`AppTelemetry.trackOfflineQueued()` fires a `ScanQueuedForSync` PostHog event to
measure offline usage rate. If the save fails, the main context rolls back, any
consumed free-tier quota token is refunded, and staged files are deleted without
dispatching sync.

If cleanup encounters an orphaned hint after its queued scan was already
removed, `flushOfflineQueuedScan` deletes the companion and saves that repair.
This keeps later scan-ID reuse or correction work from observing a stale local
preference.

All queued-capture file I/O is now actor-owned. `enqueueCapture` writes staged
image bytes through `FileIOActor.writeTemporaryImages(imageDatas:)`, adopts
video/audio files already moved into Documents, and routes cleanup for rejected
inserts or failed saves through `FileIOActor.deleteFiles(at:)`. Inline
`Data.write` / `FileManager.removeItem` calls on the queue path are no longer
allowed.

Queued image bytes must already be bounded before this point. Camera, gallery,
and refinement paths stage inference-sized `compressedData` plus 2048 px
`displayData`; the offline queue must not receive original full-size library or
historical scan file bytes as `displayImageDatas`.

Temporary staged-media cleanup has explicit ownership. UI reset after submit
clears references only, leaving media for the queue or live persistence path to
adopt. Cancel, remove, replace, session-timeout discard, and queue-rejection
paths collect staged playback video paths plus companion audio paths and delete
them through `FileIOActor.deleteFiles(at:)`.

Video captures split display media from inference media before entering the
queue. `capturedMediaJSON` and `capturedMediaEntries` remain the user-facing
timeline: a video contributes one `SerializedMediaItem.video` with its playback
`.mp4`, poster thumbnail, and optional extracted-audio reference. Sampled video
frames are stored separately in `OfflineQueuedScan.inferenceImagePaths`, and
their matching `IdentifyVisualMediaItem` descriptors are stored in
`visualMediaItemsJSON`. This lets replay send every sampled frame to
`/identify-multimodal` while keeping Scan tiles, Insight previews, and Explore
sharing anchored to the single playback video item. Queue deletion treats those
sampled frames as inference-only cleanup candidates and preserves any video,
audio, or display media adopted by the final local scan.

Server finalization mirrors this split. Sampled frame URLs may remain in the
scan's compatibility image array but are not standalone canonical image rows.
Migration `20260729012153_fix_video_scan_canonical_finalization.sql` projects
the structured timeline when available and otherwise applies the legacy
standalone-image rule `max(images - videos × 5, 0)`, then requires every
projected image, playback video, and standalone audio row as exact owner-matched
ready media before completing the ingestion ledger. An offline video retry must
therefore preserve and promote its real playback key; it must not manufacture
display rows from inference frames or downgrade into a frame-only scan.

Still-image descriptors may also contain an optional normalized `focusRegion`.
The existing `visualMediaItemsJSON` field preserves it across queued upload and
replay without a SwiftData migration. `QueuedScanContext` snapshots the same
JSON so an analyzing queued Insight can render the identical region without
touching a live SwiftData model. Focus coordinates are transient and are not
copied onto completed scan records.

**UI Surface**: While a scan awaits network transit, its `OfflineQueuedScan`
record is rendered at the **top** of the Scans Library grid (`ScansGrid`) with a
dark overlay that reflects online, retry-wait, and needs-attention states.
Tapping a queued tile calls `LibraryView.openQueuedScan`. It first checks for a
completed local record to resolve the render-to-tap race; otherwise it emits a
fresh `QueuedScanContext` to `ScansSheetView`, which pushes
`InsightSheetView(presentationStyle: .embeddedInScansLibrary)` on the Scans
sheet's existing navigation path. No nested sheet is created. Queued scans are
excluded from batch-selection mode, so their IDs cannot enter the Share,
Download, or Delete pipeline.

The queued destination shares the foreground scanning layout: dynamic status
pill, `DidYouKnowCard`, Field notes, and scan information. Its phrase deck is
derived from exact queue/server state and uses the engine's generic phrases
during active inference. Only actionable queue status is added. It does not
show a separate heading, upload explainer, media-kind summary, or approximate
file size. `QueuedScanSnapshot` and `QueuedScanContext` still copy retry
metadata, captured media, telemetry, and approximate bytes so routing,
recovery, and diagnostics remain safe after SwiftData rows are updated or
deleted.

Two presentation refresh loops have different scopes. While queued tiles exist,
`ScansSheetView` reads fresh value snapshots every 1.5 seconds to work around
dropped presented-sheet SwiftData notifications. While a queued Insight is
visible, `QueuedContentView` reads the exact row through a fresh `ModelContext`
every second to update queue state and retry presentation. Neither loop owns
retry scheduling or pipeline dispatch, and unchanged values remain silent.
Future deadlines render `Automatic retry in N sec/min`, elapsed deadlines
render `Automatic retry is starting`, and offline rows render
`Retry when connection returns`. Eligible pending/staged rows expose
`Retry now`; this clears persisted backoff and resets the bounded automatic
attempt counter under the same scan UUID before entering the same atomic claim
path. Description-only staged work receives the same fresh budget. A known
cloud-complete result preserves its owner-result recovery marker and never
re-enables provider dispatch.

**Value-Type Snapshot Pattern** — `ScansGrid` never holds a live
`OfflineQueuedScan @Model` reference. When `ScansSheetView.refreshQueuedScans()`
fetches pending scans, it immediately maps them to `[QueuedScanSnapshot]`
value-type structs while the objects are live. `LazyVGrid` renders tiles from
this snapshot array — after `context.delete(scan)` fires, no grid tile can
access a zombie `@Model` attribute. When the user taps a queued tile, a fresh
`OfflineQueuedScan` is fetched and snapshotted into `QueuedScanContext` (a
richer value type with all telemetry and queue fields) before the queued route
is appended. That route retains the value snapshot through queue deletion and
completed-result handoff. `QueuedScanSnapshot.gridId` returns `"q_\(id)"` to
prevent duplicate `ForEach` keys against `LocalScanRecord` tiles that share the
same UUID.

**Failed-row retention (`purgeSoftDeletedRecords`)**: Terminal `.failed` (raw
value 5) rows are not all disposable. Rows marked `queueNeedsAttention == true`
remain visible so the user can retry now or cancel after local problems such as
missing media files, corrupt payloads, auth mismatch, or permanent validation
failure. Non-actionable failed rows are purged periodically. The purge rebuilds
paths through `CapturedMediaSnapshot` so image, audio, video, thumbnail, and
extracted-audio cleanup all follow the same canonical media timeline. File
removal happens after the SwiftData save via `FileIOActor.deleteFiles(at:)`,
keeping the database state authoritative.

**The Circuit Breaker (`CircuitBreakerManager`)**: If repeated HTTP errors or
timeouts cross a threshold, the circuit "trips", routing all new captures
straight to the offline queue and bypassing useless network connections for a
guaranteed zero-latency shutter experience.

**Serialized Funding Admission and Advisory Flash Meter**: The observable
entitlement booleans drive presentation only. Before capture code writes files
or starts foreground inference, `insertAndPersistRecord` and
`enqueueNonVisualCapture` synchronously claim one account/scan-keyed
`ScanFundingReservation` on `@MainActor`. Its class is paid Pro, locally
reserved complimentary Pro, immediate Flash, or deferred Flash with earlier
complimentary blocker scan IDs. Verified server availability is reduced by all
unresolved local complimentary and conservative legacy blockers, so one stale
remaining credit cannot admit multiple queued Pro scans.

Exactly one image, one standalone audio clip, or one description with no video
is Flash-eligible. Mixed, multi-item, and video captures without Pro funding
open the upgrade flow and never enter the queue. Immediate and deferred Flash
claims reserve the separate advisory daily meter at enqueue time; if it is
exhausted, admission fails before durable capture. If queue persistence fails,
the context rolls back, any Flash token is refunded, the local funding claim is
released, and source files are cleaned up. `AppTelemetry.trackOfflineQueued()`
is not fired for rejected work.

Funding is persisted as `funding_reservation` in the scan job metadata beside
`inference_generation`; generation handoff removes only its property. Relaunch
restores nonterminal reservations. Active pre-protocol-3 jobs without funding
metadata remain potential complimentary blockers unless
`funding_reservation_released: true` durably proves a prior local release. A
proven pre-dispatch local failure writes that marker before releasing memory
state or the advisory token. If the save fails, capacity remains blocked.
Ambiguous network outcomes remain reserved. A manual retry of a released job
derives eligibility from the persisted media timeline and performs a fresh
synchronous funding claim before re-entering automatic work.

Locally complimentary-reserved scans dispatch first. Deferred work cannot run
foreground inference or dispatch until one bulk owner-scoped status lookup per
scheduler pass establishes earlier blocker states. All `held`/`consumed`
blockers safely choose immediate Flash. A released or absent terminal blocker
requires a fresh entitlement snapshot and may promote the later scan to
complimentary Pro; newly paid proof promotes it to paid Pro. A terminal
`consumed` status also remains blocked until a subsequent successful entitlement
refresh proves the installed balance includes settlement. Reclassification is
persisted before dispatch and paid/complimentary promotion refunds the optimistic
Flash token.

This remains advisory rather than provider authorization. On upload, Edge uses
the stable scan UUID as its idempotency key and atomically reserves database
UTC-day/user/IP quota and any required lifetime hold before Gemini. A modified
client or cleared `UserDefaults` cannot bypass that boundary. Provider attempts,
including non-biological outcomes or malformed responses, consume the server
reservation; only a proven pre-provider no-op may refund it. Provider failures
move to a charged `failed` state so a later same-scan retry can make a newly
metered attempt; an abandoned pre-provider reservation expires and is
automatically refunded. The non-biological correction entry point may bypass
the Pro-only reanalysis feature lock, but replacement capture follows normal
paid → complimentary → Flash selection and limits. Success reconciles local
funding from both authoritative `plan_used` and `credit_consumed`;
`pro_complimentary` with `credit_consumed = false` releases the local assumption.

The entitlement verification, original-analysis linkage, and hold-settlement
rules are canonical in
[Three Complimentary Pro Scans](18-complimentary-pro-scans.md).

### 3. Network Awakening (`NWPathMonitor`)

The `NWPathMonitor` instance listens to the network stack continuously. The
manager records satisfied, constrained, and expensive state on the main actor;
a change to any of those values is meaningful even when connectivity remains
`.satisfied`. Eligible changes debounce for **3,000 ms** to let the OS
networking stack fully settle before processing. The 3-second window covers the
typical WiFi → cellular → WiFi handoff sequence, which fires 3–4
`NWPathMonitor` events within ~2 seconds — the 1-second window previously fired
sync on the first cellular `satisfied` event before the preferred interface was
fully associated.

Low Data Mode cancels the process-local persisted wake, all automatic drains
refuse a constrained path, and the background URLSession disallows constrained
network access. A later constrained → unconstrained change creates a new drain
even though the path stayed satisfied. Expensive but unconstrained paths may
continue eligible small image/audio work; playback-video rows remain pending
unless explicitly user-forced. An expensive → unmetered WiFi change likewise
wakes those blocked video rows. The same live values stop the Scan Library's
periodic refresh while all visible rows are path-ineligible and restart it when
work becomes eligible. The worker rechecks path policy after every actor
fetch/refetch and once more after Auth/filesystem preparation immediately before
its atomic pending → uploading claim, so an async suspension cannot dispatch a
video from a stale permissive snapshot. Immediately before each background task
resumes, dispatch rechecks online, constrained, expensive, and
explicit-override state. Every final PUT request disallows constrained access;
every request belonging to a non-forced playback-video scan also disallows
expensive access at the transport layer. This prevents an already-created
mixed-media WiFi manifest from partially continuing over cellular after a later
handoff. Standalone image/audio requests may still use an expensive
unconstrained path.

Automatic inference request preparation, delayed status probes,
server-ingestion polls, retry callbacks, and orphan-status reconciliation
revalidate that same online-and-unconstrained predicate after every suspension
and immediately before their next network entry. Completed-owner recovery
rechecks again before targeted or fallback historical hydration and before
persisting another local recovery attempt. A satisfied-path change into Low
Data Mode therefore does not issue a foreground status/inference/history
request or spend retry budget; the durable row is reclaimed when an eligible
path wakes the queue.

Connectivity restore now enters through `OfflineJobScheduler`. The scheduler is
the durable control-plane facade; it delegates scan ingestion to
`OfflineQueueManager`, cloud deletion to `PendingCloudDeletionTask`, and
collection sync to a coalesced `OfflineJobRecord`. Existing executors remain in
place, but retry ownership is no longer process-local: each job stores attempt
counts, last errors, next-run times, server status/stage, and user-attention
state in SwiftData.

The persisted date is an eligibility boundary, not an operating-system timer.
`OfflineJobScheduler` therefore selects the earliest active
`queueNextRetryAt`/`OfflineJobRecord.nextRunAt` and creates one token-fenced
process-local wake. It rebuilds that wake after every retry-date write, on
connectivity restoration, on each foreground activation, and when a queued
Insight opens. Attention-paused rows are excluded. A stale date wakes after a
bounded one second, and an atomic upload/inference claim clears both the scan
and job deadline before dispatch so a stale label or second claim cannot
survive. Connectivity loss cancels only the ephemeral wake; the durable date
recreates it after reconnect. If iOS suspends or terminates the process, exact
wall-clock execution is not promised—the foreground/reconnect drain immediately
re-evaluates all elapsed dates.

When a collection job drains, `BackgroundDatabaseActor.collectionSyncPayloads()`
fetches only non-Favorites `ScanCollection` rows and prefetches their direct
inverse `scans` relationships. It emits sorted scan IDs for deterministic
retries; it does not page through the full `LocalScanRecord` table. The
`sync-collections` Edge function compares that desired snapshot with current
membership and writes only the server-side delta.

### 4. Background Processing & Batch Uploads

The manager guards against expedition mode, connectivity, and an in-flight sync
before proceeding. Every scan in the queue at this point has already passed the
quota check and had its token consumed at enqueue time — `syncPendingScans` has
no quota involvement and uploads all queued scans unconditionally.

`SyncStateManager.shared.beginSync(itemCount:generation:)` is called to
transition the shared state machine to `.uploading(count:)` and broadcast the
exact batch volume to the UI. The generation is the same UUID stored on the
active upload batch and encoded into every URLSession upload task created by
that batch.

Batch sizing is governed by `MerianConfig`:

- **`pendingScanFetchLimit`** (50): maximum runnable `OfflineQueuedScan`
  records returned per cycle by
  `BackgroundDatabaseActor.fetchPendingScans(limit:)`. The actor may inspect
  additional deterministic pages to move past future-dated retries, deferred
  live uploads, and network-blocked videos.
- **`uploadBatchSize`** (5): maximum scans considered for R2 staging per cycle.
  Selection scans the full bounded runnable window, skips empty rows and
  non-fitting combinations, and admits later work that still fits. A malformed
  empty `.pending` row becomes needs-attention rather than remaining an
  invisible queue blocker; its serialized quarantine rechecks state and media
  before committing queue/job/event state. The selected scan batch is
  additionally capped by
  `MediaStagingContract.maxUploadItemsPerRequest` /
  `MerianConfig.mediaStagingMaxFilesPerRequest` to the `generate-upload-urls`
  limit of 6 media files total. This covers the canonical Pro video shape (five
  sampled inference frames plus one playback clip) while keeping mixed scans
  inside the pre-signed URL contract.
- **`mediaStagingMaxAudioFilesPerRequest`** (2): maximum audio files in one
  upload-signing request, matching the Edge parser and the documented
  cross-language contract in
  `docs/contracts/media-staging-upload-manifest.json`.
- **`mediaStagingMaxImageFilesPerRequest`** (5): maximum images in one signing
  request. The sixth total slot is reserved for the canonical five-frame plus
  one-playback-video shape, not a sixth still.
- **`mediaStagingMaxVideoFilesPerRequest`** (1): maximum video files in one
  upload-signing request, with `video/mp4` as the canonical queued content type.
  New Pro video captures prefer a compressed 720p playback clip of roughly 3 MB
  before upload while retaining the 12 MB hard cap for capture-time bounding,
  compatibility, and fallback when export is slow or unavailable.

Before upload tasks are dispatched, `MediaStagingContract` builds the canonical
staging manifest: sanitized filename, deterministic
`staging/{userId}/{fileName}` object key, media kind, content type, byte size,
client scan id, media role, file URL, and upload task description. It also
validates the local media budget before any scan is promoted out of `.pending`:
staged images must stay within the edge's 5 MB image fetch budget, staged audio
must stay within the 2.7 MB raw audio budget, staged video must stay within the
strict video byte budget, and a signing batch may include at most 2 audio files
and 1 video file. Records that fail this preflight move to `queueNeedsAttention`
instead of being marked `.uploading`.

The locally predicted owner segment is planning data, not server authority.
`/generate-upload-urls` derives its owner from the authenticated request, which
may lazily replace a device identity with an anonymous-user UUID. The queue
validates the complete returned manifest and signed paths, requires one
canonical server owner, and carries each exact returned key in the background
task description. A malformed or partial response starts no PUT and returns the
claimed scans to `.pending`.

Signing registration is idempotent on the authenticated owner, client scan UUID,
and deterministic object key. If the first HTTP response is lost after its
`scan_media_assets` rows commit, a retry returns the same row and upload-session
IDs instead of creating another active staging generation. A retryable failed
row reactivates with its original session; terminal, completed, or
media-incompatible rows fail closed for normal queue uploads. Completed scans
have one separate, fail-closed exception for a deterministic
`scan_share_restore` request. The same exception applies to an exact
authenticated-owner `failed_terminal` job only when its server-written
`terminal_reason_code` is `replay_exhausted`, or when exact
`media_reconciliation_abandoned` is also backed by matching composite
dead-letter/quota/media-lifecycle proof. Current/later policy,
pre-result/unproven abandonment, legacy-unknown, arbitrary terminal,
moderation-rejected, moderation-pipeline-failed, and ordinary queue signing
remains closed. A fresh
unrestricted scan lookup must confirm the active authenticated-owner row or
prove it absent for guarded reconstruction; tombstoned and foreign rows reject
signing. The offline queue never sets that purpose. The database enforces one
active staged row for that identity, and the parser rejects duplicate filenames
(including legacy names that sanitize to one key) before signing. New ledger
rows use a per-scan media slot, so retrying one scan alone does not change its
recorded order. Signing calls are composable subsets: a foreground inline
generation may have no staged sources while its queued recovery later adds them,
and live video may sign separately from queue frames/audio/video for the same
scan. Existing unrequested rows do not define an immutable full manifest. Edge
code bounds the combined active staged/processing capture-key set at six and
ignores historical promoted rows when a completed scan needs a later restore. A
database trigger takes an owner-scoped transaction advisory lock before
enforcing the same active staged-row cap, so concurrent disjoint subsets cannot
evade it.

After that preflight, `BackgroundDatabaseActor.markScansAsUploading(scanIds:)`
atomically transitions only the valid selected scans from `.pending` to
`.uploading`, saves, and returns the set of scan IDs it actually claimed.
`syncPendingScans` signs and dispatches only files belonging to those claimed
IDs. If the actor fetch or save fails, it rolls back and returns an empty set,
leaving the queue in `.pending` for a later retry rather than launching
URLSession uploads whose state was never persisted. This means
`fetchPendingScans` can never re-dispatch the same scans after an app restart —
the persistent state machine eliminates the need for an in-memory
`activeScanUploadIds` set that would be lost on process death. Each local media
file is streamed directly from `URL.documentsDirectory` to
`URLSession.uploadTask(with:fromFile:)`. Every image, audio, and video upload uses
the exact response-declared `Content-Type` and `Content-Length` headers. These
must match the values baked into the Cloudflare R2 pre-signed URL by the
`generate-upload-urls` Edge function; its signed-header set is
`content-length;content-type;host`. `ScanUploadItem` retains the size used when
signing. The queue re-stats the file immediately before PUT task creation and
discards/re-signs the URL if that size changed. The Edge function
now consumes the full `files` manifest (`fileName`, `mediaKind`, `contentType`,
`sizeBytes`, `clientScanId`, `mediaRole`) instead of inferring type from
extensions, creates staged `scan_media_assets` rows for scan media, and
validates the manifest—including a positive, nonzero size for every structured
file—before signing. The OS background session owns byte transmission from
here, handling interruption and resume transparently. The
scheduled `replay-scan-ingestion` worker can later retry staged
media/audio/video or description-only scans whose `scan_ingestion_intents` are
resumable, so an app exit after successful upload does not leave the phone as
the only recovery path. The scheduled `reconcile-scan-media-assets` worker can
repair stale staged media when the scan row already exists, or clean abandoned
upload-session objects after their TTL. Before cleanup, reconciliation checks
the server `scan_ingestion_jobs` row keyed by the same user and
`client_scan_id`: active leases and future `retry_after` windows keep staged
media pending, repaired scans complete only through the shared claimed-key and
canonical-media finalization transaction, and abandoned media records a
structured terminal reason for status polling. Inline foreground requests still
depend on the iOS queue because raw media bytes are not stored in replay
intents. Queue diagnostics can be exported through
`OfflineQueueManager.writeQueueDiagnosticsExport(eventLimit:)`; the JSON
contains jobs, redacted scan queue metadata, and bounded event rows only. This
internal exporter is not exposed in Settings. The artifact binds that evidence
to the app version/build and embedded source revision/fingerprint/state. It
never contains raw media paths or payload contents, descriptions, Field notes,
location/GPS, raw metadata, or arbitrary free-form error/event messages.
Retained error codes and server status/stage values must match the canonical
lowercase machine-token grammar or they are omitted.
The support schema currently declares `formatVersion: 1`. Jobs, scans, and
events are each capped at 500 rows, and event requests are clamped to 1...500
even when an internal caller supplies zero or an unbounded integer. The export
uses complete data protection at rest.

**`MediaStagingContract` + `ScanUploadItem`** (defined in
`OfflineSyncTypes.swift`): The flat arrays previously used to pass per-image
metadata (`fileNames`, `fileURLs`, `scanIDs`, `imageIndices`) have been
consolidated into a typed staging manifest. Each `ScanUploadItem` carries
`scanId`, `uploadIndex`, `mediaKind`, `localPath`, sanitized `fileName`,
`fileURL`, `contentType`, expected `objectKey`, and a `StagingUploadFile`
request DTO carrying `sizeBytes`, `clientScanId`, and `mediaRole` together,
eliminating the class of flat-index bug where indexing into parallel arrays at
position `N` could silently return mismatched values for mixed-media batches.
URLSession upload task descriptions now use
`upload|{scanId}|{uploadIndex}|{syncGeneration}|{serverObjectKey}` through the
same contract, preserving scan IDs that contain underscores, binding each
callback to its originating batch, and carrying the authenticated destination
through suspension. The parser still accepts the previous three-/four-part forms
and the legacy underscore form for OS-owned tasks created by an older app build.
Legacy callbacks recover and validate the key from the signed request path.
Before signing, local validation rejects duplicate sanitized filenames or object
keys, including collisions produced by distinct local path spellings. Staged
image roles are a signing-time hint; final user-visible media still comes from
the saved `captured_media` manifest and ready `scan_media_assets` rows.

Connectivity, constrained-path policy, live-upload ownership, and playback-video
cellular eligibility are rechecked immediately after the serialized database
claim as well as before it. A claim invalidated while the actor was suspended is
returned to `.pending` together with its durable ingestion job in one save,
without incrementing retry budget or recording a transport failure. The same
exact-claim release runs if signing fails after a connectivity/policy handoff or
if no upload task was created. Claims from a newer timestamp-fenced generation
and scans with a live URLSession task remain untouched.

Dispatch treats one scan manifest as one logical transport unit. All signed
destinations and local sources for that scan are validated first; then every
member task is created and resumed in one main-actor turn, or none are. A path
update cannot therefore interleave task creation and leave a generation waiting
forever for a sibling callback from a PUT that never existed. Once resumed,
transport-level constrained/expensive flags stop a later handoff, and the exact
successful-key accumulator still prevents partial completion from advancing to
analysis.

Upload retry accounting is scan-generation scoped, not file scoped. Each
successful callback contributes its exact key to the generation accumulator but
does not clear `queueAttemptCount` or the last durable error. Those fields reset
only after the accumulator proves the complete expected manifest succeeded and
the same actor save persists the exact keys plus `.staged`. If the queue/job
read is unavailable, an already-staged manifest differs, or persistence fails,
the callback cannot dispatch inference; replay uses only the durable row. If one
sibling succeeds and another repeatedly fails, each new generation therefore
advances normal backoff and eventually reaches the bounded needs-attention state
instead of restarting forever at attempt one.

Server completion is also not a retry-reset boundary by itself. Status `found`
starts exact-owner local hydration and promotion but does not clear attempt
count, backoff, or last error first. If targeted or full historical sync fails,
the queue remains server-owned and `.inferencing`; it advances that same durable
history and schedules local-recovery polling without becoming eligible for
another provider request. The exact-owner `found` observation is persisted
before hydration, so a relaunch or later unavailable/inconsistent status probe
cannot make orphan reconciliation reset the row to `.staged`. The latest server
status remains intact. The bounded retry limit pauses recovery for explicit user
retry instead of polling forever. That manual retry preserves the exact-owner
fence and performs owner-result recovery only; it cannot re-enable provider
dispatch during a temporary status outage. Successful local recovery deletes the
queue row.

**`ScanQueueState` enum (SchemaV33)**: `OfflineQueuedScan` uses a single
`scanStateRaw: Int` column (added in V32→V33 custom migration, replacing the old
`isUploaded: Bool` + `isDeleted: Bool` pair) to encode all pipeline states:

| State          | Raw Value | Meaning                                                                                                                                                    |
| -------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.pending`     | 0         | Awaiting upload to R2                                                                                                                                      |
| `.uploading`   | 1         | URLSession task dispatched, bytes in transit                                                                                                               |
| `.staged`      | 2         | All upload-backed media confirmed in R2; awaiting inference. Describe-only scans also enter `.staged` directly because they have no media bytes to upload. |
| `.inferencing` | 3         | Background URLSession download task dispatched to the unified inference edge path (`/identify-multimodal` for current app traffic)                         |
| _(reserved)_   | 4         | —                                                                                                                                                          |
| `.failed`      | 5         | Terminal — tombstoned, awaiting purge                                                                                                                      |

After the last media file for a scan receives HTTP 200,
`BackgroundDatabaseActor.markScanAsStaged(scanId:r2Keys:)` atomically persists
the confirmed R2 object keys into `stagedR2Keys: [String]?` and transitions to
`.staged`. Storing the keys at upload time eliminates the auth-expiry 403 edge
case that occurred when keys were reconstructed from the current session UUID at
inference time — a session that may have expired hours later.
`replayInferenceForUploadedScans()` queries for `.staged` scans and re-enters
them via `dispatchInferenceDownloadTask` using the persisted keys.

The transition returns a durable `ScanStagingTransitionOutcome`; HTTP success is
not itself permission to start inference. Only `.staged` or `.alreadyAdvanced`
may continue to the generation-aware inference claim. `.retryRequired` keeps the
current completion evidence fenced until the delegate envelope releases its
callback token, then the timestamp-fenced orphan pass resets a row that is still
`.uploading` to `.pending` and restarts signing. `.discarded` clears the
in-memory manifest without resurrecting a missing, failed, or external-import
row. Likewise `updateQueuedScanForRetry` returns an attempt only after its queue
and job changes save; callers distinguish a failed durable schedule from the
bounded in-process retry wake.

**Audio, video, and non-visual scans**:
`OfflineQueueManager.enqueueNonVisualCapture` enters audio-bearing records at
`.pending` so their local audio file is uploaded through the same background R2
staging phase as images and videos. Description-only records enter `.staged`
directly because they carry no media bytes. Video captures can attach an
extracted Int16 PCM WAV track to the persisted video item; queued replay uploads
that track as audio inference input while keeping the user-facing media timeline
as one video item. `dispatchInferenceDownloadTask` splits persisted staging keys
into image `r2ObjectKeys`, audio `audioR2ObjectKeys`, and video
`videoR2ObjectKeys`, derives `observation_contexts` and `audioMediaItems` from
the canonical media timeline, passes video frame counts for telemetry/token
accounting, and routes replay through
`MerianNetworkClient.buildMultiModalRequest(...)` without building a large
inline audio body.

Standalone audio begins a pinned environment-context lookup when recording
starts, but `submitNonVisualCapture` never waits for it before inserting the
durable queue row. The first record uses `lastKnownLocation` and immediate
capture telemetry. After acceptance, the prefetched or fallback context gets a
150 ms grace for the live request; a later result updates the same local row and
`/update-scan-context` without another identification. The eventual
`LocalScanRecord` can therefore share enriched GPS, `locationName`, weather, and
capture-time context while durability remains independent of
WeatherKit/geocoding. This is required for later Explore publication because
post-level location sharing can sanitize an existing label but cannot derive a
text label from coordinates by itself.

For video scans, `MerianNetworkClient.uploadStagedVideoFiles` is strict: every
requested local `.mp4` must resolve from an absolute path, `file://` URL,
Documents filename, or temporary filename, and every upload must succeed. The
foreground path no longer converts a video upload failure into
`videoR2ObjectKeys: []`; it throws and lets the already-durable queue retry. The
same rule applies on replay: a scan that began as video must reach the backend
with a durable playback video key, not as sampled frames alone.

**Distributed lock (`tryClaimForInference`)**: Before any inference pipeline
starts, `BackgroundDatabaseActor.tryClaimForInference(scanId:)` performs an
atomic `.staged → .inferencing` transition. It returns `false` if the scan is
already `.inferencing`, preventing two concurrent pipelines from racing for the
same scan. This replaces the in-memory `activeScanUploadIds` set which was lost
on process death.

**Generation ownership and ABA safety**: Durable queue state prevents duplicate
claims across processes, and the winning inference UUID is persisted in the
scan-ingestion `OfflineJobRecord.metadataJSON` in the same save as
`.staged → .inferencing`. In-memory generations and slot tokens provide an
additional callback fence, but they are not the persistence authority:

- An upload batch receives one UUID before its background wrapper starts.
  Expiration, URL-generation failure, zero-task completion, and URLSession
  delegate teardown call `finishUploadSync(generation:)`. That method clears
  `isSyncing`, `syncTask`, and UI upload state only when the UUID still matches
  `syncGeneration`. Each successfully claimed scan also retains its latest
  upload generation after preparation ends; a delayed callback from an older
  batch is rejected even after the replacement batch has already finished.
- A scan receives a single-flight inference preparation UUID before
  `.staged → .inferencing`. `ScanInferencePersistenceCoordinator` serializes
  claims and retry retreats for that scan across independent SwiftData
  `ModelContext` actors, closing their fetch-then-save window. The same UUID is
  stored durably, becomes the active inference generation, and is encoded as
  `inference_v2|{generation}|{scanId}` in the background download task. Request
  preparation, delayed status probes, retry scheduling, delegate callbacks,
  result processing, task cancellation, and queue deletion all compare that UUID
  before mutating state.
- An online queue-backed submission receives a foreground inference UUID before
  enqueue. The queue transaction stores it in the scan-ingestion job and
  registers the same in-memory owner before upload/replay can start. Provider
  preflight, provider dispatch and completion, live local persistence,
  main-actor result or failure commit, and queue cleanup all carry that UUID.
  `scanId` alone is never sufficient ownership. The UUID is single-use:
  `OfflineQueueManager` atomically consumes an exact generation before any
  engine instance dispatches its provider pipeline. Cancellation and
  pre-provider exits register a tokenized retirement task synchronously so the
  UUID cannot restart before asynchronous durable handoff completes. Transient
  handoff fetch/save failures retain that registry slot and retry with bounded
  backoff rather than reopening the UUID or permanently abandoning recovery
  suppression. Merely registering retirement immediately makes the attempt
  non-current, so delayed saves and UI/cleanup callbacks cannot act during the
  durable handoff window. Failure handlers also compare the full scan,
  presentation-attempt, and foreground generation before emitting telemetry,
  recording a circuit-breaker failure, triggering a haptic, or publishing an
  error placeholder. A current owner snapshots that proof immediately before
  synchronous retirement and performs its terminal commit without another
  suspension; a stale handler is an idempotent no-op. Confidence-zero responses
  preserve their terminal no-record behavior, but queue-backed foreground and
  generated background paths require the response to echo the exact scan ID
  before cleanup is allowed. A mismatched or missing ID leaves the durable row
  intact for recovery. App backgrounding, connectivity loss, failure, or
  cancellation clears only the expected generation and then hands the durable
  row to recovery. Replacing the insight presentation with a persisted library
  record performs the same exact-generation handoff before changing
  `activeScanId`; it never abandons the old foreground claim or deletes its
  queued capture.
- Retry accounting plus `.inferencing → .staged` is one persistence operation
  and succeeds only when the `OfflineJobRecord` still contains the expected
  generation. A stale callback therefore cannot consume retry budget or make a
  replacement runnable. Upgrade recovery may adopt a generation only when the
  legacy metadata is `nil`; once any UUID is present, ownership is exact.
- Delayed probe, server-poll, and replay tasks live in `GenerationTaskRegistry`.
  Each registry entry has both an owner generation and a unique slot token.
  Replacing an entry removes the old slot before cooperative cancellation; a
  resumed old task can neither clear the replacement nor perform delayed work
  unless its token still owns the slot. Status probes and server polls retain
  that slot through their awaited status, cancellation, database-transition, and
  recovery work, then compare before clearing it. A replacement also cancels the
  old Swift task, and post-await guards require both a live token and
  non-cancelled task before mutation.
- Upload-completion callbacks use independent membership tokens until ownership
  transfers to inference preparation. A callback removes only its own token;
  another callback for the same multi-file scan remains visible to orphan
  reconciliation. The scan's latest upload generation is revalidated after every
  suspension before either callback may mutate queue state or dispatch
  inference. Successful callbacks also record their exact canonical
  server-issued key in a generation-scoped accumulator. The scan can become
  staged only when that set equals the duplicate-free expected manifest key set;
  missing, extra, or duplicate expected members fail closed, and disappearance
  from the URLSession task list is never success evidence. Each handler
  publishes its outcome before its first suspension.
- Inference-driven queue deletion carries either a background
  `InferenceGenerationExpectation` or foreground
  `ForegroundInferenceGenerationExpectation` and revalidates it after awaiting
  `URLSession.allTasks`. A recovery initiated by a server-poll slot carries that
  slot token through the same check. It then acquires the per-scan persistence
  coordinator, validates the appropriate durable generation, and keeps that
  ownership across URLSession cancellation and the main-context queue-deletion
  save. That one save marks the scan job complete, clears transient job errors,
  inserts the completed event, and deletes the queue row; it never persists a
  successful inference as cancelled in an earlier transaction. Explicit user
  deletion remains intentionally unguarded and records cancellation for all work
  on that scan. A crash replay that finds no queue row and an already-complete
  job succeeds idempotently without inserting another completed event.
- Connectivity loss invalidates the current upload and inference generations,
  cancels registered delayed tasks, clears preparation ownership, and calls
  `SyncStateManager.forceIdle()`. Late callbacks carry retired UUIDs and become
  no-ops; reconnect reconciliation returns durable `.uploading` / `.inferencing`
  orphans to runnable states.

**Startup reconciliation & ongoing orphan recovery**: On first connectivity
restore per process life, `replayInferenceForUploadedScans` runs a gated
cold-start `reconcileOrphanedUploadingScans(activeScanIds:observedThrough:)`
that cross-references pre-existing URLSession tasks. The task-list snapshot
captures `observedThrough` before its first suspension, and the actor resets
only rows whose `queueUpdatedAt` is not newer than that cutoff. Upload claims,
reconciliation, inference claims, and retries all use the same cached queue
actor, so a replacement claim that reaches the actor before an older reconcile
is ordered first and excluded by the cutoff. This closes the snapshot/actor
queue ABA window without relying on task cancellation. Both orphan reconcilers
also exclude `queueNeedsAttention` rows before reset; paused work retains its
exact durable state until explicit retry.

The replay/orphan driver also has a process-local single-flight boundary.
Library presentation, scheduler, reconnect, and URLSession completion wakes
share one active reconciliation. Any number of wakes received while it runs
coalesce into at most one trailing pass. This preserves a wake that observes
new durable state without overlapping task snapshots, duplicate status probes,
duplicate orphan transitions, retry-budget inflation, or a Library log storm.
Process termination remains safe because runnable authority is durable and the
next process can claim a new driver.

The all-upload-tasks-settled callback invokes this recovery even when a
reattached generation cannot finish the old process-local global sync latch. On
every pass, a proven `.uploading → .pending` orphan reset refreshes the unsynced
count and calls `syncPendingScans()` immediately; it never waits for another
app-active or connectivity event. This is also the recovery path when a process
terminates after only part of the in-memory callback success set was recorded.

`reconcileOrphanedUploadingScans` returns `Bool` — `true` if at least one orphan
was reset. The cold-start callback calls `syncPendingScans()` **only when the
return value is `true`**. This is critical: the initial `syncPendingScans()`
call from `handleActivePhase` runs before the cold-start reconcile completes
(the reconcile is async), so it finds no `.pending` scans (the orphaned scan is
still `.uploading` at that moment). Without calling `syncPendingScans()` after
the reconcile, the reset scan would sit in `.pending` indefinitely — there is no
subsequent trigger until the next connectivity change or foreground. Guarding on
the return value prevents a spurious second sync in the common case (no orphaned
uploads). On every subsequent call it also runs
`reconcileOrphanedUploadingScans` again via a live-task cross-reference — this
catches `.uploading` orphans created mid-session when `generateUploadURLs` fails
or the `syncPendingScans` Task is killed before its catch block can run, and
resets them to `.pending` and immediately restarts signing. Additionally, on
every call it runs
`reconcileOrphanedInferencingScans(activeInferenceScanIds:observedThrough:)`
with the same snapshot cutoff. It cross-references live background URLSession
inference tasks, preparation slots, completion slots, active generation owners,
and server-poll slots before resetting `.inferencing → .staged`. Current tasks
use `inference_v2|{generation}|{scanId}` descriptions; the parser also
recognizes legacy `"inference_{scanId}"` tasks created before generation
tagging. This replaces the old blind `resetOrphanedInferencingScans()` — a
background download task for inference can survive app suspension and re-attach
after a relaunch, so blindly resetting all `.inferencing` scans would dispatch a
duplicate inference task against a scan already owned by a live OS task.
Transient inference failures reset the scan back to `.staged` (via
`transitionScanToStaged(id:)`) so `replayInferenceForUploadedScans` can reclaim
it on the next connectivity restore. `transitionScanToStaged` is source-state
guarded — it only writes if the scan is currently `.inferencing`, preventing a
concurrent `softDeleteQueuedScan` tombstone from being overwritten by a
background actor that resolves slightly later.

Background inference classifies a Supabase platform route `404` before general
HTTP handling. The response must omit `X-Merian-Handler: 1` and carry the stable
platform code, official missing-function envelope, or gateway-without-execution
evidence. That outcome preserves the local queue row and enters the normal
durable retry path. Handler-owned `401`, `408`, `425`, and `429` responses do
the same; the four exact Identify replay conflicts remain retryable as a
rolling-deployment safety net. `Retry-After` can raise the bounded persisted
delay. Exact handler-owned `403 ai_consent_required` is classified before the
generic `4xx` branch: it retains the row/media in user-actionable
needs-attention, invokes the durable account-scoped consent fence, and returns
without an automatic inference retry. Other handler-owned `4xx` responses
retain the media in a user-actionable failed row. Only an exact stable
`observation_rejected` response is a
non-actionable terminal policy outcome.

**Server idempotency**: The iOS client passes its local `scanId` as
`client_scan_id` in the active `buildMultiModalRequest(...)` request body. The
edge function uses it as `generatedScanId` when provided, claims
`scan_ingestion_jobs` before AI inference, and records expected media counts,
staged image/audio/video object keys, recovered upload-session ids, and a
deterministic `manifest_checksum`. The atomic RPC calculates that checksum only
after it resolves the upload-session ids. It also writes a service-role-only
`scan_ingestion_intents` row containing the sanitized replay intent: telemetry,
observation context, media descriptors, staged keys, upload-session ids, and a
payload checksum calculated from the exact stored payload. Raw inline media
bytes are not stored; if a foreground request used inline base64 media, the
intent is marked non-resumable and the iOS queue remains the recovery source.
The scheduled `replay-scan-ingestion` worker claims due resumable jobs,
reconstructs the staged request, and invokes `/identify-multimodal` with the
same `client_scan_id`. `insertScan` still uses an upsert with
`onConflict: "id", ignoreDuplicates: true`, so a replayed inference request for
an already-inserted scan is a silent no-op rather than a duplicate-key error.
Completion is separate: the shared finalization RPC proves all claimed
staging-key dispositions and ready canonical media rows before writing
`complete` last. The response-aware finalizer atomically stores the validated
success envelope at that same boundary. A repeated request checks for a stored
completion or an exact reconstructible owner row before media resolution and
quota reservation, returns `200` with `X-Merian-Idempotent-Replay`, and never
calls the provider again. A reconstructed replay may coexist with a retryable
canonical ledger; older completed rows without an envelope use the same durable
scan/species reconstruction through the executable wire contract. The job ledger
plus intent therefore lets status polling, reconciliation, and server replay
distinguish the same-media retry from a changed media shape for the same scan
id. Account-deletion tombstones have no owner and are terminal for replay; a
delayed ingestion job cannot dispatch another provider request for them. When an
owned scan row exists but strict media finalization was interrupted, a
service-only completion repair distinguishes inline image hints from real queued
image keys using redacted inline counts. It requires exact owner-bound upload
rows and filename-to-canonical-URL mappings for every real image/audio/video
key, tolerates only migration-marked superseded signing rows, recomputes both
checksummed ledgers, and invokes the canonical finalizer without reopening quota
or inference.

> **Critical**: The `taskDescription` for each new upload task is
> `upload|{scanId}|{uploadIndex}|{syncGeneration}|{serverObjectKey}`, where
> `uploadIndex` is the per-scan media slot across the canonical upload list. It
> must not use the flat position across the entire batch.
> `processUploadCompletion` parses the identity structurally and records an
> HTTP-successful upload under its exact canonical server key. Because iOS
> multiplexed HTTP/3 background tasks can complete and dispatch callbacks out of
> order, neither `indexPart == count - 1` nor absence from `session.allTasks`
> proves the whole manifest succeeded. The final callback reconstructs the exact
> expected keys from the durable queue row and requires all of them in the
> generation-scoped success accumulator. A failed member never contributes a key
> and fences the generation; a callback also aborts when a different generation
> is preparing or transferring the same scan.

**Concurrent staging (`withTaskGroup`)**: Pre-flight guards — URL validation,
file existence checks, and tombstoning — remain serial. Once all guards clear,
the `FileManager.copyItem` and `uploadTask` creation for each image are fanned
out concurrently via `withTaskGroup`. For a 3-image scan this eliminates 500
ms–2 s of head-of-line blocking before the background session takes ownership.

**Bounded backoff for `generateUploadURLs` failures**: When the pre-signed URL
request fails, `syncPendingScans` first calls
`reconcileOrphanedUploadingScans(activeScanIds:observedThrough:)` to reset any
`.uploading` scans — which were transitioned before `generateUploadURLs` was
called — back to `.pending`. Without this reset those scans would be invisible
to the retry since `fetchPendingScans` only returns `.pending` records. After
the reset, each affected scan records durable retry metadata through
`OfflineQueueRetryPolicy`. Retries use jittered backoff capped by
`maximumRetryDelay`; once `maximumAutomaticRetryAttempts` is exhausted, the
queued scan is marked `queueNeedsAttention` instead of scheduling another
automatic retry. Process-local helper tasks and the central wake are cancelled
immediately on connectivity loss so stale retries never fire while offline;
their persisted deadline is retained and recreates the wake after reconnect.

All this payload work runs inside a `BackgroundTaskWrapper.execute` block so iOS
does not suspend the process during disk I/O or URL generation. Its expiration
handler captures the batch UUID and calls `expireUploadSync(generation:)`.
Expiration cancels and clears only the still-matching `syncTask`, removes only
preparation entries owned by that batch, and completes only that upload token in
`SyncStateManager`. A delayed expiration from batch A therefore cannot reset
batch B. If OS-level caching attempts fail locally and create zero transfer
tasks, the same generation-checked `finishUploadSync(generation:)` path releases
the latch without waiting for a URLSession delegate callback.

### 5. Upload Lifecycle via URLSession Delegates

- **Step A**: iOS transmits the staged file to the Cloudflare R2 staging bucket.
- **Step B**: `urlSessionDidFinishEvents(forBackgroundURLSession:)` fires,
  invoking the `AppDelegate` completion handler so the system knows it's safe to
  suspend.
- **Step C**: `urlSession(_:task:didCompleteWithError:)` fires. Non-Sendable
  task properties are captured as local immutable variables before crossing the
  actor boundary through the newly distinct `fetchScanMetadata` helper. The
  handler cleans up the temp staging file unconditionally, then evaluates the
  payload explicitly through `handleUploadFallback`:
  - **Transport errors — file missing** (`NSURLErrorFileDoesNotExist`,
    `NSURLErrorCannotOpenFile`): terminal local problem — mark
    `queueNeedsAttention` and keep the row visible for user retry/cancel.
  - **Transport errors — transient connectivity** (`NSURLErrorTimedOut`,
    `NSURLErrorNetworkConnectionLost`, `NSURLErrorNotConnectedToInternet`,
    `NSURLErrorDataNotAllowed`, `NSURLErrorInternationalRoamingOff`): retain in
    queue, persist `queueAttemptCount`, `queueLastError*`, and
    `queueNextRetryAt` via `OfflineQueueRetryPolicy` until the automatic retry
    budget is exhausted.
  - **Transport errors — other**: logged, retained in queue with persisted retry
    metadata until the automatic retry budget is exhausted.
  - **HTTP 429 / 5xx**: Recoverable — retain in queue and persist the next retry
    time until the automatic retry budget is exhausted. **HTTP 503** returned by
    the `identify` Edge function for transient Gemini errors (including non-STOP
    finish reasons) falls into this category — the scan is retained for retry
    rather than tombstoned while retry budget remains.
  - **HTTP 401 / 403 and other permanent upload 4xx**: mark
    `queueNeedsAttention`. The user media is not silently deleted after a fixed
    retry count. Inference response handling separately recognizes exact
    `403 ai_consent_required` as the no-auto-retry disclosure transition.
  - **HTTP 200**: Evaluates the image against `session.allTasks` to ensure it is
    the _final_ chunk completing, then calls `dispatchInferenceDownloadTask()`.

  > **Retry durability**: `uploadRetryCount` is no longer the source of truth.
  > Retry ownership lives on `OfflineQueuedScan.queue*` fields and the paired
  > `OfflineJobRecord`. Automatic scan-ingestion retries are capped by
  > `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`, use jittered
  > backoff up to `maximumRetryDelay`, and then move to `queueNeedsAttention`. A
  > process kill no longer resets retry history or deletes user media after
  > three local failures. Successful upload/inference paths clear retry
  > metadata; server-owned work persists `job_status`, `job_stage`, and
  > `retry_after` from `/check-scan-status`. Server-side resumable replay is
  > also bounded: after 10 replay claims for the same sanitized intent,
  > `claim_replayable_scan_ingestion_jobs` marks the job `failed_terminal` at
  > `server_replay_limit_reached`.

  > **Failed Upload Notifications**: Any pathway that natively tombstones a
  > queue payload (due to transient exhaustion, HTTP 4xx permanence, or explicit
  > file-system corruption) proactively fires a
  > `PushNotificationManager.shared.sendUploadFailedNotification()` alert
  > containing an isolated `{"type": "failure"}` payload if the application is
  > currently backgrounded, allowing the user to gracefully intercept lost sync
  > cycles without inadvertently routing to deleted `InsightSheet` indices.
- **Step D**:
  `dispatchInferenceDownloadTask(scanId:extracted:preparationGeneration:)`
  validates the single-flight preparation owner, builds an authenticated
  `URLRequest` via `MerianNetworkClient.buildMultiModalRequest(...)`, and issues
  a **background URLSession download task**
  (`backgroundSession.downloadTask(with: request)`). The preparation UUID is
  claimed before any suspending status/request work and becomes the task
  identity: `"inference_v2|{generation}|{scanId}"`.
  `SyncStateManager.shared.beginInferencing(generation:)` registers that exact
  token. The inference download is suppressed until the **last** media file for
  the scan and upload generation has landed (guarded by the strict
  `session.allTasks` lookahead filter validated in Step C), preventing
  partial-payload submissions. The request body is small for queued media:
  images travel as `r2ObjectKeys`, audio travels as `audioR2ObjectKeys`, and
  only descriptions/telemetry are inline. Because this is a background
  URLSession download task (not a data task), iOS can deliver the response body
  even while the app is completely suspended. To pass the server's
  case-sensitive IDOR block, the deterministically awaited user UUID embedded
  within the R2 keys is strictly lowercased. Weather backfill is persisted to
  `OfflineQueuedScan` via `BackgroundDatabaseActor.updateScanTelemetry` before
  dispatch so the delegate can read hydrated telemetry from SwiftData on result
  delivery. The current implementation deliberately skips optional WeatherKit
  backfill during background replay so request construction cannot hold the
  queue; already persisted telemetry is still included.
- **Step E (background)**: When the inference download task completes,
  `urlSession(_:downloadTask:didFinishDownloadingTo:)` fires. The temp file is
  immediately copied to a task-specific stable path and
  `processInferenceDownloadResult(scanId:generation:resultFileURL:statusCode:functionRouteEvidence:)`
  is invoked inside a `BackgroundTaskWrapper`. The parsed generation must still
  own the scan; otherwise the result is discarded as stale.
  `SyncStateManager.shared.beginFinalizing(generation:)` transitions that exact
  token to `.finalizing`. `BackgroundDatabaseActor.processAndCleanupOfflineScan`
  decodes the JSON, inserts `LocalScanRecord` when confidence is positive,
  writes `audioFilePaths`, `videoFilePaths`, and `capturedMediaJSON`, and calls
  `modelContext.save()` while the same per-scan persistence coordinator still
  protects the durable generation. The background actor intentionally does not
  delete the `OfflineQueuedScan`; after the save succeeds,
  `processInferenceDownloadResult` rechecks the inference generation before it
  calls
  `deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:preservePreferredGoalHint:inferenceExpectation:serverPollTokenToPreserve:)`
  on the main actor. The expectation is rechecked after URLSession task
  enumeration, so a delayed finalizer cannot cancel or delete a replacement
  generation. Job completion, its completed event, and queue deletion commit in
  that same guarded save; the generation is checked again before later UI,
  notification, and retry-accounting side effects. That main-context deletion
  still provides the reliable `@Query` re-evaluation trigger for open sheets,
  but it also has access to the queued row before deletion, so it can delete
  `inferenceImagePaths` and other queue-only files while preserving display
  images, video clips, and audio files adopted by the saved `LocalScanRecord`.
  If the background save fails, `wasCleaned` is `false`, no
  push/discovery/hydration side effects fire, and the queue record remains
  retryable. If the main-context delete fails, final user-facing side effects
  stay suppressed until a later retry can commit cleanup. On zero-confidence
  HTTP 200 responses no `LocalScanRecord` is inserted; successful queue deletion
  removes the queued row and purges its media footprint. Inference download task
  failures and retryable non-200 HTTP responses route through
  `handleInferenceTaskNetworkFailure(scanId:generation:error:)` before entering
  `handleInferenceRetry(scanId:generation:reason:)`. `NSURLErrorCancelled`
  (Code=-999) is short-circuited because it is produced when an owner path
  cancels background work after live inference already succeeded or the user
  deleted the queued scan. Before scheduling a retry, `handleInferenceRetry`
  calls
  `MerianNetworkClient.shared.checkScanStatusDetails(scanId:requiredVideoCount:)`
  (POST `/check-scan-status`) to probe whether the scan already landed in
  `public.scans` or is still owned by a server ingestion job. For queued video
  scans, `requiredVideoCount` is the count of video entries in the queued
  captured-media timeline, so a frame-only cloud row does not count as
  recovered. When the poll returns `found`, targeted historical sync pulls the
  server row immediately and `deleteQueuedScan` removes the queue entry only
  after local promotion succeeds. Retry metadata is retained until that
  deletion; a failed hydration persists a completed-result recovery marker and
  advances bounded recovery instead of becoming a new inference attempt. A
  scheduled server poll keeps its registry token until this awaited recovery
  finishes; replacement cancels the old task and all post-await mutations
  revalidate that exact token. When the row is not found but the job is still
  `processing`, `finalizing`, or `retrying`, the local row stays `.inferencing`
  and another server poll is scheduled. The first `failed_retryable` observation
  honors `retry_after` and atomically writes the exact
  `server_retryable_failure` latch plus incremented attempt count. A not-found
  durability/promotion generation that consumed staging clears
  `stagedR2Keys`, returns to `.pending`, and uploads retained local media again;
  its latch and attempt survive successful `.uploading → .staged`. The marker
  and count are mirrored on `OfflineQueuedScan` and its `OfflineJobRecord`.
  Fresh reads consult both copies; claim, retry, upload-claim, and staging
  transitions repair drift from the surviving high-authority marker and
  nonnegative monotonic maximum before mutation. A cloud-complete marker wins
  over retry state in either copy. Transient signer or PUT retries also retain
  the latch, append their precise failure event, and increment from the maximum
  committed count rather than a cached snapshot. After the persisted delay,
  only that exact durable marker lets the next generation-fenced status
  preflight dispatch Identify and reclaim the backend attempt.
  Marker-free, unrelated, manual, processing/finalizing, completed-result, and
  terminal states still reject duplicate inference. Both marker and attempt
  reads use a fresh context and both mirrored rows so cached main-context faults
  or a migrated queue-row snapshot cannot hide background-actor authority.
  Expected duplicate retreats already committed by another serialized owner
  are silent. Retry exhaustion cancels server polling and retains the scan in
  needs-attention state rather than creating a status/upload loop.
  Other provider/inference failures return the row to `.staged`. A retry
  timestamp that is already stale schedules a one-second recheck rather than
  the maximum five-minute wait, so clock skew or an expired lease cannot stall
  recovery. HTTP `401`, `408`, `409`, `425`, and `429` are retryable; a safe
  integer `Retry-After` raises the persisted delay up to the queue maximum.
  Exact `403 ai_consent_required` preserves local media in
  `queueNeedsAttention`, durably closes the active account's consent gate, and
  schedules no automatic inference retry while consent is invalid. After the
  user explicitly reapproves, the queue resumes at most its newest matching row
  only when durable funding metadata proves the current account, exact scan ID,
  unreleased reservation, and dispatch eligibility. It never bulk retries or
  claims replacement funding; unproven rows remain paused. Other handler-owned
  `4xx` responses
  preserve local media in `queueNeedsAttention`, while exact
  `observation_rejected` is terminal.
  Server-ledger terminal failure marks the queue row as needing attention.
  Unresolved `not_found` responses or status-probe failures fall back to the
  same persisted retry budget
  (`OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`) used by upload
  staging only when no durable exact-owner result has previously been observed.
  Once a completed-result recovery marker exists, an unavailable or temporarily
  inconsistent probe remains `waitForServer` and can never re-enable provider
  dispatch.

  **InferenceEngine hydration (background-wins race)**: After the shared scan
  milestone coordinator task is started, if `processingResult.speciesData` is
  non-nil, `processInferenceDownloadResult` checks whether `InferenceEngine` is
  still presenting the exact released live-attempt generation for the same scan.
  `commitRecoveredBackgroundResult` compares `activeScanId`, the live
  presentation UUID, its released foreground UUID, and the absence of a new
  foreground owner before publishing. When these checks succeed, the background
  URLSession path has raced ahead of the suspended live
  `InferenceEngine.analyze()` task — which happens when the user backgrounds the
  app immediately after capture. In that case the recovered result is committed
  first, atomically invalidating the old presentation UUID, and only then is the
  exact live task cancelled. That ownership transfer prevents a cooperatively
  cancelled live error handler from overwriting the recovered result. A stale
  background completion that finds replacement generation B returns without
  cancelling B. This prevents the old live task from resuming after
  foregrounding, finding a cold network, and overwriting a scan whose result is
  already committed to the database. The required queue-backed connectivity
  path publishes `queuedPresentationScanId`; the open Insight snapshots that
  durable row and shows **Queued for later** while the background owner resumes,
  instead of manufacturing a **Network timeout** result. Durable foreground
  retirement and local presentation authority must be evaluated separately:
  path monitoring can retire the former before URLSession returns, while the
  exact still-current sheet still needs to acknowledge queue takeover. The
  current catch path separates those checks, and queue-backed Identify returns
  the first transport failure without generic inline replay. A protected gated
  transport test reproduces retirement-before-callback ordering. Exact-SHA and
  device acceptance remain release-blocked in the
  [live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md).
  Same-ID background completion continues to use the result observer
  (`isProcessing == false && speciesData != nil`). Queue takeover instead uses
  `InsightSheetView`'s task keyed by `queuedPresentationScanId`, with a bounded
  exact-ID SwiftData fetch before it routes to queued content.
- **UUID Terminality**: `OfflineQueueManager` strictly awaits the resolved
  finalized database UUID from `dbActor.processAndCleanupOfflineScan()` (the
  "Terminal ID"). This effectively terminates the ephemeral offline properties
  forever. Downstream notifications or `AppRoute.scan` requests
  ALWAYS execute traversing the Terminal ID, guaranteeing user interactions bind
  directly to `.biological` persistence blocks instead of ghost records.
- **Long-lived actors**: `BackgroundDatabaseActor` and `ProfileDatabaseActor`
  are now stored as persistent properties (`_queueDbActor`, `_profileDbActor`)
  on `OfflineQueueManager` and initialized lazily on first use. Reusing a single
  actor instance across consecutive completions avoids repeated actor
  allocation + `ModelContext` setup. Each `@ModelActor` serializes concurrent
  calls through its executor automatically, so rapid burst completions queue
  safely. `resolvedQueueDbActor(container:)` tracks the container that owns the
  cached actor (`_queueDbActorContainer`). If the caller provides a different
  container, the cache is invalidated and a fresh actor is created. In
  production the container is a process-lifetime singleton so this is a no-op;
  in tests each suite creates a fresh in-memory container, and the identity
  check ensures a stale actor bound to a previous test's already-deallocated
  store is never returned.
- **Step F**: `GamificationManager.shared.recordNewSpeciesDiscovered()` and the
  inference-complete push notification fire immediately per completion. The
  final database scan ID, decoded `SpeciesData`, and model container then enter
  `ScanMilestoneCoordinator`, the same boundary used by foreground inference.
  The server ingestion transaction has already attempted Field trip progress
  before the scan becomes visible. The coordinator deduplicates
  foreground/background races by final scan ID, waits for remote persistence,
  retrieves the idempotent progress receipt through the Edge action, publishes
  progress refresh events, calculates newly eligible achievements without
  immediately presenting them, and atomically enqueues standard outing progress,
  Seasonal Challenge progress, achievements, then **New to
  Naturebook**. A failed or no-match progress attempt releases the later
  milestones only after it finishes. Award calculation is per final scan rather
  than process-lifetime burst-debounced, because strict notification ordering
  and scan-level deduplication are now the contract. The Retryable progress
  failures leave the SwiftData goal-hint outbox intact and schedule bounded
  in-process retries; a later scheduler pass replays it after termination.
  `UserDefaultsKeys.hasUnseenScan` is set to trigger the MainTabBar red dot,
  **unless** `suppressInferenceBanners` is `true` (the insight sheet is open and
  the user is watching the transition to results — setting the badge in that
  case would cause it to appear and immediately need clearing on sheet dismiss).
  The push notification is scheduled unconditionally via
  `PushNotificationManager.shared.sendInferenceCompleteNotification` —
  foreground banner suppression is delegated to
  `PushNotificationManager.willPresent`, which reads `suppressInferenceBanners`
  and either presents the banner or delivers silently based on whether the
  insight sheet is currently visible.

**Offline telemetry at dispatch**: Background replay includes the environmental
telemetry already persisted on `OfflineQueuedScan`. Although the request builder
retains a bounded historical-weather backfill branch for compatibility, current
policy sets `shouldFetchWeatherBackfill = false`: queue recovery must not wait
on WeatherKit or reverse geocoding before the OS-owned inference task is
created. A scan without stored weather therefore proceeds with its durable GPS,
location, and capture-time fields as available. If this policy is re-enabled,
the backfill must remain generation-guarded and must be persisted before task
dispatch because there is no opportunity to alter the request after URLSession
takes ownership.

When all background upload tasks for a batch settle,
`finishUploadSync(generation:)` calls
`SyncStateManager.shared.completeUploadPhase(generation:)`. A stale delegate
cannot clear a replacement batch. If `unsyncedItemsCount > 0` after the matching
batch completes, `syncPendingScans()` is called recursively to drain the queue
automatically.

## The Sync State Machine (`SyncStateManager`)

`SyncStateManager` is an `@MainActor @Observable` singleton that exposes the
current phase of the upload pipeline to UI components. It replaced the original
pair of `isSyncing: Bool` + `pendingUploadCount: Int` booleans with an
exhaustive `SyncPhase` enum:

```swift
enum SyncPhase: Equatable {
    case idle
    case uploading(count: Int)  // Media files are being PUT to R2 staging
    case inferencing            // Gemini Edge function is running
    case finalizing             // Writing LocalScanRecord, cleaning up queue
}
```

Backward-compatible computed shims (`isSyncing: Bool`,
`pendingUploadCount: Int`) are preserved for existing UI components. New UI can
branch on `phase` directly for richer progress display. `OfflineQueueManager` is
the only writer.

**Concurrent pipeline safety**: `SyncStateManager` stores one optional upload
activity keyed by its batch UUID and a dictionary of inference UUIDs whose
values are `.inferencing` or `.finalizing`. `begin*` calls are idempotent for an
existing token, and `completeSync(generation:)` /
`completeUploadPhase(generation:)` remove only the exact token that began the
work. A completion from generation A after `forceIdle()` and generation B has
started is therefore a no-op instead of decrementing B. Phase priority is
`.finalizing`, `.inferencing`, `.uploading`, then `.idle`, so concurrent work
still presents the most advanced active phase. Connectivity-loss resets use
`forceIdle()` to invalidate all current tokens; late completions cannot match
new work.

**Operational diagnostics**: stale ownership is expected during cancellation
races and is logged at debug level rather than treated as queue corruption.
Relevant messages include `ignored stale generation`, `ignored stale callback`,
`superseded while enumerating tasks`, `replacement upload owns`, and
`owner changed while enumerating tasks`. If a scan appears stuck, export queue
diagnostics and correlate its durable `scanStateRaw` / job timeline with these
messages and the generation-bearing URLSession task description. Never remove
the compare-before-clear checks to silence these logs.

## Deletions in Offline Environments

Scan permanence and user privacy require that explicitly deleted datasets are
permanently erased, even fully offline.

### 1. Transactional Destruction (`ScanRepository.eradicateScan`)

Deletion follows a strict ordering designed to guarantee consistency: **database
operations commit first, file deletion runs after**.

1. `offlineQueue.softDeleteQueuedScan(scanId:)` — tombstone any in-flight
   upload.
2. Insert `PendingCloudDeletionTask` + `modelContext.delete(record)` +
   `modelContext.save()` — **atomic DB commit**. If the save fails, the method
   returns immediately without touching disk; state remains fully consistent.
3. `FileIOActor.shared.deleteImages(at:)` — purge local `.webp` files
   asynchronously, skipping remote R2 URLs (those are cloud-owned). Runs only
   after the DB commit succeeds.
4. `offlineQueue.syncPendingDeletions()` async — attempt the cloud deletion
   immediately; retry from durable eligibility dates on the current or a later
   connectivity cycle until the server explicitly confirms erasure.

### 2. Cloud Deletion Tasking (`PendingCloudDeletionTask`)

A `PendingCloudDeletionTask` SwiftData record is inserted at deletion time,
queuing the `scanId` for cloud erasure. The UI executes an optimistic delete
immediately. On the server, `/delete-scan` first commits a private,
owner-verified generation tombstone, then erases canonical R2 media, then
removes the PostgreSQL row. A failed or lost response leaves both the local task
and server tombstone available for idempotent retry; stale inference or a second
device cannot recreate that UUID. The local task is a latency optimization, not
the only completion mechanism: `reconcile-scan-deletions` independently leases
and resumes pending server tombstones every five minutes, so uninstalling the
app or permanently losing the deleting device cannot strand the privacy request.
The GitHub-backed Scan Media Health Monitor separately alerts on oldest-pending
age, backlog, and expired leases.

### 3. Upload Interception (`softDeleteQueuedScan` & `deleteQueuedScan`)

If the scan being destroyed is actively queued for upload, invoking
`deleteQueuedScan(scanId:)` cancels isolated URLSession transmission streams,
deletes the `OfflineQueuedScan`, and removes local files only after the
SwiftData save succeeds. Save failure rolls back the pending queue deletion and
leaves disk intact for retry. The secondary `softDeleteQueuedScan(scanId:)`
tombstones the `OfflineQueuedScan` record
(`scanStateRaw = ScanQueueState.failed.rawValue`) only when its save commits,
structurally excluding it from future sync attempts across disconnected logic
flows. Records are hard-purged later via `purgeSoftDeletedRecords()`, which also
rolls back on save failure before touching disk.

### 4. Network Polling Sync (`syncPendingDeletions`)

On `NWPathMonitor` reconnect, `syncPendingDeletions()` drains the
`PendingCloudDeletionTask` queue. The initial SwiftData fetch is bounded to
**200 records** (`fetchLimit = 200`) to prevent a user returning from a long
offline period from loading hundreds of tasks into the V8 heap at once; records
beyond that limit are processed on the next reconnect cycle. Deletion requests
are fanned out **concurrently in batches of 10** via `withTaskGroup`. Each batch
fans out all its child tasks simultaneously, collecting results before the next
batch begins. A single `modelContext.save()` runs once after all batches
complete, removing all successfully confirmed tasks in one write. If that save
fails, the context rolls back so the deletion tasks remain durable and can be
retried, even though the remote deletes may already be idempotently complete.
Capping at 10 concurrent Edge calls prevents connection-pool exhaustion; for a
user with 10 offline deletions the wall time still drops from ~4 s (serial) to
~600 ms (concurrent).

The task is removed only when `MerianNetworkClient.deleteScan` receives a 2xx
body and decodes explicit `success: true`. `invalidResponse` is not not-found
proof: it can represent a missing/non-HTTP response, an unresolved auth/session
failure, or a malformed/contradictory 2xx body. That error and every transport,
HTTP, or decoding failure retain the task for the next cycle until the server
explicitly confirms success. Cloud erasure does not inherit the generic
ten-attempt pause: its exponential delay caps at 15 minutes, but the privacy
request never expires. A pending task is authoritative, so the next drain also
repairs legacy `needsAttention` jobs and contradictory local `complete` or
`cancelled` job states before retrying. The owner-bound endpoint rejects a
different active account rather than confirming someone else's deletion; the
task remains queued until its owner session can resume it. Server-declared
already-absent scans use the same validated `success: true` envelope, so
idempotency never requires guessing from a client error category. The
result-processing loop builds a `[String: PendingCloudDeletionTask]` dictionary
once before iterating results, making each lookup O(1) instead of the previous
O(n) linear scan (was O(n²) overall for large batches).
One process-local single-flight latch serializes the whole drain across
scheduler, repository, and UI wake sources. It resets in `defer`; after process
termination, the persisted `.running` status remains runnable and the
owner-fenced endpoint makes replay idempotent.

## The Collections Pipeline

Merian supports creating custom `ScanCollection` buckets while fully
disconnected.

1. **Entity Instantiation**: A user taps "New Collection" — a `ScanCollection`
   is inserted into SwiftData and `modelContext.save()` is called immediately.
   The collection is durable locally from this point.
   `CollectionActionAlertModifier` trims names, rejects duplicates against
   non-deleted local collections, reserves `"Favorites"` as a protected system
   collection name, and only enqueues cloud sync after the local save succeeds.
2. **Background Upload**: `OfflineQueueManager.shared.enqueueCollectionSync()`
   is triggered, creating or updating the coalesced
   `OfflineJobRecord(id: "collection-sync")` instead of treating a process-local
   or `UserDefaults` flag as the source of truth. A one-release startup bridge
   imports any legacy `UserDefaultsKeys.needsCollectionSync` bit into that job
   record, then the shared `syncCollectionsIfPending()` /
   `drainCollectionSyncIfPossible()` single-flight path pushes
   `SyncCollectionPayload` arrays to the `sync-collections` Edge function. The
   upload is wrapped in `BackgroundTaskWrapper.execute(name: "CollectionSync")`
   so iOS grants additional background time if the user closes the app
   immediately after creating a collection. Repeated automatic push failures use
   the same bounded retry budget as other offline jobs; after the budget is
   exhausted, the coalesced job moves to `needsAttention`. A later local
   collection mutation re-queues the job and resets that retry budget because it
   represents new user intent.

   **Diff-based Edge sync**: The `sync-collections` Deno function handles
   explicitly passed soft-deletions (`is_deleted: true` or `isDeleted: true`)
   securely before performing a set-based delta sync for `collection_scans`
   membership. It computes the desired membership from the client payload and
   diffs it against the current Supabase state. Existing memberships are fetched
   for all owned incoming collections with one keyset-paginated
   `.in("collection_id", ownedIds)` query ordered by `(collection_id, scan_id)`,
   resuming after the last composite primary key rather than using range/OFFSET
   pages or one round trip per collection. Only the delta (rows to add and rows
   to remove) is written. We intentionally do not use implicit destructive diffs
   for whole collections to prevent devices with missing histories from
   obliterating remote databases. Collection ownership is admitted atomically by
   `upsert_owned_collections`: new and same-owner IDs continue, while foreign or
   concurrently colliding IDs remain unchanged and are skipped without blocking
   unrelated collections. Membership additions use
   `insert_owned_collection_scans`, which joins both the collection and scan to
   the authenticated owner. Scans that have not synced yet—and foreign scans—are
   skipped for a later sync pulse rather than causing the whole chunk to fail.
   An ownership-RPC error stops hydration and membership writes. A database
   owner-match trigger and split authenticated RLS policies independently reject
   cross-owner memberships. Removals are grouped by `collection_id`. A
   `MAX_COLLECTIONS = 200` cap is enforced server-side.

   **Strict Concurrency Gating**: To prevent race conditions where out-of-order
   network requests resurrect deleted collections, all collection pushes now
   flow through one shared drain path. `OfflineQueueManager` retains the active
   `collectionSyncTask`, so concurrent callers await the same in-flight work
   instead of launching parallel requests. A monotonic `collectionSyncRevision`
   is incremented on every local collection mutation; a successful sync marks
   the collection-sync job complete only when the captured revision still
   matches. If a newer rename/delete arrives while the old request is in flight,
   the job remains pending/waiting and the next drain loop replays the newer
   state. This guarantees `is_deleted: true` reaches the Edge function after any
   stale upsert snapshots.

   **Explicit Local Tombstone Destruction**: When a collection is marked for
   deletion in the UI, `CollectionActionAlertModifier` explicitly captures
   underlying SwiftData constraint validations using a strict `do-catch` block
   around `modelContext.save()` and logs any failures to `MerianLog.data`. This
   provides a reliable guarantee that the `isDeleted = true` assignment persists
   to disk. Once the Edge sync returns HTTP 200 indicating successful cloud
   deletion for the payload, the `BackgroundDatabaseActor` permanently hard
   deletes the ghost `ScanCollection` record from SwiftData to ensure it cannot
   resurrect or linger in UI state.

   > [!IMPORTANT]
   > **Apple Sign-In (`ES256`) and Edge Functions:** Merian utilizes Apple
   > Sign-In on iOS, which issues JWTs signed with `ES256` rather than the
   > typical `HS256`. Supabase's Kong API Gateway natively rejects `ES256`
   > tokens by default, resulting in silent **401 Unauthorized** errors that do
   > not even reach the Deno runtime. Anonymous-compatible authenticated routes
   > must be deployed with `verify_jwt = false` / `--no-verify-jwt`. This
   > bypasses Kong's fast-path validation and allows our internal `requireAuth`
   > wrapper in `_shared/auth.ts` to validate the token. Most routes retain
   > `supabaseClient.auth.getUser()`; latency-sensitive
   > identify/deferred-context routes use the cached-JWKS `getClaims(token)`
   > path with explicit claims validation. Both strategies natively support
   > `ES256`. Deliberately public routes such as `species-dictionary` also use
   > `verify_jwt = false`, but skip `requireAuth` and must document their public
   > data boundary.

3. **Resilient Sync Architecture**: `syncCollectionsIfPending()` /
   `drainCollectionSyncIfPossible()` no-op when offline or unauthenticated.
   Collections created in these states remain in SwiftData and are picked up by
   the push-before-pull ordering described in step 4.
4. **Push-Before-Pull Ordering**: `syncHistoricalScansDown` routes pending
   collection uploads through the same
   `OfflineQueueManager.drainCollectionSyncIfPossible()` path — **before**
   fetching the cloud collection list. This guarantees that any collection
   created while offline or before authentication completes is in the cloud
   before the reconciliation delete pass runs, and also prevents launch-time
   historical sync from bypassing the normal collection single-flight latch. If
   pending collection mutations cannot be drained safely, historical
   reconciliation aborts rather than reconciling against stale cloud state.
5. **Reconciliation**: After all scan pages have been streamed,
   `syncHistoricalScansDown` calls
   `HistoricalDatabaseActor.syncCollectionsDown(remoteCollections:)`.
   Collections present in the cloud response are upserted. **Inbound Tombstone
   Shield**: If the cloud response erroneously includes a collection that is
   already marked as `isDeleted = true` locally, the cloud response is ignored.
   This protects against delayed edge functions resurrecting a deleted entity.
   Collections absent from the cloud response and not named "Favorites" are
   deleted locally. Because step 4 guarantees every local collection is already
   in the cloud, the delete pass only removes collections the user genuinely
   deleted on another device. `syncCollectionsDown` also clears the actor's
   `cachedLocalIds` set, releasing the accumulated ID set from memory at the end
   of the sync cycle.
6. **FK Safety**: If the assigned scan UUID hasn't reached Cloudflare R2 yet
   when the collection payload arrives, the Edge node safely absorbs the
   Postgres foreign-key rejection. The collection itself is saved. On the next
   collection-sync drain the scan reference resolves.

**Collections debugging quick-check**:

- Confirm the local `ScanCollection.isDeleted` tombstone actually persisted in
  SwiftData.
- Confirm the coalesced `OfflineJobRecord(id: "collection-sync")` remains
  `pending`, `running`, or `waiting` until the newest collection mutation has
  been pushed successfully. `UserDefaultsKeys.needsCollectionSync` is only a
  legacy bridge and should not be the active scheduler authority.
- Confirm the remote `collections` row is absent after the `sync-collections`
  delete path runs.
- If a deleted collection ever reappears, inspect whether a stale upsert raced
  the tombstone or whether historical sync pulled an unexpected remote row.

**Critical ordering rule:** The collection push drain must always complete
before the pull (cloud collections fetch) in `syncHistoricalScansDown`.
Reversing this order causes local-only collections to be treated as obsolete and
deleted.

## Restoring Historical Workloads (Rehydration)

To support multi-device access and app reinstalls,
`ScanRepository.syncHistoricalScansDown(modelContext:)` pulls cloud history and
reconciles it with local SwiftData.

### Paginated Cloud Fetch

Both the scans and collections queries are paginated via Supabase PostgREST's
`.range(from:to:)` to prevent OOM on accounts with large histories:

- Scans: pages of `MerianConfig.historicalSyncPageSize` (200) records
- Collections: pages of `MerianConfig.collectionsSyncPageSize` (100) records

Each loop runs until the returned page is smaller than the page size, indicating
the last page.

### Streaming Reconciliation (`reconcileScanPage` + `syncCollectionsDown`)

A single `HistoricalDatabaseActor` instance is created and each fetched page is
processed immediately via `reconcileScanPage(responses:)` before the next page
is fetched. This prevents the full cloud scan list from accumulating in memory —
at 10 k+ scans, the old "accumulate-then-reconcile" approach could hold 100 MB+
of `HistoricalScanResponse` structs in RAM simultaneously and trigger JetSam OOM
kills.

Each page passes through these steps inside the actor:

1. **ID Page Bounding Fetch (per page)**: Inside `reconcileScanPage`, the actor
   restricts fetching strictly down to the `responseIds` provided in the current
   PostgREST batch (typically `200` items). It shards this id-set into bounds no
   larger than 500, and explicitly issues an array intersection query
   `FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunk.contains($0.id) })`.
   _CRITICAL QUIRK: We must execute this via
   `try modelContext.fetchIdentifiers(desc)` rather than `fetch()`. On iOS 17+,
   invoking `.fetch()` via `#Predicate` natively dynamically unboxes the generic
   map behind the `@ModelActor` barrier, which completely fails to map back to
   the `typealias LocalScanRecord` (crashing with
   `Failed to cast model MerianSchemaV22... to LocalScanRecord`). Extracting
   identifiers safely and individually reinstantiating
   `modelContext.model(for: id)` is completely immune to this macro casting
   panic._
2. **`updateExistingScans`**: Receives only the local record sets securely
   matched from the previous bounding fetch. Updates: `localImagePath`,
   `additionalImagePaths`, `referenceImageUrl`, GPS fields, `locationName`,
   taxonomic ranks (`taxonomyKingdom` through `taxonomyGenus`), and
   `customTags`. Backfills `imageQualityScore` when the local value is `nil` and
   the cloud `HistoricalScanResponse.image_quality_score` is non-nil
   (one-directional — never overwrites an existing local value). Saves only if
   any field actually changed. Note: Overwriting `customTags` defaults to
   cloud-wins reconciliation, erasing offline-only tag additions if they failed
   to push before the downward sync.
3. **`ingestScans`**: Inserts new `LocalScanRecord` rows for cloud records
   absent locally entirely. Checkpoint-saves every
   `MerianConfig.ingestCheckpointInterval` (50) records to limit data loss if a
   background task is killed mid-ingest. _Crucially, it defaults
   `hasBeenViewed: true` when instantiating the record to prevent re-installing
   users from being inundated with thousands of "New" badges on their historical
   archive._
4. **`syncCollectionsDown`**: Called once, after all scan pages have streamed.
   Delegates to `syncCollections` (fetches only the `ScanCollection` records and
   local scan references; upserts collections _except_ those marked as
   `isDeleted` locally which block cloud overrides). It differentially merges
   scan relationships to protect offline queued scans from being overwritten,
   and deletes obsolete non-Favorites collections. `syncCollections` now builds
   its existing-membership map from `LocalScanRecord.collections` rather than
   traversing `ScanCollection.scans`, keeping reconciliation aligned with the
   zero-OOM scan-side relationship rule. **Precondition**:
   `syncHistoricalScansDown` always drains pending uploads through
   `OfflineQueueManager.drainCollectionSyncIfPossible()` before this step so
   that the cloud collection list already contains every local collection
   mutation — the delete pass therefore only removes genuine remote deletions,
   never unsynced local creations.

### Lifecycle Execution Hook

This synchronization fires the moment a user transitions from Ghost →
Authenticated (inside `SupabaseManager.setupAuthStateListener`) and whenever the
app recovers foreground state (`AppDIContainer.handleActivePhase`).

### Ghost-Rendering Image Optimization

Historical scans restore their Cloudflare R2 URLs directly into `localImagePath`
and `additionalImagePaths` when the physical photo is absent locally.
`LocalImageLoader` evaluates HTTP boundaries implicitly. Eligible durable R2
URLs first consult the process-local recovery registry for a surviving Documents
file established by exact filename, read-only rescue-store alignment, or
constrained timestamp grouping. Without a match, the loader routes the bounded
async network fetch transparently so the user downloads only what is on screen.
A local recovery hit can enqueue authenticated cloud repair that promotes a new
object and atomically updates Scan and Explore references; it does not change
offline-queue inference ownership.

### SwiftData Typealias UI Quirks

When building UI that references the `LocalScanRecord` typealias, **never attach
a `#Predicate` to a `@Query` property wrapper directly** if the predicate
executes string evaluations across the versioned schema boundaries. The same
internal macro resolution that faults in the background actor will crash the
Main thread upon unboxing `_wrappedValue`. Instead, fetch unbounded records and
filter locally:

```swift
@Query(sort: \.timestamp) private var rawRecords: [LocalScanRecord]
private var cleanRecords: [LocalScanRecord] { rawRecords.filter { $0.isBiological } }
```

## Centralized Configuration (`MerianConfig`)

All magic numbers governing the sync pipeline live in `MerianConfig.swift`
(Core/Utilities):

| Constant                              | Value  | Purpose                                                              |
| ------------------------------------- | ------ | -------------------------------------------------------------------- |
| `uploadBatchSize`                     | 5      | Scans dispatched per sync cycle                                      |
| `pendingScanFetchLimit`               | 50     | `OfflineQueuedScan` records fetched per cycle                        |
| `mediaStagingMaxFilesPerRequest`      | 6      | Media files allowed by `generate-upload-urls` per request            |
| `mediaStagingMaxVideoFilesPerRequest` | 1      | Video files allowed by `generate-upload-urls` per request            |
| `stagedImagePayloadMaxBytes`          | 5 MB   | Maximum staged image bytes fetched by edge inference                 |
| `audioPayloadMaxBytes`                | 2.7 MB | Maximum inline or staged audio bytes accepted for inference          |
| `videoPlaybackExpectedMaxBytes`       | 3 MB   | Client-side target for preferred compressed Pro video playback clips |
| `videoPayloadMaxBytes`                | 12 MB  | Hard maximum staged video bytes accepted for persistence             |
| `historicalSyncPageSize`              | 200    | Records per page for scans rehydration                               |
| `collectionsSyncPageSize`             | 100    | Records per page for collections rehydration                         |
| `ingestCheckpointInterval`            | 50     | SwiftData save frequency during bulk ingest                          |

## 2026-04 Hardening Updates

- Offline scan completion now preserves the user’s original capture timestamp
  all the way through `processAndCleanupOfflineScan`. Replayed scans no longer
  jump to the top of the library purely because they synced later.
- The deletion side of the offline pipeline now follows a strict order: persist
  `PendingCloudDeletionTask` + local row deletion first, then remove local media
  after the SwiftData save commits.
- `InferenceEngine` cancellation now clears stale pending background DB writes
  before the next scan starts, which prevents old offline cleanup/hydration work
  from leaking into a new session.

## 2026-05 Queue I/O Update

- `deleteQueuedScan`, `purgeSoftDeletedRecords`, and `enqueueCapture` now funnel
  disk cleanup and queued media writes/adoption through `FileIOActor`, not
  inline main-actor `FileManager` calls.
- Collection reconciliation is now scan-driven: use
  `LocalScanRecord.collections` projections for membership diffs instead of
  traversing `collection.scans`.
- Queue mutations now use rollback containment: failed queue saves roll back
  pending SwiftData changes, refund any just-consumed free quota, and keep
  external side effects behind committed local state.
