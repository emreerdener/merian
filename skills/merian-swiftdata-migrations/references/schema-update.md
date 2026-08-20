# SwiftData schema update workflow

Follow this order exactly. Changing an active model before freezing the outgoing
schema can alter historical checksums and crash installed stores at startup.

## Why the order is load-bearing

`MerianMigrationPlan.schemas` computes Core Data models from each
`VersionedSchema.models` array. A retired schema that still references a global
active type silently changes whenever that type changes. Historical schemas must
therefore reference immutable nested snapshots; the current schema must
reference global active types so application `@Query`, inserts, and fetches use
the container's current entities.

On iOS 26+, every `NSCustomMigrationStage` is validated at container startup.
Its `fromVersion` and `toVersion` must resolve to distinct model references even
when that stage will not run for the current user. Bare names in extension-based
schemas may resolve to the global type, so retired arrays always use fully
qualified names such as `MerianSchemaV42.LocalScanRecord.self`.

## 1. Inventory the current contract

Before editing:

1. Read the `CurrentSchema` alias, `MerianMigrationPlan.schemas`,
   `MerianMigrationPlan.stages`, recent startup recovery plans, and the affected
   files under `apps/ios/Merian/Models/ActiveSchema/`.
2. Identify the outgoing version `V(N)` and next version `V(N+1)` from source;
   never copy example version numbers.
3. Determine the exact outgoing stored shape, including defaults, optionality,
   attributes, uniqueness, relationships, inverse key paths, delete rules, and
   initializers. Use version history only to recover facts, not to edit history.
4. Decide whether the stage can be lightweight or needs a bounded custom
   transform. Record any temporary data needed between `willMigrate` and
   `didMigrate` and its cleanup behavior.

## 2. Freeze outgoing V(N) before active edits

In the outgoing schema, declare immutable nested snapshots for every changed
model. Prefer declarations inside the enum body. When the existing schema uses
extensions because of a macro limitation, keep that established structure but
fully qualify every entry in `models`.

Unchanged models without relationships to a changed model may alias a prior
frozen type. Do not alias a relationship-bearing type merely because its stored
properties look identical. `ScanCollection`, for example, carries an inverse key
path to `LocalScanRecord`; freeze/redeclare it so both ends use V(N) type
identity.

The outgoing array should make missing snapshots a compile error:

```swift
static var models: [any PersistentModel.Type] {
    [
        MerianSchemaV42.LocalScanRecord.self,
        MerianSchemaV42.OfflineQueuedScan.self,
        MerianSchemaV42.ScanCollection.self,
        MerianSchemaV42.PendingCloudDeletionTask.self,
    ]
}
```

For a custom stage, `willMigrate` fetches the fully qualified outgoing frozen
type. `didMigrate` fetches the new/current type. Compile this snapshot before
touching the active model. If it does not compile, do not continue.

## 3. Change the active model

Only after the frozen outgoing schema compiles:

- apply the intended field, attribute, relationship, or entity change under
  `Models/ActiveSchema/`;
- preserve initialization and decode compatibility where required;
- update repository/domain mappings and fixtures that own the new state; and
- avoid unrelated cleanup that makes the migration diff harder to audit.

## 4. Add current V(N+1)

Create the next schema file under `apps/ios/Merian/Models/Schema/`. The new
current schema intentionally references the global active types:

```swift
enum MerianSchemaV43: VersionedSchema {
    static var versionIdentifier = Schema.Version(43, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
```

Do not freeze V(N+1) yet. It remains active until the next schema bump. Update
the `CurrentSchema` alias and append V(N+1) to every applicable schema list.

## 5. Add exactly one ordered stage

Append a stage from V(N) to V(N+1) and add it to the stage list in the matching
position. Use a lightweight stage only for a change SwiftData can migrate
without custom data movement. For a custom stage:

- read old values through fully qualified V(N) snapshot types;
- write through V(N+1)/global types only after the model transition;
- bound temporary state, key it by stable identity, and clear it on success and
  failure paths;
- make transforms deterministic and safe to retry where the framework may
  recreate a container; and
- never reach a network or external service.

Do not edit an older stage to make the new version work. Add forward logic.

## 6. Preserve startup recovery semantics

Review `MerianApp.bootstrapModelContainer`, `ModelStoreRecoveryCoordinator`, and
the recent-version recovery plans whenever the new stage affects which stores
can open.

- Keep error classification explicit. A migration error is not automatically a
  corruption signature.
- Do not broaden quarantine or destructive rescue matching to hide a schema
  defect.
- Keep archived/quarantined artifacts recoverable and keep logs free of user
  data and raw store contents.
- Extend store-version selection and known-good recent plans when the new
  current schema requires it.

## 7. Verify real store paths

At minimum:

1. Run `make validate-ios-migration-guardrails`.
2. Run `make xcodegen` when a schema file was added and verify its target
   membership.
3. Build the `Merian` scheme.
4. Run all `MigrationPlanTests`, including fresh-container initialization and a
   disk-backed V(N) → V(N+1) fixture on iOS 26 or later.
5. Run focused repository/model tests for changed data semantics.
6. Run startup recovery tests that prove the new store version selects the
   intended plan and that non-eligible errors are not quarantined.
7. Update the current SwiftData schema and migration/recovery explanation in
   `docs/backend-and-data/04-database-schema.md`.

Do not delete or overwrite a failing fixture store as the migration strategy. If
a supported historical store cannot migrate, fix the forward plan and retain the
failing fixture as regression coverage.
