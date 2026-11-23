import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
struct SharedMediaOrdinaryArtifactStorageTests {
    @Test(arguments: ["reserved", "ready", "accepted", "released", "unknown"])
    func orphanArtifactSurvivesReopenAndBlocksUnqualifiedCleanup(_ phase: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("artifact.store")
        let ids = (0..<11).map { _ in UUID() }, opaque = Data([0, 255, 17, 128])
        func open() throws -> ModelContainer {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try open(), context = ModelContext(container)
            context.autosaveEnabled = false
            let row = SharedMediaOrdinaryArtifactRecord(id: ids[0], inventoryID: ids[1], inventoryGeneration: ids[2],
                ownerID: ids[3], recipientScanID: ids[4], submissionGeneration: ids[5], mediaID: ids[6],
                itemIndex: 1, roleRaw: "audio_source", frameIndex: nil, allocationID: ids[7],
                referenceID: ids[8], leaseID: ids[9], writerEpoch: ids[10], requestData: opaque, requestSHA256: "synthetic")
            row.phaseRaw = phase; row.revision = 7
            row.stageReceiptData = opaque; row.stageReceiptSHA256 = "synthetic-stage"
            row.acceptanceData = opaque; row.acceptanceSHA256 = "synthetic-acceptance"
            row.retirementData = opaque; row.retirementSHA256 = "synthetic-retirement"
            context.insert(row); try context.save()
        }
        let container = try open(), context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>())
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.id == ids[0] && row.schemaVersion == 1)
        #expect(row.inventoryID == ids[1] && row.inventoryGeneration == ids[2] && row.ownerID == ids[3])
        #expect(row.recipientScanID == ids[4] && row.submissionGeneration == ids[5] && row.mediaID == ids[6])
        #expect(row.allocationID == ids[7] && row.referenceID == ids[8] && row.leaseID == ids[9] && row.writerEpoch == ids[10])
        #expect(row.itemIndex == 1 && row.roleRaw == "audio_source" && row.frameIndex == nil)
        #expect(row.membershipKey == [ids[3], ids[4], ids[5], ids[6]].map { $0.uuidString.lowercased() }.joined(separator: ":"))
        #expect(row.phaseRaw == phase && row.revision == 7 && row.requestData == opaque && row.requestSHA256 == "synthetic")
        #expect(row.stageReceiptData == opaque && row.stageReceiptSHA256 == "synthetic-stage")
        #expect(row.acceptanceData == opaque && row.acceptanceSHA256 == "synthetic-acceptance")
        #expect(row.retirementData == opaque && row.retirementSHA256 == "synthetic-retirement")
        #expect(try SharedMediaStorageLookup.hasLiabilities(in: context))
        #expect(throws: SharedMediaStorageFailure.closed) { try SharedMediaStorageLookup.requireNoNativeOwnership(context) }
        #expect(throws: SharedMediaStorageFailure.closed) { try SharedMediaStorageLookup.requireNoUnqualifiedOrdinaryTransfers(context) }
        #expect(throws: SharedMediaStorageFailure.inUse) { try SharedMediaPurgeState.requireEmptyGraph(context) }
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaNativeBootstrapDatabase.requireUnassociated(container) }
        #expect(throws: PhotoPreparationFailure.unsupportedComposition) { _ = try PhotoPreparationRepository(container: container) }
        #expect(SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(SharedMediaOrdinaryArtifactRecord.self)))
        #expect(!context.hasChanges)
    }
}
