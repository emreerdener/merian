import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct SharedMediaSubmissionStorageTests {
    @Test(arguments: [false, true])
    func bindingAndTerminalFenceSurviveQueueCleanup(_ erased: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("submission.store")
        let ids = (0..<7).map { _ in UUID() }, opaque = Data([0, 255, 17, 128])
        func open() throws -> ModelContainer {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try open(), context = ModelContext(container)
            context.autosaveEnabled = false
            let row = SharedMediaOrdinarySubmissionRecord(inventoryID: ids[0], inventoryGeneration: ids[1],
                ownerID: ids[2], recipientScanID: ids[3], submissionGeneration: ids[4],
                jobID: "synthetic-job", eventID: ids[5], writerEpoch: ids[6], formatRaw: "synthetic-format",
                requestData: opaque, requestSHA256: "synthetic-request", observationSHA256: "synthetic-observation")
            row.phaseRaw = erased ? "erased" : "accepted"; row.revision = 7
            row.acceptanceData = opaque; row.acceptanceSHA256 = "synthetic-accepted"
            if erased {
                row.requestData = nil
                row.retirementData = opaque; row.retirementSHA256 = "synthetic-retirement"
            }
            let queue = OfflineQueuedScan(id: ids[3].uuidString.lowercased(), timestamp: .distantPast)
            let job = OfflineJobRecord(id: "synthetic-job", kind: .scanIngestion, subjectId: queue.id)
            context.insert(row); context.insert(queue); context.insert(job); try context.save()
            context.delete(queue); context.delete(job); try context.save()
        }
        let container = try open(), context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>())
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.id == ids[4] && row.cursorKey == ids[4].uuidString.lowercased())
        #expect(row.identityKey == SharedMediaOrdinarySubmission.identityKey(ownerID: ids[2], scanID: ids[3], generation: ids[4]))
        #expect(row.scanKey == [ids[2], ids[3]].map { $0.uuidString.lowercased() }.joined(separator: ":"))
        #expect(row.inventoryID == ids[0] && row.inventoryGeneration == ids[1] && row.ownerID == ids[2])
        #expect(row.recipientScanID == ids[3] && row.submissionGeneration == ids[4])
        #expect(row.jobID == "synthetic-job" && row.eventID == ids[5] && row.writerEpoch == ids[6])
        #expect(row.schemaVersion == 1 && row.revision == 7 && row.formatRaw == "synthetic-format")
        #expect(row.phaseRaw == (erased ? "erased" : "accepted"))
        #expect(row.requestData == (erased ? nil : opaque) && row.requestSHA256 == "synthetic-request")
        #expect(row.observationSHA256 == "synthetic-observation")
        #expect(row.acceptanceData == opaque && row.acceptanceSHA256 == "synthetic-accepted")
        #expect(row.retirementData == (erased ? opaque : nil))
        #expect(row.retirementSHA256 == (erased ? "synthetic-retirement" : nil))
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        // Opaque storage is not a qualified acceptance/erasure receipt. An
        // orphan binding alone must prevent bootstrap, purge and owner access.
        #expect(try SharedMediaStorageLookup.hasLiabilities(in: context))
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoNativeOwnership(context) }
        #expect(throws: (any Error).self) { try SharedMediaNativeEligibility.requireOriginalAccount(context, ownerID: ids[2]) }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeOriginalAccounting.audit(assetID: UUID(), inventoryID: ids[0], context: context)
        }
        #expect(SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(SharedMediaOrdinarySubmissionRecord.self)))
        #expect(!context.hasChanges)
    }
}
