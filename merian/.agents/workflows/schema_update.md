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
