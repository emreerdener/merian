# Core Data

The `Data` directory manages the local persistence and offline-first data pipeline.

## Purpose
This area acts as the source of truth for app data. It encompasses SwiftData configurations, the `HistoricalDatabaseActor` for cloud sync reconciliation, and the `OfflineQueuedScan` persistence mechanism. It ensures that data remains durable even when inference fails or network connectivity is absent.

## Store Recovery

`StoreRecovery/` owns launch-time SwiftData store repair. It is deliberately part of Core Data, not app shell code, because recovery policy belongs to local persistence.

- `ModelStoreRecoveryCoordinator` decides whether a `ModelContainer` startup failure is a verified SQLite/Core Data corruption case.
- Only confirmed corruption may quarantine `default.store`, `default.store-shm`, and `default.store-wal`.
- Non-corrupt failures on legacy migration strategies may archive those same artifacts under `store-rescue/` before Merian rebuilds a fresh persistent store.
- Each quarantine or rescue directory includes `recovery-manifest.json` with app/build/OS metadata, archive reason, moved artifact names, and a sanitized error reason for support.
- Store recovery must never reference `KeychainManager`, `SupabaseManager`, sign-out flows, device identity resets, or profile state.
