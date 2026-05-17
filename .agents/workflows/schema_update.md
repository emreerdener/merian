# Schema Update Workflow

Runbook for bumping the SwiftData schema to a new version. Follow these steps **in order** — the ordering is load-bearing.

## Why ordering matters

Every `VersionedSchema` in `MerianMigrationPlan.schemas` has a checksum computed from the model types in its `models` array. If a schema's `models` array references the global `LocalScanRecord` (or any other global model) and that global model changes, the stored checksum no longer matches, and `NSStagedMigrationManager` throws a fatal exception at app launch.

The invariant that prevents this:
- **Retired schemas (V1 … V(N-1))**: `models` references frozen snapshot types nested inside `extension MerianSchemaV{K}` — immutable, stable checksums forever.
- **Current schema (V(N))**: `models` references global types — required so all app code (`@Query`, `context.insert`, etc.) operates on the same entities as the container.

The crash happens when you modify global models WITHOUT first freezing the outgoing schema. This runbook enforces the safe ordering.

### iOS 26 additional constraint: custom stages must have distinct model references

On iOS 26+, `NSCustomMigrationStage` validates at `ModelContainer` init time that `fromVersion` and `toVersion` produce **non-equal** `NSManagedObjectModelReference` values. If both versions resolve to the same underlying model (e.g., both reference the global V(N)-shaped `LocalScanRecord`), the app crashes at launch with:

```
'NSInvalidArgumentException', reason: 'The current model reference and the next model reference cannot be equal.'
```

This constraint applies to ALL custom stages in `MerianMigrationPlan.stages`, even stages that will never need to run (e.g., V15→V16 for a user already on V26). The fix is the same as the main invariant: use **fully-qualified** type names in every schema's `models` array so SwiftData resolves the frozen snapshot, not the global type.

**Special attention for schemas using the extension pattern** (e.g., V24, V25): when `@Model` classes are declared via `extension MerianSchemaV{K}` rather than directly inside the enum body, Swift's name lookup may silently resolve bare `LocalScanRecord.self` in the enum body to the global type instead of the extension-defined snapshot. Always use `MerianSchemaV{K}.LocalScanRecord.self` in those schemas' `models` arrays.

---

## Steps

### Step 1 — Freeze the outgoing schema V(N)

No schema-freezing automation script is currently checked into this repository.
Freeze the outgoing schema manually before touching any file in
`apps/ios/Merian/Models/ActiveSchema/`.

Manual freeze checklist inside `SchemaV{N}.swift` or `SchemaVersions.swift`:

1. **Declare the frozen `LocalScanRecord` inside the enum body (not an extension)**:
   - Extension-declared inner classes introduce a Swift name-resolution ambiguity: bare `LocalScanRecord.self` in the enum body's `models` computed property may silently resolve to the global `ActiveSchema` type instead of the frozen snapshot, causing the iOS 26 "cannot be equal" crash.
   - If an extension is unavoidable (e.g., the `@Relationship` macro reflection bug from V24/V25), **always use fully-qualified `MerianSchemaV{N}.LocalScanRecord.self` in the `models` array**.

2. **Typealiases for unchanged models — but never for ScanCollection**:
   - `OfflineQueuedScan` and `PendingCloudDeletionTask` are safe to typealias — they have no relationship to `LocalScanRecord`.
   - **`ScanCollection` must always be redeclared in the enum body** (not typealiased), even if structurally identical to the previous version. `ScanCollection` has `@Relationship(inverse: \LocalScanRecord.collections)` — this key path captures `LocalScanRecord` by **Swift type identity** at compile time. A typealias brings in the previous schema's `ScanCollection`, whose relationship still points to V(N-1).LocalScanRecord by type. On iOS 26, SwiftData resolves relationship destinations by type identity and may auto-include V(N-1).LocalScanRecord in V(N)'s schema, making V(N) and V(N-1) produce equal `NSManagedObjectModel` hashes → crash during custom stage validation.
   ```swift
   typealias OfflineQueuedScan        = MerianSchemaV{N-1}.OfflineQueuedScan
   typealias PendingCloudDeletionTask = MerianSchemaV{N-1}.PendingCloudDeletionTask
   // ScanCollection: always redeclare — see note above
   @Model
   final class ScanCollection {
       @Attribute(.unique) var id: String = UUID().uuidString
       var name: String
       var createdAt: Date = Date()
       var isDeleted: Bool = false
       @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
       init(...) { ... }
   }
   ```

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

After Step 1 compiles, it is safe to add, remove, or rename fields in
`apps/ios/Merian/Models/ActiveSchema/`:
- `LocalScanRecord.swift`
- `OfflineQueuedScan.swift`
- `ScanCollection.swift`
- `PendingCloudDeletionTask.swift`

Any model that changes here is the **only** model that needs a new snapshot in Step 1 of the next bump. Models that do not change can be typealiased.

---

### Step 3 — Create SchemaV{N+1}.swift

Create `apps/ios/Merian/Models/Schema/SchemaV{N+1}.swift`:

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

XcodeGen uses glob source discovery. If the glob pattern already covers `apps/ios/Merian/Models/Schema/`, no change is needed. Verify:

```bash
grep -A2 "Schema" project.yml | head -10
```

Run `xcodegen generate` if you added new directories.

---

### Step 7 — Build and test

```bash
xcodebuild build -scheme Merian \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0'

xcodebuild test -scheme Merian \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
    -only-testing:merianTests/MigrationPlanTests \
    -only-testing:merianTests/ScanRepositoryTests
```

`MigrationPlanTests` has two guards — both must pass on the iOS 26 simulator:
- `migrationPlanContainerInitializesWithoutCrash` — fresh store; catches init-time stage validation failures.
- `migrationFromV26ToV27DoesNotCrash` — creates a V26 disk store and migrates it; catches the migration-execution path where iOS 26 validates ALL custom stages (including ones not being applied).

Run both on iOS 26 on every schema bump:

```bash
xcodebuild test -scheme Merian \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
    -only-testing:merianTests/MigrationPlanTests
```

> **Note**: Update `migrationFromV26ToV27DoesNotCrash` to target the new version pair (e.g., V27→V28) when V28 is introduced.

All tests must pass before committing.

---

## Checklist

- [ ] Outgoing schema V(N) frozen manually BEFORE modifying any `ActiveSchema/` file
- [ ] V(N) frozen `LocalScanRecord` declared **inside the enum body** (not an extension)
- [ ] V(N) frozen `ScanCollection` redeclared **inside the enum body** (not a typealias) — relationship key path must point to V(N).LocalScanRecord
- [ ] V(N) `OfflineQueuedScan` and `PendingCloudDeletionTask` may use typealiases (no relationship to LocalScanRecord)
- [ ] V(N) `models` array uses fully-qualified `MerianSchemaV{N}.ModelName.self` references
- [ ] Any `.custom` migration's `willMigrate` uses `MerianSchemaV{N}.LocalScanRecord` (frozen), `didMigrate` uses `MerianSchemaV{N+1}.LocalScanRecord` or unqualified global type
- [ ] Global models in `ActiveSchema/` are modified AFTER the snapshot in step 1
- [ ] `SchemaV{N+1}.swift` created, referencing global types
- [ ] `Aliases.swift` updated: `typealias CurrentSchema = MerianSchemaV{N+1}`
- [ ] `SchemaVersions.swift` updated: both `schemas` and `stages` arrays extended
- [ ] Build succeeds
- [ ] `MigrationPlanTests` pass (iOS 18 + iOS 26 simulator if available)
- [ ] `ScanRepositoryTests` pass
- [ ] `docs/backend-and-data/04-database-schema.md` updated (current active schema version, new fields documented)
