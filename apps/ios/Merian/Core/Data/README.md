# Core Data

The `Data` directory manages the local persistence and offline-first data pipeline.

## Purpose
This area acts as the source of truth for app data. It encompasses SwiftData configurations, the `HistoricalDatabaseActor` for cloud sync reconciliation, and the `OfflineQueuedScan` persistence mechanism. It ensures that data remains durable even when inference fails or network connectivity is absent.
