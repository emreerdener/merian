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
