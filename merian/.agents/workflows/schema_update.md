---
description: Updating the SwiftData Schema Version
---

# 🚀 SwiftData Schema Migration Runbook

This automated workflow correctly bumps the SwiftData schema version, snapshotting the active global models so the historical schema integrity remains intact.

## Step 1: Discover Current Schema State
Identify what the current schema is by inspecting the `CurrentSchema` alias in `Models/Aliases.swift`.
If the current schema is `V26`, we will be transitioning to `V27`. For the sake of these instructions, let's assume `V_CURRENT` is `26` and `V_NEXT` is `27`. 

## Step 2: Create the Next Schema File
1. Create a new file `merian/Models/Schema/SchemaV27.swift`.
2. Inside `SchemaV27.swift`, define the new version:

```swift
import Foundation
import SwiftData

enum MerianSchemaV27: VersionedSchema {
    static var versionIdentifier = Schema.Version(27, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
```

> [!IMPORTANT]
> Do **NOT** put `@Model class` declarations in this file. Active models live globally in `Models/ActiveSchema/`. This file purely maps the globally active models to `SchemaV27.models`.

## Step 3: Snapshot the Old Schema
Because the active models and their properties have likely changed in the global namespace (which is why you are bumping the schema), you **MUST** preserve the exact structure of what the models looked like under `V26`. 

1. Gather the codebase's Git history from *before* the model changes were made (or just look at the last committed state of the ActiveSchema models before you started modifying properties).
2. Take the struct/class text of the OLD `LocalScanRecord`, `ScanCollection`, `PendingCloudDeletionTask`, and `OfflineQueuedScan` and paste them directly **INSIDE** `extension MerianSchemaV26 { ... }`.
3. Inside `SchemaV26.swift`, ensure its `models` property refers to these namespaced snapshot models (e.g. `MerianSchemaV26.LocalScanRecord.self`). 

## Step 4: Advance the Schema Pointer
1. Update `merian/Models/Aliases.swift`:
```diff
- typealias CurrentSchema = MerianSchemaV26
+ typealias CurrentSchema = MerianSchemaV27
```

> [!TIP]
> `App/MerianApp.swift` automatically uses `CurrentSchema.self`, so it requires zero changes.

## Step 5: Update the Migration Plan
1. Open `merian/Models/SchemaVersions.swift`.
2. Append `MerianSchemaV27.self` to the end of the `schemas` array.
3. Define the specific `MigrationStage` step at the bottom of the file (e.g., lightweight or custom migration depending on the change).

```swift
static let migrateV26toV27 = MigrationStage.lightweight(
    fromVersion: MerianSchemaV26.self,
    toVersion: MerianSchemaV27.self
)
```
4. Finally, append `migrateV26toV27` to the end of the `stages` array block.

By adhering strictly to this runbook, the main models will *always* live freely in the global namespace under `Models/ActiveSchema/*`, giving `#Predicate` no trouble, while the historical versions remain safely archived inside their respective extensions.

---

## ⚠️ Critical: Checksums and Cast Errors

### How SwiftData computes schema checksums

SwiftData computes per-entity version hashes from **stored attribute names and types** (field content). Swift class identity and module qualification have **no effect** — a frozen inner class with the same fields as the global produces **identical** checksums. The only way to create unique checksums between two consecutive schema versions is either:

1. A **real field difference** in at least one existing model, OR
2. A **new model entity** that exists in V_NEXT but not in V_CURRENT.

### The "Failed to cast model" error

If two schema versions in the migration plan register **different Swift types** for the same entity (a frozen inner class in one version and the global in another), SwiftData's internal entity-class registry becomes inconsistent. Fetches and relationship traversals can fail with:

```
Fatal error: Failed to cast model Merian.LocalScanRecord
  for PersistentIdentifier(...) to LocalScanRecord.
```

This error occurs **post-migration** during normal fetch operations — not only during migration itself. Using a custom migration instead of lightweight does **not** avoid it.

### The golden rule: all global types, always

**Every entity must use the same global Swift class in every schema version of the migration plan.** Never use frozen inner classes or typealiased older frozen classes for any entity — they create irreversible registry conflicts.

Checksum uniqueness between V_CURRENT and V_NEXT must come from one of the two mechanisms above (field difference or new entity), achieved exclusively through adding/removing/renaming stored attributes on the global class or by adding a new global model exclusively to V_NEXT.

### Example — V33 → V34 (adds alternativeCommonNames + UserSpeciesPreference)

```swift
// SchemaV33.swift — all global types; no frozen inner classes
enum MerianSchemaV33: VersionedSchema {
    static var versionIdentifier = Schema.Version(33, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self]
    }
}

// SchemaV34.swift — adds UserSpeciesPreference; checksum differs from V33
// because V34 has one more entity in its model set.
enum MerianSchemaV34: VersionedSchema {
    static var versionIdentifier = Schema.Version(34, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}

// SchemaVersions.swift — lightweight: adds alternativeCommonNames column +
// UserSpeciesPreference table. No cast errors because all entities use the
// same global class in both V33 and V34.
static let migrateV33toV34 = MigrationStage.lightweight(
    fromVersion: MerianSchemaV33.self,
    toVersion: MerianSchemaV34.self
)
```

### What to do when adding a field to an existing model

1. Add the field to the global model class in `Models/ActiveSchema/`.
2. Create `SchemaVN+1` pointing to all global types.
3. If the field alone does not differentiate checksums (because V_CURRENT also points to the same global and the global now includes the new field), **add a new companion entity** to `SchemaVN+1` to anchor the checksum difference.
4. Register a lightweight migration from `SchemaVN` to `SchemaVN+1`.
