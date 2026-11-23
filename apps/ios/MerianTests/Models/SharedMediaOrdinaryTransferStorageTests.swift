import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
struct SharedMediaOrdinaryTransferStorageTests {
    @Test func savedTransferSurvivesReopenAndBlocksUnqualifiedOwners() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("transfer.store")
        let ids = (0..<9).map { _ in UUID() }, opaque = Data([0, 255, 17, 128])
        func open() throws -> ModelContainer {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try open(), context = ModelContext(container)
            context.autosaveEnabled = false
            let row = SharedMediaOrdinaryTransferRecord(id: ids[0], inventoryID: ids[1],
                inventoryGeneration: ids[2], ownerID: ids[3], sourceAssetID: ids[4], sourceReferenceID: ids[5],
                recipientScanID: ids[6], submissionGeneration: ids[7], writerEpoch: ids[8],
                requestData: opaque, requestSHA256: "synthetic-request")
            row.phaseRaw = "retiring"; row.revision = 7
            row.completionData = opaque; row.completionSHA256 = "synthetic-copy"
            row.acceptanceData = opaque; row.acceptanceSHA256 = "synthetic-accepted"
            row.retirementData = opaque; row.retirementSHA256 = "synthetic-retirement"
            context.insert(row); try context.save()
        }
        let container = try open(), context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<SharedMediaOrdinaryTransferRecord>())
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.id == ids[0] && row.cursorKey == ids[0].uuidString.lowercased())
        #expect(row.inventoryID == ids[1] && row.inventoryGeneration == ids[2] && row.ownerID == ids[3])
        #expect(row.sourceAssetID == ids[4] && row.sourceReferenceID == ids[5] && row.recipientScanID == ids[6])
        #expect(row.submissionGeneration == ids[7] && row.writerEpoch == ids[8] && row.schemaVersion == 1)
        #expect(row.phaseRaw == "retiring" && row.revision == 7)
        #expect(row.requestData == opaque && row.requestSHA256 == "synthetic-request")
        #expect(row.completionData == opaque && row.completionSHA256 == "synthetic-copy")
        #expect(row.acceptanceData == opaque && row.acceptanceSHA256 == "synthetic-accepted")
        #expect(row.retirementData == opaque && row.retirementSHA256 == "synthetic-retirement")
        #expect(try SharedMediaStorageLookup.hasLiabilities(in: context))
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoNativeOwnership(context) }
        #expect(throws: (any Error).self) { try SharedMediaNativeEligibility.requireOriginalAccount(context, ownerID: ids[3]) }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeOriginalAccounting.audit(assetID: ids[4], inventoryID: ids[1], context: context)
        }
        #expect(SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(SharedMediaOrdinaryTransferRecord.self)))
        #expect(!context.hasChanges)
    }
}
