# Core Data

The `Data` directory manages the local persistence and offline-first data pipeline.

## Purpose
This area acts as the source of truth for app data. It encompasses SwiftData configurations, the `HistoricalDatabaseActor` for cloud sync reconciliation, and the `OfflineQueuedScan` persistence mechanism. It ensures that data remains durable even when inference fails or network connectivity is absent.

The active V50 schema adds `OfflineQueuedScanGoalHint`, a scan-keyed companion
that stores the optional standard-outing and checklist-item IDs selected in a
qualifying live Capture. Keeping this separate preserves the released V49 queue
entity. Foreground/background completion read the same hint, and every queued-
scan deletion or orphan repair removes it. Persistent Insight contribution
cards are server-backed and are intentionally not cached in SwiftData.

## Offline Scan Durability Boundary

A completed background PUT is evidence for one upload member, not permission to
start analysis. The generation accumulator must equal the duplicate-free exact
expected key set; missing, extra, or duplicate manifest members fail closed.
Sanitized filename and object-key collisions are rejected before signing or
upload. `BackgroundDatabaseActor.markScanAsStaged` then persists those keys,
normally resets upload retry state, updates the queue job, and transitions
`.uploading → .staged` in one save. Only `.staged` after that commit—or a
serialized owner with the same staged manifest—may proceed toward an inference
claim. The one exception is an exact scheduled server-failure retry. Its
`server_retryable_failure` marker, attempt count, and last attempt are mirrored
on `OfflineQueuedScan` and the corresponding `OfflineJobRecord`. Successful
re-stage preserves them; every serialized claim/retry/staging transition first
repairs a drifted copy from the surviving marker and monotonic maximum. A
cloud-complete recovery marker has higher authority than either retry copy. A
transient signer or PUT failure while performing that re-stage also preserves
the machine marker and increments from the maximum committed attempt; its
precise failure remains in the queue event stream.

Fetch, job-read, manifest-mismatch, or save failure returns a retry-required
outcome before inference. Once the callback token releases, timestamp-fenced
orphan reconciliation restarts signing for a still-uploading row; a staged row
replays only its persisted keys. A missing, failed, or external-import row is
discarded and never resurrected.

The replay/orphan driver is process-local single-flight. Library, scheduler,
reconnect, and URLSession completion wakes share one active reconciliation.
Wakes received while it is running coalesce into at most one trailing pass, so
state changes are not dropped without allowing duplicate status probes, orphan
transitions, retry-budget inflation, or Library log storms.

The first `failed_retryable` status observation writes that marker and
increments retry accounting atomically. After its persisted delay, only that
exact marker lets the next generation-fenced status preflight reclaim the
backend generation and dispatch Identify; all marker-free, active, completed,
manual, and terminal states still refuse duplicate inference. Marker and
attempt reads use a fresh `ModelContext`, consult both durable copies, and use
the monotonic maximum so a migrated-store snapshot cannot hide or roll back a
background-actor commit. Exhaustion keeps the row for manual attention and
cancels polling instead of cycling through signing, PUT, and status
indefinitely.
An explicit user retry resets the bounded automatic counter under the same scan
UUID before re-entering the atomic claim path. This matters for
description-only staged work, which has no successful upload transition to
reset the counter. A known cloud-complete result is the exception: manual retry
preserves its owner-result marker and cannot re-enable provider dispatch.

After foreground or background result persistence, inference-driven queue
deletion writes the scan job's `.complete` status, clears transient errors,
inserts the completed event, and removes the exact guarded queue row in one
main-context save. Explicit user/system deletion instead records `.cancelled`.
A crash or save failure therefore cannot leave successful inference durably
classified as cancellation, and local file cleanup runs only after this save.
If crash replay reaches the same proven generation after the queue row is gone,
an already-complete job is accepted without appending a duplicate completion
event.

Cloud-deletion draining uses a process-local single-flight latch in addition to
durable restartable job state. Competing scheduler, repository, and UI wake
sources therefore cannot delete the same `PendingCloudDeletionTask` object
concurrently, while process termination still leaves `.running` work eligible
for idempotent replay.

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

`StoreRecovery/` owns launch-time SwiftData store repair. It is deliberately part of Core Data, not app shell code, because recovery policy belongs to local persistence.

- `ModelStoreRecoveryCoordinator` decides whether a `ModelContainer` startup failure is a verified SQLite/Core Data corruption case.
- Only confirmed corruption may quarantine `default.store`, `default.store-shm`, and `default.store-wal`.
- Non-corrupt failures on legacy migration strategies may archive those same artifacts under `store-rescue/` before Merian rebuilds a fresh persistent store.
- Each quarantine or rescue directory includes `recovery-manifest.json` with app/build/OS metadata, archive reason, moved artifact names, and a sanitized error reason for support.
- Store recovery must never reference `KeychainManager`, `SupabaseManager`, sign-out flows, device identity resets, or profile state.
