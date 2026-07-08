import Foundation
@testable import Merian
import SwiftData
import Testing

/// Validates the SwiftData migration plan structurally — ensures no two consecutive custom migration
/// stages produce the same NSManagedObjectModel, which causes a fatal crash on iOS 26+.
///
/// Two test categories:
///  1. In-memory init — covers the case where the app has no existing store (fresh install).
///  2. Disk migration — covers the case where a user upgrades from a prior schema version.
///     On iOS 26+, `NSCustomMigrationStage` validates all custom stages at migration time,
///     not just the one being applied. Any stage with equal from/to models crashes at that point.
@Suite(.serialized)
@MainActor
struct MigrationPlanTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func schemaVersionsSource() throws -> String {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Merian")
            .appendingPathComponent("Models")
            .appendingPathComponent("SchemaVersions.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func migrationPlanSource() throws -> String {
        let source = try schemaVersionsSource()
        guard let migrationStart = source.range(of: "enum MerianMigrationPlan")?.lowerBound else {
            Issue.record("SchemaVersions.swift must declare MerianMigrationPlan")
            return ""
        }
        let remainder = source[migrationStart...]
        if let alternateStart = remainder.range(of: "\nenum MerianRecentV44MigrationPlan")?.lowerBound {
            return String(remainder[..<alternateStart])
        }
        return String(remainder)
    }

    private func migrationPlanSchemasListSource() throws -> String {
        let source = try migrationPlanSource()
        guard let schemasStart = source.range(of: "static var schemas")?.lowerBound else {
            Issue.record("MerianMigrationPlan must declare schemas")
            return ""
        }
        let remainder = source[schemasStart...]
        guard let stagesStart = remainder.range(of: "\n    static var stages")?.lowerBound else {
            Issue.record("MerianMigrationPlan schemas must precede stages")
            return String(remainder)
        }
        return String(remainder[..<stagesStart])
    }

    private func migrationPlanStagesListSource() throws -> String {
        let source = try migrationPlanSource()
        guard let stagesStart = source.range(of: "static var stages")?.lowerBound else {
            Issue.record("MerianMigrationPlan must declare stages")
            return ""
        }
        let remainder = source[stagesStart...]
        let firstStageStart = remainder.range(
            of: "\n    private static func initializeV48OfflineQueueRecords"
        )?.lowerBound ?? remainder.range(of: "\n    static let migrateV47toV48")?.lowerBound
        guard let firstStageStart else {
            Issue.record("MerianMigrationPlan stages must precede stage declarations")
            return String(remainder)
        }
        return String(remainder[..<firstStageStart])
    }

    private func recentV44MigrationPlanSource() throws -> String {
        let source = try schemaVersionsSource()
        guard let migrationStart = source.range(of: "enum MerianRecentV44MigrationPlan")?.lowerBound else {
            Issue.record("SchemaVersions.swift must declare MerianRecentV44MigrationPlan")
            return ""
        }
        let remainder = source[migrationStart...]
        if let nextStart = remainder.range(of: "\nenum MerianRecentV45MigrationPlan")?.lowerBound {
            return String(remainder[..<nextStart])
        }
        return String(remainder)
    }

    private func recentV45MigrationPlanSource() throws -> String {
        let source = try schemaVersionsSource()
        guard let migrationStart = source.range(of: "enum MerianRecentV45MigrationPlan")?.lowerBound else {
            Issue.record("SchemaVersions.swift must declare MerianRecentV45MigrationPlan")
            return ""
        }
        let remainder = source[migrationStart...]
        if let nextStart = remainder.range(of: "\nenum MerianRecentV46MigrationPlan")?.lowerBound {
            return String(remainder[..<nextStart])
        }
        return String(remainder)
    }

    private func recentV46MigrationPlanSource() throws -> String {
        let source = try schemaVersionsSource()
        guard let migrationStart = source.range(of: "enum MerianRecentV46MigrationPlan")?.lowerBound else {
            Issue.record("SchemaVersions.swift must declare MerianRecentV46MigrationPlan")
            return ""
        }
        let remainder = source[migrationStart...]
        if let nextStart = remainder.range(of: "\nenum MerianRecentV47MigrationPlan")?.lowerBound {
            return String(remainder[..<nextStart])
        }
        return String(remainder)
    }

    private func recentV47MigrationPlanSource() throws -> String {
        let source = try schemaVersionsSource()
        guard let migrationStart = source.range(of: "enum MerianRecentV47MigrationPlan")?.lowerBound else {
            Issue.record("SchemaVersions.swift must declare MerianRecentV47MigrationPlan")
            return ""
        }
        return String(source[migrationStart...])
    }

    private func sourceLineViolations(
        in source: String,
        where isViolation: (String) -> Bool
    ) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                let lineString = String(line)
                return isViolation(lineString)
                    ? "SchemaVersions.swift:\(index + 1): \(lineString.trimmingCharacters(in: .whitespaces))"
                    : nil
            }
    }

    private func keepSQLiteStoreForProcessLifetime(at url: URL) {
        // SwiftData/Core Data can keep SQLite and WAL descriptors alive after the
        // last visible ModelContainer falls out of scope. Unlinking these files
        // during the same test process causes sqlite "vnode unlinked while in use"
        // traps on CI, so migration fixtures use unique temp URLs and let the
        // simulator/temp-directory cleanup remove them after the process exits.
        _ = url
    }

    private struct CurrentMigrationStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private struct QueuedMediaMigrationFixture {
        let id: String
        let items: [SerializedMediaItem]
        let cover: String?
        let inferencePaths: [String]?
        let visualJSON: String?
    }

    private func migrationStoreURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_\(name).sqlite")
    }

    private func makeModelContainer(
        for schema: Schema,
        configurations: [ModelConfiguration]
    ) throws -> ModelContainer {
        try MerianApp.makeContainerCatchingObjectiveCExceptions {
            try ModelContainer(for: schema, configurations: configurations)
        }
    }

    private func makeModelContainer<MigrationPlan: SchemaMigrationPlan>(
        for schema: Schema,
        migrationPlan: MigrationPlan.Type,
        configurations: [ModelConfiguration]
    ) throws -> ModelContainer {
        try MerianApp.makeContainerCatchingObjectiveCExceptions {
            try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: configurations
            )
        }
    }

    private func openCurrentMigrationStore(at url: URL) throws -> CurrentMigrationStore {
        let currentSchema = Schema(versionedSchema: CurrentSchema.self)
        let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
        let currentContainer = try makeModelContainer(
            for: currentSchema,
            migrationPlan: MerianRecentV47MigrationPlan.self,
            configurations: [currentConfig]
        )
        return CurrentMigrationStore(
            container: currentContainer,
            context: ModelContext(currentContainer)
        )
    }

    private func encodedMediaJSON(_ items: [SerializedMediaItem]) throws -> String {
        try #require(String(data: JSONEncoder().encode(items), encoding: .utf8))
    }

    private func fetchCurrentQueuedScan(id: String, context: ModelContext) throws -> OfflineQueuedScan {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try #require(context.fetch(descriptor).first)
    }

    private func assertCurrentScanIngestionJob(
        scanId: String,
        context: ModelContext
    ) throws {
        let jobId = "scan-ingestion:\(scanId)"
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let migratedJob = try #require(context.fetch(jobDescriptor).first)
        #expect(migratedJob.kind == .scanIngestion)
        #expect(migratedJob.subjectId == scanId)
        #expect(migratedJob.status == .pending)
        #expect(migratedJob.attemptCount == 0)
    }

    private func assertCurrentQueuedScanHasFreshRetryState(_ scan: OfflineQueuedScan) {
        #expect(scan.queueAttemptCount == 0)
        #expect(scan.queueLastAttemptAt == nil)
        #expect(scan.queueNextRetryAt == nil)
        #expect(scan.queueLastErrorCode == nil)
        #expect(scan.queueLastHTTPStatus == nil)
        #expect(scan.queueLastServerStatus == nil)
        #expect(scan.queueLastServerStage == nil)
        #expect(scan.queueLastServerRetryAfter == nil)
        #expect((scan.queueUpdatedAt?.timeIntervalSinceReferenceDate ?? 0) > 0)
        #expect(scan.queueNeedsAttention == false)
    }

    @Test func migrationPlanCustomStagesDoNotUseSilentSaves() throws {
        let source = try migrationPlanSource()
        let violations = sourceLineViolations(in: source) { line in
            let condensed = line
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\t", with: "")
            return condensed.contains("try?context.save()")
                || condensed.contains("try?modelContext.save()")
        }

        #expect(
            violations.isEmpty,
            "Custom migrations must use saveMigrationContext so save failures rollback and abort migration:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test func migrationPlanCustomStagesDoNotFetchActiveModels() throws {
        let source = try migrationPlanSource()
        let activeFetchTokens = [
            "FetchDescriptor<LocalScanRecord>",
            "FetchDescriptor<OfflineQueuedScan>",
            "FetchDescriptor<ScanCollection>",
            "FetchDescriptor<CapturedMediaEntry>",
            "FetchDescriptor<PendingCloudDeletionTask>",
            "FetchDescriptor<UserSpeciesPreference>",
            "FetchDescriptor<CurrentSchema"
        ]
        let violations = sourceLineViolations(in: source) { line in
            activeFetchTokens.contains { line.contains($0) }
        }

        #expect(
            violations.isEmpty,
            "Custom migrations must fetch concrete MerianSchemaV{N} model snapshots, never active/global models:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test func migrationPlanCustomStagesDoNotCallActiveModelConvenienceHelpers() throws {
        let source = try migrationPlanSource()
        let activeHelperTokens = [
            ".replaceCapturedMedia(",
            " replaceCapturedMedia("
        ]
        let violations = sourceLineViolations(in: source) { line in
            activeHelperTokens.contains { line.contains($0) }
        }

        #expect(
            violations.isEmpty,
            "Custom migrations must use schema-scoped helpers instead of active model convenience methods:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test func capturedMediaRelationshipBackfillInsertsRowsThroughMigrationContext() throws {
        let source = try migrationPlanSource()
        let requiredSnippets = [
            "replaceMigratedCapturedMedia(on: scan, with: items, context: context)",
            "let entries = MerianSchemaV41.CapturedMediaEntry.makeEntries(from: items)",
            "entries.forEach { context.insert($0) }",
            "scan.capturedMediaEntries = entries"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "V40->V41 must insert migrated CapturedMediaEntry rows into the migration ModelContext before assigning the relationship:\n\(missing.joined(separator: "\n"))"
        )
    }

    @Test func retiredSchemasDoNotReferenceActiveCapturedMediaEntryRelationships() throws {
        let source = try schemaVersionsSource()
        let retiredSchemaSource = source
            .components(separatedBy: "enum MerianSchemaV42")
            .first ?? source
        let violations = sourceLineViolations(in: retiredSchemaSource) { line in
            if line.contains("CapturedMediaEntry.self"),
               !line.contains("MerianSchemaV") {
                return true
            }
            return line.contains("[CapturedMediaEntry]")
                || line.contains("[CapturedMediaEntry]?")
        }

        #expect(
            violations.isEmpty,
            "Retired schemas must freeze CapturedMediaEntry relationship targets in the schema namespace:\n\(violations.joined(separator: "\n"))"
        )
    }

    /// Mirrors MerianApp.init() exactly, using in-memory storage to keep the test fast.
    ///
    /// On iOS 26+, `NSCustomMigrationStage` validates at `ModelContainer` init time that
    /// `fromVersion` and `toVersion` resolve to non-equal `NSManagedObjectModelReference` values.
    /// If any custom stage has equal references (both schemas pointing to the same global model type),
    /// this throws at app launch:
    ///   'The current model reference and the next model reference cannot be equal.'
    ///
    /// Regression coverage: V24/V25/V26 extension-pattern name resolution ambiguity (2026-03).
    @Test func migrationPlanContainerInitializesWithoutCrash() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        _ = try makeModelContainer(
            for: schema,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config]
        )
    }

    @Test func currentSchemaColdStartPersistsCapturedMediaEntriesAcrossReload() throws {
        let url = migrationStoreURL(named: "v41coldstart_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let localId = "cold_start_local"
        let offlineId = "cold_start_offline"
        let localItems: [SerializedMediaItem] = [
            .audio(.documents("cold_start_audio.wav")),
            .description(ObservationContext(freeText: "Cold-start local description")),
            .image(.documents("cold_start_local.webp"))
        ]
        let offlineItems: [SerializedMediaItem] = [
            .description(ObservationContext(freeText: "Cold-start queued description")),
            .image(.documents("cold_start_offline.webp"))
        ]

        do {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try makeModelContainer(
                for: schema,
                migrationPlan: MerianMigrationPlan.self,
                configurations: [config]
            )
            let context = ModelContext(container)

            let localRecord = LocalScanRecord(
                id: localId,
                speciesId: "cold_start_species",
                scientificName: "Persistus media",
                commonName: "Persistent Media",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild"
            )
            localRecord.replaceCapturedMedia(with: localItems)

            let offlineRecord = OfflineQueuedScan(
                id: offlineId,
                coverImagePath: nil
            )
            offlineRecord.replaceCapturedMedia(with: offlineItems)

            context.insert(localRecord)
            context.insert(offlineRecord)
            try context.save()
        }

        do {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try makeModelContainer(
                for: schema,
                migrationPlan: MerianMigrationPlan.self,
                configurations: [config]
            )
            let context = ModelContext(container)

            var localDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == localId }
            )
            localDescriptor.fetchLimit = 1
            let localRecord = try #require(context.fetch(localDescriptor).first)
            #expect(localRecord.capturedMediaEntries?.count == localItems.count)
            #expect(localRecord.serializedCapturedMediaItems == localItems)
            #expect(localRecord.capturedMediaSnapshot.items == localItems)
            #expect(localRecord.coverImagePath == "cold_start_local.webp")

            var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == offlineId }
            )
            offlineDescriptor.fetchLimit = 1
            let offlineRecord = try #require(context.fetch(offlineDescriptor).first)
            #expect(offlineRecord.capturedMediaEntries?.count == offlineItems.count)
            #expect(offlineRecord.serializedCapturedMediaItems == offlineItems)
            #expect(offlineRecord.capturedMediaSnapshot.items == offlineItems)
            #expect(offlineRecord.coverImagePath == "cold_start_offline.webp")
        }
    }

    /// Simulates upgrading from V26 to V27 on-disk — the scenario that triggers iOS 26's
    /// eager custom-stage validation during `migrateStoreWithContext:error:`.
    ///
    /// On iOS 26, when any migration runs (even lightweight V26→V27), SwiftData iterates ALL
    /// custom stages in MerianMigrationPlan.stages and calls NSCustomMigrationStage.init for each.
    /// If any pair produces equal NSManagedObjectModelReferences, the app crashes before migration
    /// even begins. The in-memory test above does NOT cover this path because no migration runs.
    ///
    /// This test:
    ///  1. Creates a disk-based V26 store (no migration plan — just the V26 schema).
    ///  2. Reopens the same store with the full migration plan targeting V27.
    ///  3. Verifies no crash occurs during stage validation and store loading.
    @Test func migrationFromV26ToV27DoesNotCrash() throws {
        let url = migrationStoreURL(named: "v26migration_test")

        // Step 1 — create a V26 store with no migration plan.
        let schema26 = Schema(versionedSchema: MerianSchemaV26.self)
        let config26 = ModelConfiguration(schema: schema26, url: url)
        let container26 = try makeModelContainer(for: schema26, configurations: [config26])

        // Insert a minimal V26 record so the store actually has data and is not empty.
        let context26 = ModelContext(container26)
        let record = MerianSchemaV26.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context26.insert(record)
        try context26.save()

        // Close V26 container before reopening with migration plan.
        _ = container26

        // Step 2 — reopen with the full migration plan targeting V27.
        // On iOS 26, this triggers NSCustomMigrationStage construction for ALL custom stages.
        let schema27 = Schema(versionedSchema: CurrentSchema.self)
        let config27 = ModelConfiguration(schema: schema27, url: url)
        _ = try makeModelContainer(
            for: schema27,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config27]
        )

        // Keep the temp store alive for the test process; see keepSQLiteStoreForProcessLifetime.
        keepSQLiteStoreForProcessLifetime(at: url)
    }

    /// Simulates upgrading from V28 to V29 on-disk — verifies that adding
    /// `userIdentificationOverride` and `userConfirmedIdentification` (lightweight migration,
    /// no custom stage) does not crash during iOS 26 migration plan validation.
    @Test func migrationFromV28ToV29DoesNotCrash() throws {
        let url = migrationStoreURL(named: "v28migration_test")

        // Step 1 — create a V28 store with no migration plan.
        let schema28 = Schema(versionedSchema: MerianSchemaV28.self)
        let config28 = ModelConfiguration(schema: schema28, url: url)
        let container28 = try makeModelContainer(for: schema28, configurations: [config28])

        // Insert a minimal V28 record so the store has data and is not empty.
        let context28 = ModelContext(container28)
        let record = MerianSchemaV28.LocalScanRecord(
            speciesId: "test-v28-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context28.insert(record)
        try context28.save()

        // Close V28 container before reopening with migration plan.
        _ = container28

        // Step 2 — reopen with the full migration plan targeting the current schema (V29).
        let schema29 = Schema(versionedSchema: CurrentSchema.self)
        let config29 = ModelConfiguration(schema: schema29, url: url)
        _ = try makeModelContainer(
            for: schema29,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config29]
        )

        // Keep the temp store alive for the test process; see keepSQLiteStoreForProcessLifetime.
        keepSQLiteStoreForProcessLifetime(at: url)
    }

    /// Simulates upgrading from V30 to V33 on-disk — verifies that adding
    /// `isFlagged` (V31), `isUploaded` (V32), and migrating to `scanStateRaw` (V33)
    /// does not crash during iOS 26 migration plan validation.
    @Test func migrationFromV30ToV33DoesNotCrash() throws {
        let url = migrationStoreURL(named: "v30migration_test")

        // Step 1 — create a V30 store with no migration plan.
        let schema30 = Schema(versionedSchema: MerianSchemaV30.self)
        let config30 = ModelConfiguration(schema: schema30, url: url)
        let container30 = try makeModelContainer(for: schema30, configurations: [config30])

        // Insert a minimal V30 record so the store has data and is not empty.
        let context30 = ModelContext(container30)
        let record = MerianSchemaV30.LocalScanRecord(
            speciesId: "test-v30-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        context30.insert(record)
        try context30.save()

        // Close V30 container before reopening with migration plan.
        _ = container30

        // Step 2 — reopen with the full migration plan targeting the current schema (V33).
        let schema33 = Schema(versionedSchema: CurrentSchema.self)
        let config33 = ModelConfiguration(schema: schema33, url: url)
        _ = try makeModelContainer(
            for: schema33,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config33]
        )

        // Keep the temp store alive for the test process; see keepSQLiteStoreForProcessLifetime.
        keepSQLiteStoreForProcessLifetime(at: url)
    }

    /// Simulates the last stable pre-cluster source path.
    /// V44/V45/V46 are recent duplicate-prone representatives, so the full
    /// historical plan jumps V43 directly to V48 and leaves V44/V45/V46 to
    /// source-isolated recent plans.
    @Test func migrationFromV43ToCurrentSchemaDoesNotSafeMode() throws {
        let url = migrationStoreURL(named: "v43migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let scanId = "v43-pet-migration-scan"

        do {
            let schema43 = Schema(versionedSchema: MerianSchemaV43.self)
            let config43 = ModelConfiguration(schema: schema43, url: url)
            let container43 = try makeModelContainer(for: schema43, configurations: [config43])
            let context43 = ModelContext(container43)
            let record = MerianSchemaV43.LocalScanRecord(
                id: scanId,
                speciesId: "v43-species",
                scientificName: "Canis lupus familiaris",
                commonName: "Domestic Dog",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "domesticated",
                sex: "cannot_determine",
                sexConfidence: 0.0,
                sexEvidence: "no direct sex evidence"
            )
            context43.insert(record)
            try context43.save()
        }

        do {
            let schema44 = Schema(versionedSchema: CurrentSchema.self)
            let config44 = ModelConfiguration(schema: schema44, url: url)
            let container44 = try makeModelContainer(
                for: schema44,
                migrationPlan: MerianMigrationPlan.self,
                configurations: [config44]
            )
            let context44 = ModelContext(container44)
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            let migratedRecord = try #require(context44.fetch(descriptor).first)
            #expect(migratedRecord.scientificName == "Canis lupus familiaris")
            #expect(migratedRecord.sex == "cannot_determine")
            #expect(migratedRecord.petIdentificationData == nil)
        }
    }

    @Test func recentRetiredSchemasUseFrozenModelReferences() throws {
        let source = try schemaVersionsSource()
        let retiredSchemaNames = ["MerianSchemaV44", "MerianSchemaV45", "MerianSchemaV46"]
        let forbiddenModelReferences = [
            "LocalScanRecord.self",
            "OfflineQueuedScan.self",
            "CapturedMediaEntry.self",
            "ScanCollection.self"
        ]
        var currentSchemaName: String?
        var violations: [String] = []

        for (index, sourceLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(sourceLine)
            if let schemaName = retiredSchemaNames.first(where: { line.contains("enum \($0): VersionedSchema") }) {
                currentSchemaName = schemaName
            } else if line.contains("enum MerianSchemaV") {
                currentSchemaName = nil
            }

            guard let currentSchemaName else { continue }
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            for forbiddenReference in forbiddenModelReferences where trimmedLine.contains(forbiddenReference) {
                let qualifiedReference = "\(currentSchemaName).\(forbiddenReference)"
                if !trimmedLine.contains(qualifiedReference) {
                    violations.append("SchemaVersions.swift:\(index + 1): \(trimmedLine)")
                }
            }
        }

        #expect(
            violations.isEmpty,
            "Recent retired schemas must reference schema-scoped frozen models, not active globals:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test func latestQueueMetadataMigrationStaysDurable() throws {
        let source = try migrationPlanSource()
        let v47StageSource: String
        if let stageStart = source.range(of: "static let migrateV47toV48")?.lowerBound {
            let stageRemainder = source[stageStart...]
            let stageEnd = stageRemainder.range(of: "\n    // V45/V46")?.lowerBound ?? stageRemainder.endIndex
            v47StageSource = String(stageRemainder[..<stageEnd])
        } else {
            v47StageSource = source
        }
        let requiredSnippets = [
            "private static func initializeV48OfflineQueueRecords",
            "private struct V47QueuedScanMigrationSnapshot",
            "_v47QueuedScanBackfill",
            "static let migrateV47toV48 = MigrationStage.custom",
            "static let migrateV45toV48 = MigrationStage.custom",
            "static let migrateV46toV48 = MigrationStage.custom",
            "FetchDescriptor<MerianSchemaV47.OfflineQueuedScan>",
            "FetchDescriptor<MerianSchemaV48.OfflineQueuedScan>",
            "let snapshotIds = Set(snapshots.map(\\.id))",
            "var existingScansById = Dictionary(uniqueKeysWithValues: queuedScans.map { ($0.id, $0) })",
            "let capturedMediaJSON: String?",
            "let stagedR2Keys: [String]?",
            "let inferenceImagePaths: [String]?",
            "let visualMediaItemsJSON: String?",
            "let fieldNotes: String?",
            "func initializeQueueMetadata(on scan: MerianSchemaV48.OfflineQueuedScan)",
            "func upsertQueuedScan(from snapshot: V47QueuedScanMigrationSnapshot)",
            "if let existingScan = existingScansById[snapshot.id]",
            "apply(snapshot: snapshot, to: scan)",
            "upsertQueuedScan(from: snapshot)",
            "let entries = CapturedMediaEntry.makeEntries(from: items)",
            "scan.capturedMediaEntries = entries",
            "context.insert(scan)",
            "context.delete(scan)",
            "insertSchedulerRows(scanId: snapshot.id, createdAt: snapshot.timestamp)",
            "scan.queueAttemptCount = 0",
            "scan.queueLastAttemptAt = nil",
            "scan.queueNextRetryAt = nil",
            "scan.queueLastErrorCode = nil",
            "scan.queueLastErrorMessage = nil",
            "scan.queueLastHTTPStatus = nil",
            "scan.queueLastServerStatus = nil",
            "scan.queueLastServerStage = nil",
            "scan.queueLastServerRetryAfter = nil",
            "scan.queueUpdatedAt = now",
            "scan.queueNeedsAttention = false",
            #"let jobId = "scan-ingestion:\(scanId)""#,
            "MerianSchemaV48.OfflineJobRecord",
            "MerianSchemaV48.OfflineQueueEvent",
            #"try initializeV48OfflineQueueRecords(in: context, stage: "V47->V48 didMigrate")"#,
            #"try initializeV48OfflineQueueRecords(in: context, stage: "V45->V48 didMigrate")"#,
            #"try initializeV48OfflineQueueRecords(in: context, stage: "V46->V48 didMigrate")"#,
            "_v47QueuedScanBackfill.removeAll(namespace: namespace)",
            #"try saveMigrationContext(context, stage: stage)"#
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "V45/V46/V47->V48 must remain custom durable queue migrations. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !source.contains("static let migrateV47toV48 = MigrationStage.lightweight"),
            "V47->V48 cannot be lightweight because existing queued scans need retry metadata and scheduler rows."
        )
        #expect(
            source.contains("apply(snapshot: snapshot, to: scan)"),
            "V47 snapshots must repair just-migrated V48 rows before save so required queue metadata cannot remain nil."
        )
        #expect(
            v47StageSource.contains("context.delete(scan)"),
            "V47 queued scans must be deleted after snapshotting so SwiftData cannot reopen them as stale V47-backed current models."
        )
    }

    @Test func duplicateRecentSchemasAreCollapsedOutOfFullRuntimeMigrationPath() throws {
        let source = try migrationPlanSource()
        let schemasSource = try migrationPlanSchemasListSource()
        let stagesSource = try migrationPlanStagesListSource()
        let requiredSnippets = [
            "static let migrateV43toV48 = MigrationStage.custom",
            "fromVersion: MerianSchemaV43.self",
            "toVersion: MerianSchemaV48.self",
            #"try initializeV48OfflineQueueRecords(in: context, stage: "V43->V48 didMigrate")"#,
            "static let migrateV44toV48 = MigrationStage.custom",
            "fromVersion: MerianSchemaV44.self",
            #"try initializeV48OfflineQueueRecords(in: context, stage: "V44->V48 didMigrate")"#,
            "static let migrateV45toV48 = MigrationStage.custom",
            "fromVersion: MerianSchemaV45.self",
            "toVersion: MerianSchemaV48.self",
            "static let migrateV46toV48 = MigrationStage.custom",
            "fromVersion: MerianSchemaV46.self",
            "duplicate-checksum validator"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "The duplicate-prone recent schema cluster must advance through direct jumps. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !schemasSource.contains("MerianSchemaV44.self") &&
                !schemasSource.contains("MerianSchemaV45.self") &&
                !schemasSource.contains("MerianSchemaV46.self"),
            "MerianMigrationPlan.schemas must omit duplicate-prone V44/V45/V46 representatives; source-isolated recent plans handle those stores."
        )
        #expect(
                !stagesSource.contains("migrateV43toV44") &&
                !stagesSource.contains("migrateV44toV45") &&
                !stagesSource.contains("migrateV43toV47") &&
                !stagesSource.contains("migrateV45toV47") &&
                !stagesSource.contains("migrateV44toV48") &&
                !stagesSource.contains("migrateV45toV48") &&
                !stagesSource.contains("migrateV46toV48") &&
                !stagesSource.contains("migrateV47toV48") &&
                stagesSource.contains("migrateV43toV48"),
            "The full historical stage list must jump V43->V48 and avoid V44/V45/V46/V47 source-isolated recent hops."
        )
        #expect(
            !source.contains("migrateV45toV46") &&
                !source.contains("static let migrateV43toV47") &&
                !source.contains("static let migrateV44toV47") &&
                !source.contains("migrateV46toV47") &&
                !source.contains("migrateV45toV47"),
            "Do not reintroduce staged V43/V44/V45/V46 hops through V47; V47 queued-scan fetches are only safe for true V47 stores."
        )
    }

    @Test func v47AvoidsHistoricalQueueModelAliases() throws {
        let source = try schemaVersionsSource()
        let requiredSnippets = [
            "extension MerianSchemaV47",
            "final class CapturedMediaEntry",
            "final class LocalScanRecord",
            "final class ScanCollection",
            "final class OfflineQueuedScan",
            "@Relationship(deleteRule: .cascade) var capturedMediaEntries: [MerianSchemaV47.CapturedMediaEntry]? = []",
            "@Relationship(inverse: \\MerianSchemaV47.LocalScanRecord.collections) var scans: [MerianSchemaV47.LocalScanRecord]? = []"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "V47 must keep its scan/media/collection models frozen inside V47 so neither active models nor V45/V42 aliases can pull the wrong OfflineQueuedScan metadata into V47 stores:\n\(missing.joined(separator: "\n"))"
        )

        let v47Extension = source
            .components(separatedBy: "extension MerianSchemaV47")
            .dropFirst()
            .first?
            .components(separatedBy: "\nextension MerianSchemaV44")
            .first ?? ""
        #expect(
            !v47Extension.contains("typealias LocalScanRecord = MerianSchemaV45.LocalScanRecord") &&
                !v47Extension.contains("typealias CapturedMediaEntry = MerianSchemaV45.CapturedMediaEntry") &&
                !v47Extension.contains("typealias ScanCollection = MerianSchemaV45.ScanCollection") &&
                !v47Extension.contains("typealias LocalScanRecord = MerianSchemaV46.LocalScanRecord") &&
                !v47Extension.contains("typealias CapturedMediaEntry = MerianSchemaV46.CapturedMediaEntry") &&
                !v47Extension.contains("typealias ScanCollection = MerianSchemaV46.ScanCollection") &&
                !v47Extension.contains("typealias LocalScanRecord = LocalScanRecord") &&
                !v47Extension.contains("typealias CapturedMediaEntry = CapturedMediaEntry") &&
                !v47Extension.contains("typealias ScanCollection = ScanCollection"),
            "V47 cannot point unchanged models at the V45/V46 alias chain or active models; that reintroduces stale queued-scan metadata casts."
        )
        let v47QueuedScanSource = v47Extension
            .components(separatedBy: "final class OfflineQueuedScan")
            .dropFirst()
            .first ?? ""
        #expect(
            !v47QueuedScanSource.contains("capturedMediaEntries"),
            "V47 queued scans must stay scalar-only and let V48 rebuild CapturedMediaEntry rows from capturedMediaJSON; a V47 relationship can trap while SwiftData casts the queued scan model."
        )
    }

    @Test func recentV44MigrationPlanAvoidsAdjacentDuplicateRepresentatives() throws {
        let source = try recentV44MigrationPlanSource()
        let requiredSnippets = [
            "enum MerianRecentV44MigrationPlan",
            "MerianSchemaV44.self",
            "MerianSchemaV48.self",
            "MerianMigrationPlan.migrateV44toV48"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "The recent V44 recovery plan must stay available for V44 stores. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !source.contains("MerianSchemaV43.self") &&
                !source.contains("MerianSchemaV45.self") &&
                !source.contains("MerianSchemaV46.self") &&
                !source.contains("MerianSchemaV47.self") &&
                !source.contains("migrateV44toV47") &&
                !source.contains("migrateV47toV48"),
            "The recent V44 recovery plan must include only one V44/V45/V46-family representative."
        )
    }

    @Test func recentV45MigrationPlanAvoidsAdjacentDuplicateRepresentatives() throws {
        let source = try recentV45MigrationPlanSource()
        let requiredSnippets = [
            "enum MerianRecentV45MigrationPlan",
            "MerianSchemaV45.self",
            "MerianSchemaV48.self",
            "MerianMigrationPlan.migrateV45toV48"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "The recent V45 recovery plan must stay available for V45 stores. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !source.contains("MerianSchemaV43.self") &&
                !source.contains("MerianSchemaV44.self") &&
                !source.contains("MerianSchemaV46.self") &&
                !source.contains("MerianSchemaV47.self") &&
                !source.contains("migrateV45toV47") &&
                !source.contains("migrateV47toV48"),
            "The recent V45 recovery plan must include only the V45 checksum representative and direct V48 target."
        )
    }

    @Test func recentV46MigrationPlanSupportsAlreadyStampedV46StoresWithoutAdjacentDuplicates() throws {
        let source = try recentV46MigrationPlanSource()
        let requiredSnippets = [
            "enum MerianRecentV46MigrationPlan",
            "MerianSchemaV46.self",
            "MerianSchemaV48.self",
            "MerianMigrationPlan.migrateV46toV48"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "The V46 checksum representative plan must remain available for stores already stamped V46. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !source.contains("MerianSchemaV43.self") &&
                !source.contains("MerianSchemaV44.self") &&
                !source.contains("MerianSchemaV45.self") &&
                !source.contains("MerianSchemaV47.self") &&
                !source.contains("migrateV46toV47") &&
                !source.contains("migrateV45toV47") &&
                !source.contains("migrateV45toV48") &&
                !source.contains("migrateV47toV48"),
            "The recent V46 recovery plan must use only the V46 source representative and direct V48 target."
        )
    }

    @Test func recentV47MigrationPlanOnlyRunsQueueMetadataMigration() throws {
        let source = try recentV47MigrationPlanSource()
        let requiredSnippets = [
            "enum MerianRecentV47MigrationPlan",
            "MerianSchemaV47.self",
            "MerianSchemaV48.self",
            "MerianMigrationPlan.migrateV47toV48"
        ]
        let missing = requiredSnippets.filter { !source.contains($0) }

        #expect(
            missing.isEmpty,
            "The recent V47 recovery plan must stay available for stores already on V47. Missing snippets:\n\(missing.joined(separator: "\n"))"
        )
        #expect(
            !source.contains("MerianSchemaV44.self") &&
                !source.contains("MerianSchemaV45.self") &&
                !source.contains("MerianSchemaV46.self"),
            "The recent V47 recovery plan must not include duplicate-prone earlier representatives."
        )
    }

    @Test func migrationFromV44ToCurrentSchemaDoesNotSafeMode() throws {
        let url = migrationStoreURL(named: "v44migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let scanId = "v44-current-migration-scan"

        do {
            let schema44 = Schema(versionedSchema: MerianSchemaV44.self)
            let config44 = ModelConfiguration(schema: schema44, url: url)
            let container44 = try makeModelContainer(for: schema44, configurations: [config44])
            let context44 = ModelContext(container44)
            let record = MerianSchemaV44.LocalScanRecord(
                id: scanId,
                speciesId: "v44-species",
                scientificName: "Danaus plexippus",
                commonName: "Monarch",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild",
                fieldNotes: "created before invasive status fields"
            )
            context44.insert(record)
            try context44.save()
        }

        do {
            let currentSchema = Schema(versionedSchema: CurrentSchema.self)
            let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
            let currentContainer = try makeModelContainer(
                for: currentSchema,
                migrationPlan: MerianRecentV44MigrationPlan.self,
                configurations: [currentConfig]
            )
            let currentContext = ModelContext(currentContainer)
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            let migratedRecord = try #require(currentContext.fetch(descriptor).first)
            #expect(migratedRecord.scientificName == "Danaus plexippus")
            #expect(migratedRecord.invasiveStatusRegion == nil)
            #expect(migratedRecord.fieldNotes == "created before invasive status fields")
        }
    }

    @Test func migrationFromV45ToCurrentSchemaDoesNotSafeMode() throws {
        let url = migrationStoreURL(named: "v45migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let scanId = "v45-current-migration-scan"
        let queuedId = "v45-current-migration-queued"

        do {
            let schema45 = Schema(versionedSchema: MerianSchemaV45.self)
            let config45 = ModelConfiguration(schema: schema45, url: url)
            let container45 = try makeModelContainer(for: schema45, configurations: [config45])
            let context45 = ModelContext(container45)
            let record = MerianSchemaV45.LocalScanRecord(
                id: scanId,
                speciesId: "v45-species",
                scientificName: "Ailanthus altissima",
                commonName: "Tree of Heaven",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: true,
                invasiveStatusRegion: "North America",
                invasiveRationale: "test rationale",
                invasiveConfidence: 0.94,
                ecologyType: "wild"
            )
            let queuedScan = MerianSchemaV45.OfflineQueuedScan(
                id: queuedId,
                stagedR2Keys: ["queued/v45/image.webp"],
                fieldNotes: "queued before inference replay fields"
            )
            context45.insert(record)
            context45.insert(queuedScan)
            try context45.save()
        }

        do {
            let currentSchema = Schema(versionedSchema: CurrentSchema.self)
            let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
            let currentContainer = try makeModelContainer(
                for: currentSchema,
                migrationPlan: MerianRecentV45MigrationPlan.self,
                configurations: [currentConfig]
            )
            let currentContext = ModelContext(currentContainer)

            var scanDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            scanDescriptor.fetchLimit = 1
            let migratedRecord = try #require(currentContext.fetch(scanDescriptor).first)
            #expect(migratedRecord.invasiveStatusRegion == "North America")
            #expect(migratedRecord.invasiveRationale == "test rationale")
            #expect(migratedRecord.invasiveConfidence == 0.94)

            var queuedDescriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == queuedId }
            )
            queuedDescriptor.fetchLimit = 1
            let migratedQueuedScan = try #require(currentContext.fetch(queuedDescriptor).first)
            #expect(migratedQueuedScan.stagedR2Keys == ["queued/v45/image.webp"])
            #expect(migratedQueuedScan.fieldNotes == "queued before inference replay fields")
            #expect(migratedQueuedScan.inferenceImagePaths == nil)
            #expect(migratedQueuedScan.visualMediaItemsJSON == nil)
            assertCurrentQueuedScanHasFreshRetryState(migratedQueuedScan)
            try assertCurrentScanIngestionJob(scanId: queuedId, context: currentContext)
        }
    }

    @Test func migrationFromV46ToCurrentSchemaDoesNotSafeMode() throws {
        let url = migrationStoreURL(named: "v46migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let scanId = "v46-current-migration-scan"
        let queuedId = "v46-current-migration-queued"

        do {
            let schema46 = Schema(versionedSchema: MerianSchemaV46.self)
            let config46 = ModelConfiguration(schema: schema46, url: url)
            let container46 = try makeModelContainer(for: schema46, configurations: [config46])
            let context46 = ModelContext(container46)
            let record = MerianSchemaV46.LocalScanRecord(
                id: scanId,
                speciesId: "v46-species",
                scientificName: "Quercus alba",
                commonName: "White Oak",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                invasiveStatusRegion: "Eastern United States",
                ecologyType: "wild"
            )
            let queuedScan = MerianSchemaV46.OfflineQueuedScan(
                id: queuedId,
                capturedMediaJSON: try String(
                    data: JSONEncoder().encode([SerializedMediaItem.image(.documents("queued-v46.webp"))]),
                    encoding: .utf8
                ),
                coverImagePath: "queued-v46.webp",
                stagedR2Keys: ["queued/v46/image.webp"],
                fieldNotes: "queued during video capture build"
            )
            context46.insert(record)
            context46.insert(queuedScan)
            try context46.save()
        }

        do {
            let currentSchema = Schema(versionedSchema: CurrentSchema.self)
            let currentConfig = ModelConfiguration(schema: currentSchema, url: url)
            let currentContainer = try makeModelContainer(
                for: currentSchema,
                migrationPlan: MerianRecentV46MigrationPlan.self,
                configurations: [currentConfig]
            )
            let currentContext = ModelContext(currentContainer)

            var scanDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            scanDescriptor.fetchLimit = 1
            let migratedRecord = try #require(currentContext.fetch(scanDescriptor).first)
            #expect(migratedRecord.scientificName == "Quercus alba")
            #expect(migratedRecord.invasiveStatusRegion == "Eastern United States")

            var queuedDescriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == queuedId }
            )
            queuedDescriptor.fetchLimit = 1
            let migratedQueuedScan = try #require(currentContext.fetch(queuedDescriptor).first)
            #expect(migratedQueuedScan.coverImagePath == "queued-v46.webp")
            #expect(migratedQueuedScan.stagedR2Keys == ["queued/v46/image.webp"])
            #expect(migratedQueuedScan.fieldNotes == "queued during video capture build")
            #expect(migratedQueuedScan.inferenceImagePaths == nil)
            #expect(migratedQueuedScan.visualMediaItemsJSON == nil)
            assertCurrentQueuedScanHasFreshRetryState(migratedQueuedScan)
            try assertCurrentScanIngestionJob(scanId: queuedId, context: currentContext)
        }
    }

    @Test func migrationFromV47ToCurrentSchemaDoesNotSafeMode() throws {
        let url = migrationStoreURL(named: "v47migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let queuedId = "v47-current-migration-video-queued"
        let capturedMediaJSON = try String(
            data: JSONEncoder().encode([
                SerializedMediaItem.video(StoredVideoMediaReference(
                    .documents("queued-v47-video.mp4"),
                    thumbnail: .documents("queued-v47-thumbnail.webp")
                ))
            ]),
            encoding: .utf8
        )
        let visualMediaItemsJSON = """
        [{"kind":"video_frame","path":"queued-v47-frame-1.webp"},{"kind":"video_frame","path":"queued-v47-frame-2.webp"}]
        """

        do {
            let schema47 = Schema(versionedSchema: MerianSchemaV47.self)
            let config47 = ModelConfiguration(schema: schema47, url: url)
            let container47 = try makeModelContainer(for: schema47, configurations: [config47])
            let context47 = ModelContext(container47)
            let queuedScan = MerianSchemaV47.OfflineQueuedScan(
                id: queuedId,
                capturedMediaJSON: capturedMediaJSON,
                coverImagePath: "queued-v47-thumbnail.webp",
                stagedR2Keys: ["queued/v47/video.mp4"],
                inferenceImagePaths: ["queued-v47-frame-1.webp", "queued-v47-frame-2.webp"],
                visualMediaItemsJSON: visualMediaItemsJSON,
                fieldNotes: "queued before durable retry metadata"
            )
            context47.insert(queuedScan)
            try context47.save()
        }

        do {
            let store = try openCurrentMigrationStore(at: url)
            let migratedQueuedScan = try fetchCurrentQueuedScan(id: queuedId, context: store.context)
            #expect(migratedQueuedScan.capturedMediaJSON == capturedMediaJSON)
            #expect(migratedQueuedScan.coverImagePath == "queued-v47-thumbnail.webp")
            #expect(migratedQueuedScan.stagedR2Keys == ["queued/v47/video.mp4"])
            #expect(migratedQueuedScan.inferenceImagePaths == ["queued-v47-frame-1.webp", "queued-v47-frame-2.webp"])
            #expect(migratedQueuedScan.visualMediaItemsJSON == visualMediaItemsJSON)
            #expect(migratedQueuedScan.fieldNotes == "queued before durable retry metadata")
            assertCurrentQueuedScanHasFreshRetryState(migratedQueuedScan)
            try assertCurrentScanIngestionJob(scanId: queuedId, context: store.context)
        }
    }

    @Test func migrationFromV47PreservesAllQueuedMediaKinds() throws {
        let url = migrationStoreURL(named: "v47_all_media_migration_test")
        defer { keepSQLiteStoreForProcessLifetime(at: url) }

        let fixtures = [
            QueuedMediaMigrationFixture(
                id: "v47-image-queued",
                items: [.image(.documents("queued-image.webp"))],
                cover: "queued-image.webp",
                inferencePaths: nil,
                visualJSON: nil
            ),
            QueuedMediaMigrationFixture(
                id: "v47-video-queued",
                items: [
                    .video(StoredVideoMediaReference(
                        .documents("queued-video.mp4"),
                        thumbnail: .documents("queued-video-thumbnail.webp"),
                        audio: .documents("queued-video-audio.wav")
                    ))
                ],
                cover: "queued-video-thumbnail.webp",
                inferencePaths: ["queued-video-frame-1.webp", "queued-video-frame-2.webp"],
                visualJSON: """
                [{"kind":"video_frame","path":"queued-video-frame-1.webp"},{"kind":"video_frame","path":"queued-video-frame-2.webp"}]
                """
            ),
            QueuedMediaMigrationFixture(
                id: "v47-audio-queued",
                items: [.audio(.documents("queued-audio.wav"))],
                cover: nil,
                inferencePaths: nil,
                visualJSON: nil
            ),
            QueuedMediaMigrationFixture(
                id: "v47-description-queued",
                items: [.description(ObservationContext(freeText: "Queued description-only observation"))],
                cover: nil,
                inferencePaths: nil,
                visualJSON: nil
            ),
            QueuedMediaMigrationFixture(
                id: "v47-mixed-queued",
                items: [
                    .image(.documents("mixed-image.webp")),
                    .audio(.documents("mixed-audio.wav")),
                    .description(ObservationContext(freeText: "Mixed queued observation"))
                ],
                cover: "mixed-image.webp",
                inferencePaths: nil,
                visualJSON: nil
            )
        ]

        do {
            let schema47 = Schema(versionedSchema: MerianSchemaV47.self)
            let config47 = ModelConfiguration(schema: schema47, url: url)
            let container47 = try makeModelContainer(for: schema47, configurations: [config47])
            let context47 = ModelContext(container47)
            for fixture in fixtures {
                context47.insert(MerianSchemaV47.OfflineQueuedScan(
                    id: fixture.id,
                    capturedMediaJSON: try encodedMediaJSON(fixture.items),
                    coverImagePath: fixture.cover,
                    stagedR2Keys: ["queued/v47/\(fixture.id)"],
                    inferenceImagePaths: fixture.inferencePaths,
                    visualMediaItemsJSON: fixture.visualJSON,
                    fieldNotes: "fixture \(fixture.id)"
                ))
            }
            try context47.save()
        }

        let store = try openCurrentMigrationStore(at: url)
        for fixture in fixtures {
            let migratedQueuedScan = try fetchCurrentQueuedScan(id: fixture.id, context: store.context)
            #expect(migratedQueuedScan.serializedCapturedMediaItems == fixture.items)
            #expect(migratedQueuedScan.coverImagePath == fixture.cover)
            #expect(migratedQueuedScan.stagedR2Keys == ["queued/v47/\(fixture.id)"])
            #expect(migratedQueuedScan.inferenceImagePaths == fixture.inferencePaths)
            #expect(migratedQueuedScan.visualMediaItemsJSON == fixture.visualJSON)
            #expect(migratedQueuedScan.fieldNotes == "fixture \(fixture.id)")
            assertCurrentQueuedScanHasFreshRetryState(migratedQueuedScan)
            try assertCurrentScanIngestionJob(scanId: fixture.id, context: store.context)
        }
    }

    /// Simulates upgrading from V38 to V39 — verifies that the custom migration stage
    /// correctly backfills the singular `audioFilePath`/`observationContextJSON` String?
    /// columns into the new plural `audioFilePaths`/`observationContextsJSON` [String]? arrays.
    ///
    /// Zeroes the four `nonisolated(unsafe) static var` backfill dictionaries before and
    /// after via `defer` to prevent false positives from other tests running in the same process.

    @Test func testFullMigrationV38ToV40() throws {
        // Guard against stale backfill data from a prior test in the same process.
        MerianMigrationPlan._v38LocalAudioBackfill.removeAll()
        MerianMigrationPlan._v38LocalContextBackfill.removeAll()
        MerianMigrationPlan._v38OfflineAudioBackfill.removeAll()
        MerianMigrationPlan._v38OfflineContextBackfill.removeAll()
        MerianMigrationPlan._v38LocalAdditionalImagesBackfill.removeAll()
        MerianMigrationPlan._v38LocalSemanticTagsBackfill.removeAll()
        MerianMigrationPlan._v38OfflineLocalImagesBackfill.removeAll()
        defer {
            MerianMigrationPlan._v38LocalAudioBackfill.removeAll()
            MerianMigrationPlan._v38LocalContextBackfill.removeAll()
            MerianMigrationPlan._v38OfflineAudioBackfill.removeAll()
            MerianMigrationPlan._v38OfflineContextBackfill.removeAll()
            MerianMigrationPlan._v38LocalAdditionalImagesBackfill.removeAll()
            MerianMigrationPlan._v38LocalSemanticTagsBackfill.removeAll()
            MerianMigrationPlan._v38OfflineLocalImagesBackfill.removeAll()
        }

        let url = migrationStoreURL(named: "v38migration_test")

        // Step 1 — create a V38 store with both model types carrying the singular fields.
        let schema38 = Schema(versionedSchema: MerianSchemaV38.self)
        let config38 = ModelConfiguration(schema: schema38, url: url)
        let container38 = try makeModelContainer(for: schema38, configurations: [config38])
        let context38 = ModelContext(container38)

        let localRecord = MerianSchemaV38.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            observationContextJSON: "{\"freeText\":\"Yellow wings\"}",
            audioFilePath: "recording_abc.wav"
        )
        localRecord.additionalImagePaths = ["extra1.webp"]
        localRecord.localImagePath = "main_image.webp"
        context38.insert(localRecord)

        let offlineRecord = MerianSchemaV38.OfflineQueuedScan(
            localImagePaths: ["offline_img1.webp"],
            observationContextJSON: "{\"freeText\":\"Near water\"}",
            audioFilePath: "offline_recording.wav"
        )
        context38.insert(offlineRecord)
        try context38.save()

        let capturedLocalId = localRecord.id
        let capturedOfflineId = offlineRecord.id
        _ = container38

        // Step 2 — reopen with the full migration plan targeting V40 (CurrentSchema).
        let schema40 = Schema(versionedSchema: CurrentSchema.self)
        let config40 = ModelConfiguration(schema: schema40, url: url)
        let container40 = try makeModelContainer(
            for: schema40,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config40]
        )

        // Step 3 — verify both models migrated to V40 correctly.
        let context40 = ModelContext(container40)

        var localDescriptor = FetchDescriptor<LocalScanRecord>()
        localDescriptor.fetchLimit = 500
        let localScans = try context40.fetch(localDescriptor)
        let migratedLocal = localScans.first { $0.id == capturedLocalId }
        #expect(migratedLocal != nil, "LocalScanRecord must survive V38→V40 migration")
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("recording_abc.wav") == true,
            "capturedMediaJSON must contain audioFilePath"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("Yellow wings") == true,
            "capturedMediaJSON must contain observationContextJSON"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("extra1.webp") == true,
            "capturedMediaJSON must contain additionalImagePaths"
        )
        #expect(
            migratedLocal?.capturedMediaJSON?.contains("main_image.webp") == true,
            "capturedMediaJSON must contain main_image.webp"
        )

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>()
        offlineDescriptor.fetchLimit = 500
        let offlineScans = try context40.fetch(offlineDescriptor)
        let migratedOffline = offlineScans.first { $0.id == capturedOfflineId }
        #expect(migratedOffline != nil, "OfflineQueuedScan must survive V38→V40 migration")
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("offline_recording.wav") == true,
            "capturedMediaJSON must contain audioFilePath"
        )
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("Near water") == true,
            "capturedMediaJSON must contain observationContextJSON"
        )
        #expect(
            migratedOffline?.capturedMediaJSON?.contains("offline_img1.webp") == true,
            "capturedMediaJSON must contain localImagePaths"
        )

        // Keep the temp store alive for the test process; see keepSQLiteStoreForProcessLifetime.
        keepSQLiteStoreForProcessLifetime(at: url)
    }
    @Test func testFullMigrationV39ToV40BackfillsMediaJSON() throws {
        // Ensures cleanup of static state between runs.
        defer {
            MerianMigrationPlan._v39LocalMediaBackfill.removeAll()
            MerianMigrationPlan._v39OfflineMediaBackfill.removeAll()
            MerianMigrationPlan._v39LocalCoverBackfill.removeAll()
            MerianMigrationPlan._v39OfflineCoverBackfill.removeAll()
        }

        let url = migrationStoreURL(named: "v39migration_test")

        // Step 1 — create a V39 store with plural fields populated.
        let schema39 = Schema(versionedSchema: MerianSchemaV39.self)
        let config39 = ModelConfiguration(schema: schema39, url: url)
        let container39 = try makeModelContainer(for: schema39, configurations: [config39])
        let context39 = ModelContext(container39)

        let localRecord = MerianSchemaV39.LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Testus testus",
            commonName: "Test Species",
            localImagePath: "main_image.webp",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            additionalImagePaths: ["extra1.webp", "extra2.webp"],
            observationContextsJSON: ["{\"freeText\":\"Yellow wings\"}"]
        )
        // Set audioFilePaths manually since init doesn't take it in V39 snapshot
        localRecord.audioFilePaths = ["recording_abc.wav"]
        context39.insert(localRecord)

        let offlineRecord = MerianSchemaV39.OfflineQueuedScan(
            localImagePaths: ["offline_main.webp", "offline_extra.webp"],
            observationContextsJSON: ["{\"freeText\":\"Near water\"}"]
        )
        // Set audioFilePaths manually
        offlineRecord.audioFilePaths = ["offline_recording.wav"]
        context39.insert(offlineRecord)
        try context39.save()

        let capturedLocalId = localRecord.id
        let capturedOfflineId = offlineRecord.id
        _ = container39

        // Step 2 — reopen with the full migration plan targeting V40 (CurrentSchema).
        let schema40 = Schema(versionedSchema: CurrentSchema.self)
        let config40 = ModelConfiguration(schema: schema40, url: url)
        let container40 = try makeModelContainer(
            for: schema40,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config40]
        )

        // Step 3 — verify both models had their arrays consolidated into capturedMediaJSON.
        let context40 = ModelContext(container40)

        var localDescriptor = FetchDescriptor<LocalScanRecord>()
        localDescriptor.fetchLimit = 500
        let localScans = try context40.fetch(localDescriptor)
        let migratedLocal = localScans.first { $0.id == capturedLocalId }
        
        #expect(migratedLocal != nil, "LocalScanRecord must survive V39→V40 migration")
        
        // Assert coverImagePath is the first image
        #expect(migratedLocal?.coverImagePath == "main_image.webp", "coverImagePath must be the first image")
        
        // Decode JSON and verify structure and order
        if let jsonStr = migratedLocal?.capturedMediaJSON,
           let jsonData = jsonStr.data(using: String.Encoding.utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            #expect(items.count == 5, "Should have 5 items: 1 main image, 2 extra images, 1 description, 1 audio")
            
            if items.count == 5 {
                if case .image(let path) = items[0] { #expect(path == "main_image.webp") } else { Issue.record("Item 0 not image") }
                if case .image(let path) = items[1] { #expect(path == "extra1.webp") } else { Issue.record("Item 1 not image") }
                if case .image(let path) = items[2] { #expect(path == "extra2.webp") } else { Issue.record("Item 2 not image") }
                if case .description(let ctx) = items[3] { #expect(ctx.freeText == "Yellow wings") } else { Issue.record("Item 3 not description") }
                if case .audio(let path) = items[4] { #expect(path == "recording_abc.wav") } else { Issue.record("Item 4 not audio") }
            }
        } else {
            Issue.record("Failed to decode capturedMediaJSON for migratedLocal")
        }

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>()
        offlineDescriptor.fetchLimit = 500
        let offlineScans = try context40.fetch(offlineDescriptor)
        let migratedOffline = offlineScans.first { $0.id == capturedOfflineId }
        
        #expect(migratedOffline != nil, "OfflineQueuedScan must survive V39→V40 migration")
        
        // Assert coverImagePath is the first image
        #expect(migratedOffline?.coverImagePath == "offline_main.webp", "coverImagePath must be the first image")
        
        // Decode JSON and verify structure and order
        if let jsonStr = migratedOffline?.capturedMediaJSON,
           let jsonData = jsonStr.data(using: String.Encoding.utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            #expect(items.count == 4, "Should have 4 items: 2 images, 1 description, 1 audio")
            
            if items.count == 4 {
                if case .image(let path) = items[0] { #expect(path == "offline_main.webp") } else { Issue.record("Item 0 not image") }
                if case .image(let path) = items[1] { #expect(path == "offline_extra.webp") } else { Issue.record("Item 1 not image") }
                if case .description(let ctx) = items[2] { #expect(ctx.freeText == "Near water") } else { Issue.record("Item 2 not description") }
                if case .audio(let path) = items[3] { #expect(path == "offline_recording.wav") } else { Issue.record("Item 3 not audio") }
            }
        } else {
            Issue.record("Failed to decode capturedMediaJSON for migratedOffline")
        }

        // Keep the temp store alive for the test process; see keepSQLiteStoreForProcessLifetime.
        keepSQLiteStoreForProcessLifetime(at: url)
    }

    @Test func testFullMigrationV40ToV41BackfillsCapturedMediaEntries() throws {
        let url = migrationStoreURL(named: "v40migration_test")

        let schema40 = Schema(versionedSchema: MerianSchemaV40.self)
        let config40 = ModelConfiguration(schema: schema40, url: url)
        let container40 = try makeModelContainer(for: schema40, configurations: [config40])
        let context40 = ModelContext(container40)

        let localItems: [SerializedMediaItem] = [
            .image(.documents("migration_local.webp")),
            .description(ObservationContext(freeText: "Migrated local description")),
            .audio(.documents("migration_local.wav"))
        ]
        let offlineItems: [SerializedMediaItem] = [
            .image(.documents("migration_offline.webp")),
            .audio(.documents("migration_offline.wav"))
        ]

        let localRecord = MerianSchemaV40.LocalScanRecord(
            id: "migration_v40_local",
            speciesId: "species-v40-local",
            scientificName: "Migratus localis",
            commonName: "Migrated Local",
            capturedMediaJSON: try String(data: JSONEncoder().encode(localItems), encoding: .utf8),
            coverImagePath: "migration_local.webp",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        let offlineRecord = MerianSchemaV40.OfflineQueuedScan(
            id: "migration_v40_offline",
            capturedMediaJSON: try String(data: JSONEncoder().encode(offlineItems), encoding: .utf8),
            coverImagePath: "migration_offline.webp"
        )

        context40.insert(localRecord)
        context40.insert(offlineRecord)
        try context40.save()
        _ = container40

        let schema41 = Schema(versionedSchema: CurrentSchema.self)
        let config41 = ModelConfiguration(schema: schema41, url: url)
        let container41 = try makeModelContainer(
            for: schema41,
            migrationPlan: MerianMigrationPlan.self,
            configurations: [config41]
        )
        let context41 = ModelContext(container41)

        var localDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "migration_v40_local" }
        )
        localDescriptor.fetchLimit = 1
        let migratedLocal = try #require(context41.fetch(localDescriptor).first)
        #expect(migratedLocal.capturedMediaEntries?.count == localItems.count)
        #expect(migratedLocal.serializedCapturedMediaItems == localItems)
        #expect(migratedLocal.coverImagePath == "migration_local.webp")

        var offlineDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == "migration_v40_offline" }
        )
        offlineDescriptor.fetchLimit = 1
        let migratedOffline = try #require(context41.fetch(offlineDescriptor).first)
        #expect(migratedOffline.capturedMediaEntries?.count == offlineItems.count)
        #expect(migratedOffline.serializedCapturedMediaItems == offlineItems)
        #expect(migratedOffline.coverImagePath == "migration_offline.webp")

        keepSQLiteStoreForProcessLifetime(at: url)
    }

    @Test func testSerializedMediaItemDecodesLegacyStringPayloadsIntoTypedReferences() throws {
        let legacyJSON = """
        [
          {"image":{"_0":"legacy_image.webp"}},
          {"image":{"_0":"https://example.com/remote.webp"}},
          {"audio":{"_0":"legacy_audio.wav"}},
          {"audio":{"_0":"/tmp/absolute_audio.wav"}}
        ]
        """

        let items = try JSONDecoder().decode([SerializedMediaItem].self, from: Data(legacyJSON.utf8))
        #expect(items.count == 4)

        if case .image(let documentsImage) = items[0] {
            #expect(documentsImage.storage == .documents)
            #expect(documentsImage.serializedPath == "legacy_image.webp")
        } else {
            Issue.record("Legacy documents image did not decode as image")
        }

        if case .image(let remoteImage) = items[1] {
            #expect(remoteImage.storage == .remoteURL)
            #expect(remoteImage.serializedPath == "https://example.com/remote.webp")
        } else {
            Issue.record("Legacy remote image did not decode as image")
        }

        if case .audio(let documentsAudio) = items[2] {
            #expect(documentsAudio.storage == .documents)
            #expect(documentsAudio.serializedPath == "legacy_audio.wav")
        } else {
            Issue.record("Legacy documents audio did not decode as audio")
        }

        if case .audio(let absoluteAudio) = items[3] {
            #expect(absoluteAudio.storage == .absolutePath)
            #expect(absoluteAudio.serializedPath == "/tmp/absolute_audio.wav")
        } else {
            Issue.record("Legacy absolute audio did not decode as audio")
        }
    }

    @Test func testSerializedMediaItemRoundTripsTypedStorageMetadata() throws {
        let encoded = try JSONEncoder().encode([
            SerializedMediaItem.image(.remoteURL("https://example.com/r2.webp")),
            SerializedMediaItem.audio(.documents("recording.wav"))
        ])

        let jsonString = try #require(String(data: encoded, encoding: .utf8))
        #expect(jsonString.contains("\"storage\":\"remoteURL\""))
        #expect(jsonString.contains("\"storage\":\"documents\""))
        #expect(MediaJSONParser.hasCloudImage(jsonString: jsonString))
        #expect(MediaJSONParser.imagePaths(jsonString: jsonString) == ["https://example.com/r2.webp"])
        #expect(MediaJSONParser.audioPaths(jsonString: jsonString) == ["recording.wav"])

        let decoded = try #require(MediaJSONParser.serializedItems(jsonString: jsonString))

        if case .image(let remoteImage) = decoded[0] {
            #expect(remoteImage.storage == .remoteURL)
        } else {
            Issue.record("Typed remote image did not round-trip as image")
        }

        if case .audio(let documentsAudio) = decoded[1] {
            #expect(documentsAudio.storage == .documents)
        } else {
            Issue.record("Typed documents audio did not round-trip as audio")
        }
    }

    @Test func testCapturedMediaSnapshotBuildsSharedDerivedViews() throws {
        let context = ObservationContext(freeText: "Perched near the creek")
        let snapshot = CapturedMediaSnapshot(items: [
            .audio(.documents("recording.wav")),
            .description(context),
            .image(.remoteURL("https://example.com/r2.webp"))
        ])

        #expect(snapshot.imagePaths == ["https://example.com/r2.webp"])
        #expect(snapshot.audioPaths == ["recording.wav"])
        #expect(snapshot.primaryImagePath == "https://example.com/r2.webp")
        #expect(snapshot.hasCloudImage)
        #expect(snapshot.summary == CapturedMediaSummary(
            hasImage: true,
            hasAudio: true,
            hasVideo: false,
            hasDescription: true
        ))
        #expect(snapshot.descriptionText == context.serialized())
        #expect(snapshot.observationContexts == [context])
        #expect(snapshot.observationContextsJSON?.count == 1)

        let activeMedia = snapshot.activeScanMedia
        #expect(activeMedia.totalItems == 3)

        if case .audio(let audioPath) = activeMedia.items[0] {
            #expect(audioPath.hasSuffix("recording.wav"))
        } else {
            Issue.record("First active media item should be audio")
        }

        if case .description(let decodedContext) = activeMedia.items[1] {
            #expect(decodedContext == context)
        } else {
            Issue.record("Second active media item should be description")
        }

        if case .image(let imagePath) = activeMedia.items[2] {
            #expect(imagePath == "https://example.com/r2.webp")
        } else {
            Issue.record("Third active media item should be image")
        }
    }
}
