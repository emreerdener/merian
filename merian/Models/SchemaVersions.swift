import SwiftData

// MARK: - Migration Plan
enum MerianMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MerianSchemaV1.self,
            MerianSchemaV2.self,
            MerianSchemaV3.self,
            MerianSchemaV4.self,
            MerianSchemaV5.self,
            MerianSchemaV6.self,
            MerianSchemaV7.self,
            MerianSchemaV8.self,
            MerianSchemaV9.self,
            MerianSchemaV10.self,
            MerianSchemaV11.self,
            MerianSchemaV12.self,
            MerianSchemaV13.self,
            MerianSchemaV14.self,
            MerianSchemaV15.self,
            MerianSchemaV16.self,
            MerianSchemaV17.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2,
            migrateV2toV3,
            migrateV3toV4,
            migrateV4toV5,
            migrateV5toV6,
            migrateV6toV7,
            migrateV7toV8,
            migrateV8toV9,
            migrateV9toV10,
            migrateV10toV11,
            migrateV11toV12,
            migrateV12toV13,
            migrateV13toV14,
            migrateV14toV15,
            migrateV15toV16,
            migrateV16toV17
        ]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV1.self,
        toVersion: MerianSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV2.self,
        toVersion: MerianSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV3.self,
        toVersion: MerianSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV4.self,
        toVersion: MerianSchemaV5.self
    )

    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV5.self,
        toVersion: MerianSchemaV6.self
    )

    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV6.self,
        toVersion: MerianSchemaV7.self
    )

    static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV7.self,
        toVersion: MerianSchemaV8.self
    )

    static let migrateV8toV9 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV8.self,
        toVersion: MerianSchemaV9.self
    )

    static let migrateV9toV10 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV9.self,
        toVersion: MerianSchemaV10.self
    )

    static let migrateV10toV11 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV10.self,
        toVersion: MerianSchemaV11.self
    )

    static let migrateV11toV12 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV11.self,
        toVersion: MerianSchemaV12.self
    )

    static let migrateV12toV13 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV12.self,
        toVersion: MerianSchemaV13.self
    )

    static let migrateV13toV14 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV13.self,
        toVersion: MerianSchemaV14.self
    )

    static let migrateV14toV15 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV14.self,
        toVersion: MerianSchemaV15.self
    )

    // Temporary storage for passing poisonous IDs from willMigrate (V15 context) to didMigrate (V16 context).
    nonisolated(unsafe) static var _poisonousIds: Set<String> = []

    // Temporary storage for backfilling aiReasoning from insightDescription for pre-V16 records.
    nonisolated(unsafe) static var _insightDescriptionBackfill: [String: String] = [:]

    static let migrateV15toV16 = MigrationStage.custom(
        fromVersion: MerianSchemaV15.self,
        toVersion: MerianSchemaV16.self,
        willMigrate: { context in
            // Read all records that were marked isPoisonous = true in V15.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV15.LocalScanRecord>())
            _poisonousIds = Set(allRecords.filter { $0.isPoisonous }.map { $0.id })
        },
        didMigrate: { context in
            // Set hazardType = "poisonous" for the records that had isPoisonous = true.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV16.LocalScanRecord>())
            for record in allRecords where _poisonousIds.contains(record.id) {
                record.hazardType = "poisonous"
            }
            try context.save()
            _poisonousIds = []
        }
    )

    static let migrateV16toV17 = MigrationStage.custom(
        fromVersion: MerianSchemaV16.self,
        toVersion: MerianSchemaV17.self,
        willMigrate: { context in
            // Preserve insight descriptions for records that never had aiReasoning set.
            // insightDescription is removed in V17; copy its value into aiReasoning for continuity.
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV16.LocalScanRecord>())
            _insightDescriptionBackfill = Dictionary(
                uniqueKeysWithValues: allRecords
                    .filter { $0.aiReasoning == nil && !$0.insightDescription.isEmpty }
                    .map { ($0.id, $0.insightDescription) }
            )
        },
        didMigrate: { context in
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV17.LocalScanRecord>())
            for record in allRecords {
                if let description = _insightDescriptionBackfill[record.id] {
                    record.aiReasoning = description
                }
            }
            try context.save()
            _insightDescriptionBackfill = [:]
        }
    )
}
