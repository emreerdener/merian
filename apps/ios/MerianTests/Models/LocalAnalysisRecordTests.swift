import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct LocalAnalysisRecordTests {
    private let analysisID = UUID(uuidString: "00000000-0000-4000-8000-000000000055")!
    private let ownerID = UUID(uuidString: "00000000-0000-4000-8000-000000000056")!
    private let completedAt = Date(timeIntervalSince1970: 123456)

    private func scan() -> LocalScanRecord {
        LocalScanRecord(id: "legacy-exact-identity", speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
    }

    private func record(
        scan: LocalScanRecord,
        data: Data = Data("{\"synthetic\":true}".utf8),
        version: Int = 1
    ) throws -> LocalAnalysisRecord {
        try LocalAnalysisRecord(analysisID: analysisID, observationID: scan.id,
                                ownerAccountID: ownerID, completedAt: completedAt,
                                snapshotVersion: version, resultSnapshotData: data)
    }

    @Test func storageBoundsAreExecutableAndVersionsFailClosed() throws {
        let scan = scan()
        let prefix = "{\"padding\":\""
        let suffix = "\"}"
        let data = Data((prefix + String(repeating: "x", count: LocalAnalysisRecord.maximumSnapshotBytes - prefix.utf8.count - suffix.utf8.count) + suffix).utf8)
        #expect(try record(scan: scan, data: data).resultSnapshotData == data)
        #expect(throws: LocalAnalysisRecord.StorageError.invalidSnapshot) {
            try record(scan: scan, data: data + Data(" ".utf8))
        }
        for malformed in ["", "[]", "null", "true", "42", "{broken}"] {
            #expect(throws: LocalAnalysisRecord.StorageError.invalidSnapshot) {
                try record(scan: scan, data: Data(malformed.utf8))
            }
        }
        for version in [0, 5, -1] {
            #expect(throws: LocalAnalysisRecord.StorageError.unsupportedVersion) {
                try record(scan: scan, version: version)
            }
        }
        scan.id = ""
        #expect(throws: LocalAnalysisRecord.StorageError.invalidObservation) {
            try record(scan: scan)
        }
        scan.id = "valid-local-id"
        #expect(throws: LocalAnalysisRecord.StorageError.invalidCompletionDate) {
            try LocalAnalysisRecord(analysisID: analysisID, observationID: scan.id,
                                    ownerAccountID: ownerID, completedAt: Date(timeIntervalSinceReferenceDate: .infinity),
                                    resultSnapshotData: Data("{}".utf8))
        }
    }

    @Test func onlyImportedSavedIdentificationsHaveUnknownCompletion() throws {
        let scan = scan()
        let imported = try LocalAnalysisRecord(analysisID: analysisID, observationID: scan.id,
            ownerAccountID: ownerID, completedAt: nil, snapshotVersion: 3, resultSnapshotData: Data("{}".utf8))
        #expect(imported.completedAt == nil)
        for version in [1, 2, 4] {
            #expect(throws: LocalAnalysisRecord.StorageError.invalidCompletionDate) {
                try LocalAnalysisRecord(analysisID: analysisID, observationID: scan.id,
                    ownerAccountID: ownerID, completedAt: nil, snapshotVersion: version, resultSnapshotData: Data("{}".utf8))
            }
        }
        #expect(throws: LocalAnalysisRecord.StorageError.invalidCompletionDate) {
            try record(scan: scan, version: 3)
        }
    }

    @Test func repeatedIdentityWithIdenticalBytesStoresOneChild() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let scan = scan()
        context.insert(scan)
        context.insert(try record(scan: scan))
        try context.save()
        context.insert(try record(scan: scan))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        let saved = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(saved.resultSnapshotData == Data("{\"synthetic\":true}".utf8))
        #expect(saved.observationID == scan.id)
        // SwiftData uniqueness is upsert, not conflict rejection. Admission must
        // compare immutable bytes before any insert when production wiring lands.
    }

    @Test(arguments: [1, 4]) func diskReopenPreservesPrivateBytesAndParentDeletionCascades(version: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("analysis-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // SwiftData may retain SQLite handles for the process lifetime; use a unique
        // store and do not remove its sidecars while the framework still owns them.
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("fixture.store"))
        let bytes = Data("{ \"synthetic\" : true, \"private_evidence\": [\"fixture\"] }".utf8)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let scan = scan()
            context.insert(scan)
            let result = try record(scan: scan, data: bytes, version: version)
            context.insert(result)
            scan.analysisRecords = [result]
            try context.save()
            #expect(scan.analysisSelectionInitialized)
            #expect(scan.selectedAnalysisID == nil)
            #expect(scan.analysisOwnerAccountID == nil)
            #expect(scan.observationStateRevision == nil)
            #expect(scan.scientificName == "Fixture")
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let result = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
            #expect(result.id == analysisID.uuidString.lowercased())
            #expect(result.observationID == "legacy-exact-identity")
            #expect(result.ownerAccountID == ownerID.uuidString.lowercased())
            #expect(result.completedAt == completedAt)
            #expect(result.snapshotVersion == version)
            #expect(result.resultSnapshotData == bytes)
            let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            #expect(scan.analysisRecords?.count == 1)
            context.delete(scan)
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(reopened)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
    }
}
