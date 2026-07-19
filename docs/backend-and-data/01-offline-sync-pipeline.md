# The Offline Synchronization Pipeline

Naturebook's core differentiator is treating off-grid nature encounters as a
first-class citizen using native Apple offline architecture.

## How the Queue Works

### 1. Realtime Inference Mapper (`saveLiveScanRecord`)

When a user scans a subject with an active network connection, the Gemini
response cascades back from the Edge node. To persist this inference against iOS
RAM loss,
`BackgroundDatabaseActor.saveLiveScanRecord(mappedData:localImagePaths:observationContextsJSON:audioFilePaths:mediaTimeline:)`
is invoked on its isolated `@ModelActor` thread. It accepts the current ordered
mixed-media timeline plus the image/audio/context arrays derived from that same
source, writes both the scalar `capturedMediaJSON` read mirror and the V41
`capturedMediaEntries` relationship mirror, then inserts a `LocalScanRecord` and
calls `modelContext.save()`.

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

1. A stable `scanId` UUID is generated. This UUID is shared by both the offline
   queue record and the concurrent live inference request.
2. `enqueueCapture(imageDatas:displayImageDatas:audioFilePaths:videoFilePaths:telemetry:blurScore:scanId:observationContexts:mediaTimeline:visualMediaItems:startSyncImmediately:onQueued:)`
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
   `OfflineQueuedScan` and submitted to `/update-scan-context`; background replay
   can still backfill missing historical context before its own inference
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
   saving battery and tokens by recognizing that live inference would
   inevitably result in a network timeout.
5. Concurrently (if online and the submission is an eligible live-camera still
   with no audio or video), a `Task {}` gives the pre-fetched
   `EnvironmentContext` (GPS + WeatherKit/geocoding, started at shutter press)
   at most **150 ms** to finish. If that grace period expires, it fires
   `InferenceEngine.analyze(scanId:imageDatas:...)` with shutter-time
   coordinates, date/time, distance, and cached telemetry. The late context is
   merged through the authenticated deferred-context endpoint and never causes
   a second identification request. This is the **live inference path** — it delivers results faster
   than the background upload + Gemini round-trip, directly to the open insight
   sheet. Before calling `analyze()`, the Task checks
   `pendingAnalyzeScanId == scanId` on the main actor — a property set on
   `CaptureWorkspaceViewModel` at scan submission time. If a newer scan has been
   submitted in the interim (overwriting `pendingAnalyzeScanId`), the Task
   returns without calling `analyze()` and the offline queue handles the scan
   independently. This replaces the weaker `guard isProcessing` that only
   detected completion (not supersession).

Gallery images and audio-bearing or video visual submissions keep the existing
full-context wait and immediate queue-sync race in this first optimization pass.
They still emit the same pipeline timing instrumentation.

For an eligible live-camera still, the live inference path owns the uplink
initially. The durable background path
is handed off as soon as the inline request body has finished sending:

- **Deferred background start**: `OfflineQueueManager` excludes the active live
  `scanId` from normal pending batches. `MerianRequestUploadDelegate` observes
  request-body progress and releases the row when all bytes are sent. A
  two-second fail-safe handles transports that do not provide progress callbacks.
- **Single inference owner**: recovery media may stage after that handoff, but
  `foregroundInferenceScanIds` prevents staged replay from dispatching a second
  identification while the foreground request still owns the scan.
- **Immediate recovery start**: request failure, connectivity loss, or app
  backgrounding releases both the upload hold and foreground inference claim.
  The suppression is process-local, so app termination/relaunch also leaves the
  durable row eligible for normal synchronization. Before a staged row starts
  background inference, it checks `/check-scan-status`; a processing/finalizing
  foreground ingestion remains server-owned and is polled instead of issuing a
  duplicate model call.
After handoff, either path can finish first:

- **Live wins**: `analyze()` calls
  `OfflineQueueManager.shared.deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:)`
  on success, which cancels any in-flight URLSession tasks, removes the
  SwiftData record, deletes queue-only inference frames, and preserves media
  adopted by the final `LocalScanRecord`.
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
`AppTelemetry.trackOfflineQueued()` fires a `ScanQueuedForSync` PostHog event
to measure offline usage rate. If the save fails, the main context rolls
back, any consumed free-tier quota token is refunded, and staged files are
deleted without dispatching sync.

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

Still-image descriptors may also contain an optional normalized `focusRegion`.
The existing `visualMediaItemsJSON` field preserves it across queued upload and
replay without a SwiftData migration. `QueuedScanContext` snapshots the same JSON
so an analyzing queued Insight can render the identical region without touching
a live SwiftData model. Focus coordinates are transient and are not copied onto
completed scan records.

**UI Surface**: While a scan awaits network transit, its `OfflineQueuedScan`
record is rendered at the **top** of the Scans Library grid (`ScansGrid`) with a
dark overlay that reflects online, retry-wait, and needs-attention states.
Tapping a queued tile opens `InsightSheetView` in analyzing mode via
`LibraryView`. Queued scans are excluded from batch-selection mode; their IDs
cannot enter the `Share` / `Download` / `Delete` pipeline. `QueuedScanSnapshot`
and `QueuedScanContext` carry copied retry metadata (`queueNextRetryAt`,
friendly last error, media kinds, retry availability, and approximate queued
bytes) so the sheet can render after SwiftData rows are updated or deleted.

**Value-Type Snapshot Pattern** — `ScansGrid` never holds a live
`OfflineQueuedScan @Model` reference. When `ScansSheetView.refreshQueuedScans()`
fetches pending scans, it immediately maps them to `[QueuedScanSnapshot]`
value-type structs while the objects are live. `LazyVGrid` renders tiles from
this snapshot array — after `context.delete(scan)` fires, no grid tile can
access a zombie `@Model` attribute. When the user taps a queued tile, a fresh
`OfflineQueuedScan` is fetched and snapshotted into `QueuedScanContext` (a
richer value type with all telemetry and queue fields) before the
`InsightSheetView` is presented. `QueuedScanSnapshot.gridId` returns `"q_\(id)"`
to prevent duplicate `ForEach` keys against `LocalScanRecord` tiles that share
the same UUID.

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

**Free User Quota Enforcement**: Quota is enforced at enqueue time, not at
upload time. Inside `insertAndPersistRecord`,
`UsageManager.shared.canPerformScan(isProActive: false)` is checked before the
`OfflineQueuedScan` record is inserted. If the daily limit is exhausted, the
scan is rejected and any files already written to disk are cleaned up atomically
— `AppTelemetry.trackOfflineQueued()` is **not** fired in this case. If the
quota check passes, `UsageManager.shared.consumeScan()` reserves the slot before
the record enters the queue; if the subsequent SwiftData save fails,
`modelContext.rollback()` runs and `UsageManager.shared.refundScan()` restores
the slot. This ensures every scan that reaches `syncPendingScans` is already
paid for and is uploaded without further quota checks, while failed local
inserts do not charge the user. Non-biological outcomes are still successful
scan attempts and are not refunded. The non-biological correction entry point
may bypass the Pro-only reanalysis feature lock, but once the user submits that
replacement capture it still consumes normal free-tier daily quota and uses the
normal free inference settings.

### 3. Network Awakening (`NWPathMonitor`)

The `NWPathMonitor` instance listens to the cellular stack continuously. When a
connection flips `.satisfied`, the manager debounces for **3,000 ms** to let the
OS networking stack fully settle before starting processing. The 3-second window
covers the typical WiFi → cellular → WiFi handoff sequence, which fires 3–4
`NWPathMonitor` events within ~2 seconds — the 1-second window previously fired
sync on the first cellular `satisfied` event before the preferred interface was
fully associated. After the debounce resolves, sync is additionally skipped when
`monitor.currentPath.isConstrained` is `true` (iOS Low Data Mode), preventing
aggressive batch uploads on metered connections.

Connectivity restore now enters through `OfflineJobScheduler`. The scheduler is
the durable control-plane facade; it delegates scan ingestion to
`OfflineQueueManager`, cloud deletion to `PendingCloudDeletionTask`, and
collection sync to a coalesced `OfflineJobRecord`. Existing executors remain in
place, but retry ownership is no longer process-local: each job stores attempt
counts, last errors, next-run times, server status/stage, and user-attention
state in SwiftData.

### 4. Background Processing & Batch Uploads

The manager guards against expedition mode, connectivity, and an in-flight sync
before proceeding. Every scan in the queue at this point has already passed the
quota check and had its token consumed at enqueue time — `syncPendingScans` has
no quota involvement and uploads all queued scans unconditionally.

`SyncStateManager.shared.beginSync(itemCount:)` is called to transition the
shared state machine to `.uploading(count:)` and broadcast the exact batch
volume to the UI.

Batch sizing is governed by `MerianConfig`:

- **`pendingScanFetchLimit`** (50): maximum `OfflineQueuedScan` records fetched
  per cycle via `BackgroundDatabaseActor.fetchPendingScans(limit:)`.
- **`uploadBatchSize`** (5): maximum scans considered for R2 staging per cycle.
  The selected scan batch is additionally capped by
  `MediaStagingContract.maxUploadItemsPerRequest` /
  `MerianConfig.mediaStagingMaxFilesPerRequest` to the `generate-upload-urls`
  limit of 6 media files total. This covers the canonical Pro video shape
  (five sampled inference frames plus one playback clip) while keeping mixed
  scans inside the pre-signed URL contract.
- **`mediaStagingMaxAudioFilesPerRequest`** (2): maximum audio files in one
  upload-signing request, matching the Edge parser and the documented
  cross-language contract in
  `docs/contracts/media-staging-upload-manifest.json`.
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
`URLSession.uploadTask(with:fromFile:)`. Image uploads use
`Content-Type: image/webp`; audio uploads use `audio/wav` or `audio/mp4` based
on extension. These must match the Content-Type baked into the Cloudflare R2
pre-signed URL by the `generate-upload-urls` Edge function. The Edge function
now consumes the full `files` manifest (`fileName`, `mediaKind`, `contentType`,
`sizeBytes`, `clientScanId`, `mediaRole`) instead of inferring type from
extensions, creates staged `scan_media_assets` rows for scan media, and
validates the manifest before signing. The OS background session owns byte
transmission from here, handling interruption and resume transparently. The
scheduled `replay-scan-ingestion` worker can later retry staged
media/audio/video or description-only scans whose `scan_ingestion_intents` are
resumable, so an app exit after successful upload does not leave the phone as
the only recovery path. The scheduled `reconcile-scan-media-assets` worker can
repair stale staged media when the scan row already exists, or clean abandoned
upload-session objects after their TTL. Before cleanup, reconciliation checks
the server `scan_ingestion_jobs` row keyed by the same user and
`client_scan_id`: active leases and future `retry_after` windows keep staged
media pending, repaired scans can mark their job complete once required playback
video media is present, and abandoned media marks the job terminal for status
polling. Inline foreground requests still depend on the iOS queue because raw
media bytes are not stored in replay intents. Queue diagnostics can be exported
through `OfflineQueueManager.writeQueueDiagnosticsExport(eventLimit:)`; the JSON
contains jobs, redacted scan queue metadata, and bounded event rows only, never
raw media paths or private media bytes.

**`MediaStagingContract` + `ScanUploadItem`** (defined in
`OfflineSyncTypes.swift`): The flat arrays previously used to pass per-image
metadata (`fileNames`, `fileURLs`, `scanIDs`, `imageIndices`) have been
consolidated into a typed staging manifest. Each `ScanUploadItem` carries
`scanId`, `uploadIndex`, `mediaKind`, `localPath`, sanitized `fileName`,
`fileURL`, `contentType`, expected `objectKey`, and a `StagingUploadFile`
request DTO carrying `sizeBytes`, `clientScanId`, and `mediaRole` together,
eliminating the class of flat-index bug where indexing into parallel arrays at
position `N` could silently return mismatched values for mixed-media batches.
URLSession upload task descriptions now use `upload|{scanId}|{uploadIndex}`
through the same contract, preserving scan IDs that contain underscores while
retaining legacy parser support for already-created tasks. Staged image roles
are a signing-time hint; final user-visible media still comes from the saved
`captured_media` manifest and ready `scan_media_assets` rows.

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
starts. `submitNonVisualCapture` consumes that prefetched value before inserting
the durable queue row, or resolves `lastKnownLocation` as a fallback for entry
paths without a recording-time prefetch. Therefore the queue row, live request,
and eventual `LocalScanRecord` share the same GPS, `locationName`, weather, and
capture-time context. This is required for later Explore publication because
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

**Startup reconciliation & ongoing orphan recovery**: On first connectivity
restore per process life, `replayInferenceForUploadedScans` runs a gated
cold-start `reconcileOrphanedUploadingScans(activeScanIds:)` that
cross-references pre-existing URLSession tasks (safe only before any new upload
tasks are dispatched). `reconcileOrphanedUploadingScans` returns `Bool` — `true`
if at least one orphan was reset. The cold-start callback calls
`syncPendingScans()` **only when the return value is `true`**. This is critical:
the initial `syncPendingScans()` call from `handleActivePhase` runs before the
cold-start reconcile completes (the reconcile is async), so it finds no
`.pending` scans (the orphaned scan is still `.uploading` at that moment).
Without calling `syncPendingScans()` after the reconcile, the reset scan would
sit in `.pending` indefinitely — there is no subsequent trigger until the next
connectivity change or foreground. Guarding on the return value prevents a
spurious second sync in the common case (no orphaned uploads). On every
subsequent call it also runs `reconcileOrphanedUploadingScans` again via a
live-task cross-reference — this catches `.uploading` orphans created
mid-session when `generateUploadURLs` fails or the `syncPendingScans` Task is
killed before its catch block can run, and resets them to `.pending` so the next
retry can pick them up. Additionally, on every call it runs
`reconcileOrphanedInferencingScans(activeInferenceScanIds:)` which
cross-references live background URLSession inference tasks (`"inference_*"`
task descriptions) before resetting `.inferencing → .staged`. This replaces the
old blind `resetOrphanedInferencingScans()` — a background download task for
inference can survive app suspension and re-attach after a relaunch, so blindly
resetting all `.inferencing` scans would dispatch a duplicate inference task
against a scan already owned by a live OS task. Transient inference failures
reset the scan back to `.staged` (via `transitionScanToStaged(id:)`) so
`replayInferenceForUploadedScans` can reclaim it on the next connectivity
restore. `transitionScanToStaged` is source-state guarded — it only writes if
the scan is currently `.inferencing`, preventing a concurrent
`softDeleteQueuedScan` tombstone from being overwritten by a background actor
that resolves slightly later.

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
bytes are not stored; if a foreground request
used inline base64 media, the intent is marked non-resumable and the iOS queue
remains the recovery source. The scheduled `replay-scan-ingestion` worker claims
due resumable jobs, reconstructs the staged request, and invokes
`/identify-multimodal` with the same `client_scan_id`. `insertScan` still uses
an upsert with `onConflict: "id", ignoreDuplicates: true`, so a replayed
inference request for an already-inserted scan is a silent no-op rather than a
duplicate-key error, while the job ledger plus intent lets status polling,
reconciliation, and server replay distinguish the same-media retry from a
changed media shape for the same scan id.

> **Critical**: The `taskDescription` for each upload task is
> `"\(scanId)_\(uploadIndex)"` where `uploadIndex` is the per-scan media slot
> across the canonical upload list. It must NOT use the flat position across the
> entire batch. `processUploadCompletion` triggers the inference pipeline by
> explicitly scanning `session.allTasks` to verify that no active chunks sharing
> that exact `scanId` prefix are still in-flight. Because iOS multiplexed HTTP/3
> background tasks can complete out-of-order, relying on
> `indexPart == count - 1` previously caused widespread deadlocks where the
> final chunk triggered before prior chunks, permanently stranding the
> `OfflineQueuedScan`!

**Concurrent staging (`withTaskGroup`)**: Pre-flight guards — URL validation,
file existence checks, and tombstoning — remain serial. Once all guards clear,
the `FileManager.copyItem` and `uploadTask` creation for each image are fanned
out concurrently via `withTaskGroup`. For a 3-image scan this eliminates 500
ms–2 s of head-of-line blocking before the background session takes ownership.

**Bounded backoff for `generateUploadURLs` failures**: When the pre-signed URL
request fails, `syncPendingScans` first calls
`reconcileOrphanedUploadingScans(activeScanIds:)` to reset any `.uploading`
scans — which were transitioned before `generateUploadURLs` was called — back to
`.pending`. Without this reset those scans would be invisible to the retry since
`fetchPendingScans` only returns `.pending` records. After the reset, each
affected scan records durable retry metadata through `OfflineQueueRetryPolicy`.
Retries use jittered backoff capped by `maximumRetryDelay`; once
`maximumAutomaticRetryAttempts` is exhausted, the queued scan is marked
`queueNeedsAttention` instead of scheduling another process-local retry. The
retry task is cancelled immediately on connectivity loss so stale retries never
fire while offline.

All this payload work runs inside a `BackgroundTaskWrapper.execute` block so iOS
does not suspend the process during disk I/O or URL generation. The expiration
handler for this block **must reset `isSyncing = false`** before calling
`SyncStateManager.shared.completeSync()`. If iOS expires the background task
before the URLSession upload tasks are dispatched (e.g., during extreme memory
pressure), `isSyncing` would otherwise stay `true` permanently, permanently
blocking all future `syncPendingScans()` calls until the next app relaunch.
Furthermore, if OS-level caching attempts totally fail locally (generating
exactly 0 HTTP transfer tasks), the `withTaskGroup` drops the `isSyncing` lock
dynamically—circumventing the dead `urlSessionDidFinishEvents` delegate path.

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
  - **HTTP 401 / 403 and other permanent 4xx**: mark `queueNeedsAttention`. The
    user media is not silently deleted after a fixed retry count.
  - **HTTP 200**: Evaluates the image against `session.allTasks` to ensure it is
    the _final_ chunk completing, then calls `dispatchInferenceDownloadTask()`.

  > **Retry durability**: `uploadRetryCount` is no longer the source of truth.
  > Retry ownership lives on `OfflineQueuedScan.queue*` fields and the paired
  > `OfflineJobRecord`. Automatic scan-ingestion retries are capped by
  > `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`, use jittered
  > backoff up to `maximumRetryDelay`, and then move to `queueNeedsAttention`.
  > A process kill no longer resets retry history or deletes user media after
  > three local failures. Successful upload/inference paths clear retry metadata;
  > server-owned work persists `job_status`, `job_stage`, and `retry_after` from
  > `/check-scan-status`.
  > Server-side resumable replay is also bounded: after 10 replay claims for the
  > same sanitized intent, `claim_replayable_scan_ingestion_jobs` marks the job
  > `failed_terminal` at `server_replay_limit_reached`.

  > **Failed Upload Notifications**: Any pathway that natively tombstones a
  > queue payload (due to transient exhaustion, HTTP 4xx permanence, or explicit
  > file-system corruption) proactively fires a
  > `PushNotificationManager.shared.sendUploadFailedNotification()` alert
  > containing an isolated `{"type": "failure"}` payload if the application is
  > currently backgrounded, allowing the user to gracefully intercept lost sync
  > cycles without inadvertently routing to deleted `InsightSheet` indices.
- **Step D**: `dispatchInferenceDownloadTask(scanId:extracted:)` fetches
  historical weather (if absent), builds an authenticated `URLRequest` via
  `MerianNetworkClient.buildMultiModalRequest(...)`, and issues a **background
  URLSession download task** (`backgroundSession.downloadTask(with: request)`).
  The task's description is `"inference_{scanId}"`.
  `SyncStateManager.shared.beginInferencing()` transitions the state machine to
  `.inferencing`. The inference download is suppressed until the **last** media
  file for the scan has landed (guarded by the strict `session.allTasks`
  lookahead filter validated in Step C), preventing partial-payload submissions.
  The request body is small for queued media: images travel as `r2ObjectKeys`,
  audio travels as `audioR2ObjectKeys`, and only descriptions/telemetry are
  inline. Because this is a background URLSession download task (not a data
  task), iOS can deliver the response body even while the app is completely
  suspended. To pass the server's case-sensitive IDOR block, the
  deterministically awaited user UUID embedded within the R2 keys is strictly
  lowercased. Weather backfill is persisted to `OfflineQueuedScan` via
  `BackgroundDatabaseActor.updateScanTelemetry` before dispatch so the delegate
  can read hydrated telemetry from SwiftData on result delivery.
- **Step E (background)**: When the inference download task completes,
  `urlSession(_:downloadTask:didFinishDownloadingTo:)` fires. The temp file is
  immediately copied to a stable path and
  `processInferenceDownloadResult(scanId:resultFileURL:statusCode:)` is invoked
  inside a `BackgroundTaskWrapper`. `SyncStateManager.shared.beginFinalizing()`
  transitions to `.finalizing`.
  `BackgroundDatabaseActor.processAndCleanupOfflineScan` decodes the JSON,
  inserts `LocalScanRecord` when confidence is positive, writes
  `audioFilePaths`, `videoFilePaths`, and `capturedMediaJSON`, and calls
  `modelContext.save()`. The background actor intentionally does not delete the
  `OfflineQueuedScan`; after the save succeeds, `processInferenceDownloadResult`
  calls `deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:)` on the main
  actor. That main-context deletion still provides the reliable `@Query`
  re-evaluation trigger for open sheets, but it also has access to the queued
  row before deletion, so it can delete `inferenceImagePaths` and other
  queue-only files while preserving display images, video clips, and audio files
  adopted by the saved `LocalScanRecord`. If the background save fails,
  `wasCleaned` is `false`, no push/discovery/hydration side effects fire, and
  the queue record remains retryable. If the main-context delete fails, final
  user-facing side effects stay suppressed until a later retry can commit
  cleanup. On zero-confidence HTTP 200 responses no `LocalScanRecord` is
  inserted; successful queue deletion removes the queued row and purges its
  media footprint. Inference download task failures and non-200 HTTP responses
  route through `handleInferenceTaskNetworkFailure(scanId:error:)` before
  entering `handleInferenceRetry(scanId:)`. `NSURLErrorCancelled` (Code=-999) is
  short-circuited because it is produced when an owner path cancels background
  work after live inference already succeeded or the user deleted the queued
  scan. Before scheduling a retry, `handleInferenceRetry` calls
  `MerianNetworkClient.shared.checkScanStatusDetails(scanId:requiredVideoCount:)`
  (POST `/check-scan-status`) to probe whether the scan already landed in
  `public.scans` or is still owned by a server ingestion job. For queued video
  scans, `requiredVideoCount` is the count of video entries in the queued
  captured-media timeline, so a frame-only cloud row does not count as
  recovered. When the poll returns `found`, targeted historical sync pulls the
  server row immediately, `deleteQueuedScan` removes the queue entry, and
  durable retry metadata is cleared. When the row is not found but the job is
  still `processing`, `finalizing`, or `retrying`, the local row stays
  `.inferencing` and another server poll is scheduled. `failed_retryable` honors
  the server `retry_after` before returning the row to `.staged`; terminal
  failure marks the queue row as needing attention. Unresolved `not_found`
  responses or status-probe failures fall back to the same persisted retry budget
  (`OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts`) used by upload
  staging, rather than a separate process-local attempt counter.

  **InferenceEngine hydration (background-wins race)**: After the shared scan
  milestone coordinator task is started, if `processingResult.speciesData` is non-nil,
  `processInferenceDownloadResult` checks whether `InferenceEngine` is still
  mid-flight for the same scan
  (`engine.isProcessing == true && engine.activeScanId == scanId`). When this is
  true, the background URLSession path has raced ahead of the suspended live
  `InferenceEngine.analyze()` task — which happens when the user backgrounds the
  app immediately after capture. In that case the live task is cancelled
  (`engine.inferenceTask?.cancel()`), `engine.isProcessing` is set to `false`,
  and `engine.speciesData` is set to the already-decoded `SpeciesData` from the
  database actor. This prevents the live task from resuming after foregrounding,
  finding a cold network, and showing "Network timeout" on a scan whose result
  is already committed to the database. The insight sheet's `InsightContentView`
  observer (`isProcessing == false && speciesData != nil`) transitions out of
  "Analyzing..." mode immediately.
- **UUID Terminality**: `OfflineQueueManager` strictly awaits the resolved
  finalized database UUID from `dbActor.processAndCleanupOfflineScan()` (the
  "Terminal ID"). This effectively terminates the ephemeral offline properties
  forever. Downstream notifications or `.appDidEnterActivePhaseWithScan` routes
  ALWAYS execute traversing the Terminal ID, guaranteeing user interactions bind
  directly to `.biological` persistence blocks instead of ghost records.
- **Long-lived actors**: `BackgroundDatabaseActor` and `ProfileDatabaseActor`
  are now stored as persistent properties (`_inferenceDbActor`,
  `_profileDbActor`) on `OfflineQueueManager` and initialized lazily on first
  use. Reusing a single actor instance across consecutive completions avoids
  repeated actor allocation + `ModelContext` setup. Each `@ModelActor`
  serializes concurrent calls through its executor automatically, so rapid burst
  completions queue safely. `resolvedInferenceDbActor(container:)` tracks the
  container that owns the cached actor (`_inferenceDbActorContainer`). If the
  caller provides a different container, the cache is invalidated and a fresh
  actor is created. In production the container is a process-lifetime singleton
  so this is a no-op; in tests each suite creates a fresh in-memory container,
  and the identity check ensures a stale actor bound to a previous test's
  already-deallocated store is never returned.
- **Step F**: `GamificationManager.shared.recordNewSpeciesDiscovered()` and the
  inference-complete push notification fire immediately per completion. The
  final database scan ID, decoded `SpeciesData`, and model container then enter
  `ScanMilestoneCoordinator`, the same boundary used by foreground inference.
  The coordinator deduplicates foreground/background races by final scan ID,
  waits for remote persistence and the Field trip progress attempt, publishes
  progress refresh events, calculates newly eligible achievements without
  immediately presenting them, and atomically enqueues standard outing
  progress, Events-visible Seasonal Challenge progress, achievements, then
  **New to Naturebook**. A failed or no-match progress attempt releases the
  later milestones only after it finishes. Award calculation is per final scan
  rather than process-lifetime burst-debounced, because strict notification
  ordering and scan-level deduplication are now the contract. The
  `UserDefaultsKeys.hasUnseenScan` flag is set to trigger the MainTabBar red
  dot, **unless** `suppressInferenceBanners` is `true` (the insight sheet is
  open and the user is watching the transition to results — setting the badge in
  that case would cause it to appear and immediately need clearing on sheet
  dismiss). The push notification is scheduled unconditionally via
  `PushNotificationManager.shared.sendInferenceCompleteNotification` —
  foreground banner suppression is delegated to
  `PushNotificationManager.willPresent`, which reads `suppressInferenceBanners`
  and either presents the banner or delivers silently based on whether the
  insight sheet is currently visible.

**Wireless Offline Weather Hydration (Pre-Dispatch)**: If the scan was captured
without a network connection and lacks `weatherCondition`,
`dispatchInferenceDownloadTask` calls
`EnvironmentContextManager.shared.fetchHistoricalContext(location:date:)` using
the stored GPS coordinates and capture timestamp to reconstruct the weather
context for that moment, **before** the background download task is dispatched.

Weather backfill must happen at task-creation time because there is no async
opportunity to fetch it after the OS takes ownership of the suspended background
task. The hydrated values are persisted to `OfflineQueuedScan` via
`BackgroundDatabaseActor.updateScanTelemetry` so the
`urlSession(_:downloadTask:didFinishDownloadingTo:)` delegate can re-read them
from SwiftData on result delivery — even after a relaunch. The inference request
carries the weather data in its JSON body.

Previously, WeatherKit and the foreground inference call ran concurrently via
`async let` inside `runInferencePipeline`. That was only viable when inference
was a foreground `await` — background URLSession tasks are fire-and-forget, so
the weather data must be embedded in the request at dispatch time rather than
injected on the fly.

When all background upload tasks settle,
`SyncStateManager.shared.completeUploadPhase()` transitions to `.idle` if no
inference pipelines are active. If `unsyncedItemsCount > 0` after a batch,
`syncPendingScans()` is called recursively to drain the queue automatically.

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

**Concurrent pipeline safety**: `SyncStateManager` tracks an internal
`activeInferenceCount`. `beginInferencing()` increments it; `completeSync()`
decrements it and only transitions to `.idle` when the count reaches zero. This
prevents a burst of concurrent scans from prematurely clearing the sync
indicator when the first pipeline completes while others are still in
`.inferencing` or `.finalizing`. Upload-path completions use
`completeUploadPhase()` (which never touches the count) rather than
`completeSync()`. Connectivity-loss resets use `forceIdle()` to immediately zero
the count and clear the phase regardless of how many pipelines were in flight.

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
   immediately; retry on next connectivity cycle.

### 2. Cloud Deletion Tasking (`PendingCloudDeletionTask`)

A `PendingCloudDeletionTask` SwiftData record is inserted at deletion time,
queuing the `scanId` for cloud erasure. The UI executes an optimistic delete
immediately.

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

`NetworkError.invalidResponse` (resource already gone) is treated as terminal
and the task is removed. All other errors retain the task for the next cycle
until `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts` is exhausted; the
paired `OfflineJobRecord` then moves to `needsAttention` and is no longer
runnable. The result-processing loop builds a `[String: PendingCloudDeletionTask]`
dictionary once before iterating results, making each lookup O(1) instead of the
previous O(n) linear scan (was O(n²) overall for large batches).

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
   for all owned incoming collections with one paginated
   `.in("collection_id", ownedIds)` query ordered by `(collection_id, scan_id)`,
   not one round trip per collection. Only the delta (rows to add and rows to
   remove) is written. We intentionally do not use implicit destructive diffs
   for whole collections to prevent devices with missing histories from
   obliterating remote databases. The Edge function actively pre-filters any
   mappings for scans that haven't synced to the cloud yet, preventing Postgres
   FK constraint violations from aborting the overarching database chunk.
   Removals are grouped by `collection_id`. A `MAX_COLLECTIONS = 200` cap is
   enforced server-side.

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
   > `supabaseClient.auth.getUser()`; latency-sensitive identify/deferred-context
   > routes use the cached-JWKS `getClaims(token)` path with explicit claims
   > validation. Both strategies natively support `ES256`.
   > Deliberately public routes such as `species-dictionary` also use
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
`LocalImageLoader` evaluates HTTP boundaries implicitly, treating remote R2 URLs
exactly like local `URL.documentsDirectory` paths — routing async cache fetches
transparently so the user downloads only what is on screen.

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
