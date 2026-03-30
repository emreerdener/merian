# Schema Update Workflow

Runbook for bumping the SwiftData schema to a new version. Follow these steps **in order** — the ordering is load-bearing.

## Why ordering matters

Every `VersionedSchema` in `MerianMigrationPlan.schemas` has a checksum computed from the model types in its `models` array. If a schema's `models` array references the global `LocalScanRecord` (or any other global model) and that global model changes, the stored checksum no longer matches, and `NSStagedMigrationManager` throws a fatal exception at app launch.

The invariant that prevents this:
- **Retired schemas (V1 … V(N-1))**: `models` references frozen snapshot types nested inside `extension MerianSchemaV{K}` — immutable, stable checksums forever.
- **Current schema (V(N))**: `models` references global types — required so all app code (`@Query`, `context.insert`, etc.) operates on the same entities as the container.

The crash happens when you modify global models WITHOUT first freezing the outgoing schema. This runbook enforces the safe ordering.

---

## Steps

### Step 1 — Freeze the outgoing schema V(N)

Open `merian/Models/Schema/SchemaV{N}.swift`. Add:

1. **A frozen `LocalScanRecord` snapshot** inside `extension MerianSchemaV{N}`:
   - Copy all fields from `merian/Models/ActiveSchema/LocalScanRecord.swift` **as they exist right now** (before you add any new fields).
   - Remove the `public` access modifier — nested schema types are internal.
   - Preserve all `@Attribute` annotations exactly.

2. **Typealiases for unchanged models** (models whose shape didn't change since V(N-1)):
   ```swift
   typealias ScanCollection           = MerianSchemaV{N-1}.ScanCollection
   typealias OfflineQueuedScan        = MerianSchemaV{N-1}.OfflineQueuedScan
   typealias PendingCloudDeletionTask = MerianSchemaV{N-1}.PendingCloudDeletionTask
   ```
   If a model DID change in V(N), add its frozen snapshot as an extension block instead.

3. **Update `models` to use fully-qualified type names** (compile-time proof the snapshot exists):
   ```swift
   static var models: [any PersistentModel.Type] {
       [MerianSchemaV{N}.LocalScanRecord.self, MerianSchemaV{N}.OfflineQueuedScan.self,
        MerianSchemaV{N}.ScanCollection.self, MerianSchemaV{N}.PendingCloudDeletionTask.self]
   }
   ```
   This causes a compile error if any snapshot is missing — you cannot ship a broken migration.

4. **Update `didMigrate` in `migrateV{N-1}toV{N}`** (if it is a `.custom` migration) to use `MerianSchemaV{N}.LocalScanRecord` instead of the unqualified global `LocalScanRecord`.

**Build the project. It must compile before you proceed.**

---

### Step 2 — Modify global models

Now it is safe to add, remove, or rename fields in `merian/Models/ActiveSchema/`:
- `LocalScanRecord.swift`
- `OfflineQueuedScan.swift`
- `ScanCollection.swift`
- `PendingCloudDeletionTask.swift`

Any model that changes here is the **only** model that needs a new snapshot in Step 1 of the next bump. Models that do not change can be typealiased.

---

### Step 3 — Create SchemaV{N+1}.swift

Create `merian/Models/Schema/SchemaV{N+1}.swift`:

```swift
import Foundation
import SwiftData

// Added: <one-line summary of what changed>
//
// NOTE: This file intentionally references global model types. The current active schema
// must reference global types so all app code operates on the same entities as the container.
// Freeze this schema when SchemaV{N+2} is created — see .agents/workflows/schema_update.md.
enum MerianSchemaV{N+1}: VersionedSchema {
    static var versionIdentifier = Schema.Version({N+1}, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
```

The global type references here are intentional and correct — this is the active schema.

---

### Step 4 — Update Aliases.swift

```swift
typealias CurrentSchema = MerianSchemaV{N+1}
```

---

### Step 5 — Add the migration stage to SchemaVersions.swift

Append to both arrays in `MerianMigrationPlan`:

```swift
// In schemas:
MerianSchemaV{N+1}.self

// In stages:
migrateV{N}toV{N+1}
```

For a **lightweight** migration (new optional field, no data transform needed):
```swift
static let migrateV{N}toV{N+1} = MigrationStage.lightweight(
    fromVersion: MerianSchemaV{N}.self,
    toVersion: MerianSchemaV{N+1}.self
)
```

For a **custom** migration (field removed, renamed, or requires backfill):
```swift
// Temporary storage — declare as nonisolated(unsafe) static var at the top of MerianMigrationPlan
nonisolated(unsafe) static var _myBackfill: [String: SomeType] = [:]

static let migrateV{N}toV{N+1} = MigrationStage.custom(
    fromVersion: MerianSchemaV{N}.self,
    toVersion: MerianSchemaV{N+1}.self,
    willMigrate: { context in
        // Read from MerianSchemaV{N}.LocalScanRecord (frozen) — the outgoing shape
        let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV{N}.LocalScanRecord>())
        _myBackfill = ...
    },
    didMigrate: { context in
        // Read from MerianSchemaV{N+1}.LocalScanRecord — but V{N+1} has no frozen snapshot yet.
        // Use the global LocalScanRecord (they are the same entity at this point).
        let allRecords = try context.fetch(FetchDescriptor<LocalScanRecord>())
        ...
        try context.save()
        _myBackfill = [:]
    }
)
```

---

### Step 6 — Add SchemaV{N+1}.swift to project.yml

XcodeGen uses glob source discovery. If the glob pattern already covers `merian/Models/Schema/`, no change is needed. Verify:

```bash
grep -A2 "Schema" project.yml | head -10
```

Run `xcodegen generate` if you added new directories.

---

### Step 7 — Build and test

```bash
xcodebuild build -scheme Merian -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test  -scheme Merian -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -only-testing:merianTests/ScanRepositoryTests
```

Both must pass before committing.

---

## Checklist

- [ ] V(N) schema file has a frozen `LocalScanRecord` snapshot (and frozen snapshots for any other changed models)
- [ ] V(N) schema file has typealiases for unchanged models pointing to V(N-1) frozen types
- [ ] V(N) `models` array uses fully-qualified `MerianSchemaV{N}.ModelName.self` references
- [ ] Any `.custom` migration's `willMigrate` uses `MerianSchemaV{N}.LocalScanRecord` (frozen), `didMigrate` uses `MerianSchemaV{N+1}.LocalScanRecord` or unqualified global type
- [ ] Global models in `ActiveSchema/` are modified AFTER the snapshot in step 1
- [ ] `SchemaV{N+1}.swift` created, referencing global types
- [ ] `Aliases.swift` updated: `typealias CurrentSchema = MerianSchemaV{N+1}`
- [ ] `SchemaVersions.swift` updated: both `schemas` and `stages` arrays extended
- [ ] Build succeeds
- [ ] `ScanRepositoryTests` pass
- [ ] `docs/backend-and-data/04-database-schema.md` updated (current active schema version, new fields documented)
