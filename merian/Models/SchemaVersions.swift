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
            MerianSchemaV17.self,
            MerianSchemaV18.self,
            MerianSchemaV19.self,
            MerianSchemaV20.self,
            MerianSchemaV21.self,
            MerianSchemaV22.self,
            MerianSchemaV23.self,
            MerianSchemaV24.self,
            MerianSchemaV25.self,
            MerianSchemaV26.self,
            MerianSchemaV27.self,
            MerianSchemaV28.self,
            MerianSchemaV29.self,
            MerianSchemaV30.self,
            MerianSchemaV31.self,
            MerianSchemaV32.self,
            MerianSchemaV33.self,
            MerianSchemaV34.self
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
            migrateV16toV17,
            migrateV17toV18,
            migrateV18toV19,
            migrateV19toV20,
            migrateV20toV21,
            migrateV21toV22,
            migrateV22toV23,
            migrateV23toV24,
            migrateV24toV25,
            migrateV25toV26,
            migrateV26toV27,
            migrateV27toV28,
            migrateV28toV29,
            migrateV29toV30,
            migrateV30toV31,
            migrateV31toV32,
            migrateV32toV33,
            migrateV33toV34
        ]
    }

    static let migrateV33toV34 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV33.self,
        toVersion: MerianSchemaV34.self
    )

    // Temporary backfill storage for V32→V33 migration.
    // Captures the old Bool state before the column is dropped, then writes scanStateRaw in didMigrate.
    nonisolated(unsafe) static var _scanStateBackfill: [String: Int] = [:]

    static let migrateV32toV33 = MigrationStage.custom(
        fromVersion: MerianSchemaV32.self,
        toVersion: MerianSchemaV33.self,
        willMigrate: { context in
            let scans = try context.fetch(FetchDescriptor<MerianSchemaV32.OfflineQueuedScan>())
            _scanStateBackfill = Dictionary(uniqueKeysWithValues: scans.map { scan in
                let state: Int
                if scan.isDeleted {
                    state = ScanQueueState.failed.rawValue
                } else if scan.isUploaded {
                    state = ScanQueueState.staged.rawValue
                } else {
                    state = ScanQueueState.pending.rawValue
                }
                return (scan.id, state)
            })
        },
        didMigrate: { context in
            let scans = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
            for scan in scans {
                if let state = _scanStateBackfill[scan.id] {
                    scan.scanStateRaw = state
                }
            }
            try context.save()
            _scanStateBackfill = [:]
        }
    )

    static let migrateV31toV32 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV31.self,
        toVersion: MerianSchemaV32.self
    )

    static let migrateV30toV31 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV30.self,
        toVersion: MerianSchemaV31.self
    )

    static let migrateV29toV30 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV29.self,
        toVersion: MerianSchemaV30.self
    )

    static let migrateV28toV29 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV28.self,
        toVersion: MerianSchemaV29.self
    )

    static let migrateV27toV28 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV27.self,
        toVersion: MerianSchemaV28.self
    )

    static let migrateV26toV27 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV26.self,
        toVersion: MerianSchemaV27.self
    )

    static let migrateV19toV20 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV19.self,
        toVersion: MerianSchemaV20.self
    )

    static let migrateV20toV21 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV20.self,
        toVersion: MerianSchemaV21.self
    )

    static let migrateV21toV22 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV21.self,
        toVersion: MerianSchemaV22.self
    )

    static let migrateV22toV23 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV22.self,
        toVersion: MerianSchemaV23.self
    )

    static let migrateV23toV24 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV23.self,
        toVersion: MerianSchemaV24.self
    )

    static let migrateV24toV25 = MigrationStage.custom(
        fromVersion: MerianSchemaV24.self,
        toVersion: MerianSchemaV25.self,
        willMigrate: { context in
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV24.LocalScanRecord>())
            _diagnosticLookalikesBackfill = Dictionary(
                uniqueKeysWithValues: allRecords
                    .compactMap { record in
                        guard let string = record.diagnosticLookalikeName, !string.isEmpty else { return nil }
                        let array = string.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        return (record.id, array)
                    }
            )
        },
        didMigrate: { context in
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV25.LocalScanRecord>())
            for record in allRecords {
                if let array = _diagnosticLookalikesBackfill[record.id] {
                    record.diagnosticLookalikes = array
                }
            }
            try context.save()
            _diagnosticLookalikesBackfill = [:]
        }
    )

    // Temporary storage for preserving the lookalikes array when discarding diagnostic string columns for V26.
    nonisolated(unsafe) static var _similarSpeciesBackfill: [String: [String]] = [:]

    static let migrateV25toV26 = MigrationStage.custom(
        fromVersion: MerianSchemaV25.self,
        toVersion: MerianSchemaV26.self,
        willMigrate: { context in
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV25.LocalScanRecord>())
            _similarSpeciesBackfill = Dictionary(
                uniqueKeysWithValues: allRecords
                    .compactMap { record in
                        guard let lookalikes = record.diagnosticLookalikes, !lookalikes.isEmpty else { return nil }
                        return (record.id, lookalikes)
                    }
            )
        },
        didMigrate: { context in
            let allRecords = try context.fetch(FetchDescriptor<MerianSchemaV26.LocalScanRecord>())
            for record in allRecords {
                if let array = _similarSpeciesBackfill[record.id] {
                    record.similarSpecies = array
                }
            }
            try context.save()
            _similarSpeciesBackfill = [:]
        }
    )

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

    // Temporary storage for migrating diagnosticLookalikeName (comma-separated string) to diagnosticLookalikes (array) for pre-V25 records.
    nonisolated(unsafe) static var _diagnosticLookalikesBackfill: [String: [String]] = [:]

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

    static let migrateV17toV18 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV17.self,
        toVersion: MerianSchemaV18.self
    )

    static let migrateV18toV19 = MigrationStage.lightweight(
        fromVersion: MerianSchemaV18.self,
        toVersion: MerianSchemaV19.self
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
