import Foundation
@testable import Merian
import SwiftData
import Testing

/// Runs against the real frozen-body fixture from the binding suite, but a
/// separate disk store containing only the two receipt models. No native
/// ownership or successful queue acceptance is implied by a receipt read.
@MainActor
enum SharedMediaSubmissionReceiptTests {
    typealias Receipt = SharedMediaOrdinarySubmissionReceipt

    static func check(_ binding: SharedMediaOrdinaryPhotoHoldBinding) throws {
        let submission = try SharedMediaOrdinarySubmission(binding: binding)
        let body = try submission.encoded(), holds = try SharedMediaOrdinaryHoldCohort(binding.orderedRequests)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([SharedMediaOrdinarySubmissionRecord.self, SharedMediaOrdinaryTransferRecord.self])
        let url = directory.appendingPathComponent("ordinary-receipts.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let expected = try SharedMediaOrdinarySubmissionAcceptance(submission: submission, holds: holds)
        let acceptance = try expected.encoded(submission: submission, holds: holds)
        do {
            let container = try open(), context = ModelContext(container); context.autosaveEnabled = false
            #expect(try Receipt.existing(submission, in: context) == nil)
            let row = SharedMediaOrdinarySubmissionRecord(inventoryID: submission.profile.inventoryID,
                inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
                recipientScanID: submission.scanID, submissionGeneration: submission.generation,
                jobID: submission.jobID, eventID: submission.eventID, writerEpoch: submission.writerEpoch,
                formatRaw: submission.format.rawValue, requestData: body,
                requestSHA256: SharedMediaAcquisitionEncoding.digest(body), observationSHA256: submission.observation.sha256)
            context.insert(row)
            let holdRows = try holds.requests.map { request in
                let hold = try holdRow(request)
                context.insert(hold); return hold
            }
            #expect(throws: (any Error).self) { _ = try Receipt.existing(submission, in: context) }
            try context.save()
            #expect(try Receipt.existing(submission, in: context)?.state == .reserved)
            let accepted = try holds.acceptances()
            for (request, hold) in zip(holds.requests, holdRows) {
                let receipt = try #require(accepted[request.id])
                let bytes = try receipt.encoded(request: request)
                hold.phaseRaw = "accepted"; hold.revision = 1
                hold.acceptanceData = bytes; hold.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
            }
            try context.save()
            // Every per-source receipt without its parent acceptance is partial.
            #expect(throws: (any Error).self) { _ = try Receipt.read(row, in: context) }
            row.phaseRaw = "accepted"; row.revision = 1
            row.acceptanceData = acceptance; row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(acceptance)
            try context.save()
            let saved = try #require(try Receipt.existing(submission, in: context))
            #expect(saved.submission == submission && saved.holds == holds && saved.state == .accepted(expected))
            let holdBytes = try holdRows.reduce(Int64(0)) {
                try SharedMediaStoragePolicy.add($0, SharedMediaOrdinaryHoldReceipt.read($1).metadataBytes)
            }
            #expect(saved.metadataBytes == Int64(body.count + acceptance.count + 128) + holdBytes)
        }
        let container = try open(), context = ModelContext(container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()).first)
        #expect(try Receipt.existing(submission, in: context)?.state == .accepted(expected))
        let foreignContext = ModelContext(container); foreignContext.autosaveEnabled = false
        #expect(throws: (any Error).self) { _ = try Receipt.read(row, in: foreignContext) }
        let first = try #require(try context.fetch(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()).first)
        let extraRequest: SharedMediaOrdinaryHoldRequest = try SharedMediaNativeReceivingTestFixture.copy(
            holds.requests[0], changes: ["id": UUID().uuidString])
        let extra = try holdRow(extraRequest)
        context.insert(extra); try context.save()
        #expect(throws: (any Error).self) { _ = try Receipt.read(row, in: context) }
        context.delete(extra); try context.save()
        let originalOwner = row.ownerID
        row.ownerID = UUID(); try context.save()
        #expect(throws: (any Error).self) { _ = try Receipt.existing(submission, in: context) }
        row.ownerID = originalOwner; try context.save()
        let oldScan = first.recipientScanID
        first.recipientScanID = UUID(); try context.save()
        #expect(throws: (any Error).self) { _ = try Receipt.read(row, in: context) }
        first.recipientScanID = oldScan; try context.save()
        row.acceptanceData = acceptance + Data([0]); try context.save()
        #expect(throws: (any Error).self) { _ = try Receipt.read(row, in: context) }
        row.acceptanceData = acceptance; try context.save()
        // Unknown terminal/erased states cannot be reconstructed from surviving
        // per-source requests, nor can a new generation replace the scan binding.
        let changed: SharedMediaOrdinarySubmission = try SharedMediaNativeReceivingTestFixture.copy(submission,
            changes: ["generation": UUID().uuidString])
        #expect(throws: (any Error).self) { _ = try Receipt.existing(changed, in: context) }
        row.requestData = nil; row.phaseRaw = "erased"; row.revision = 2; try context.save()
        #expect(throws: (any Error).self) { _ = try Receipt.existing(submission, in: context) }
        #expect(throws: (any Error).self) { _ = try Receipt.existing(changed, in: context) }
        context.delete(row); try context.save()
        // Orphan holds prevent a second admission even with no parent row.
        #expect(throws: (any Error).self) { _ = try Receipt.existing(submission, in: context) }
    }

    private static func holdRow(_ request: SharedMediaOrdinaryHoldRequest) throws -> SharedMediaOrdinaryTransferRecord {
        let bytes = try request.encoded()
        return SharedMediaOrdinaryTransferRecord(id: request.id, inventoryID: request.profile.inventoryID,
            inventoryGeneration: request.profile.generation, ownerID: request.profile.ownerID,
            sourceAssetID: request.source.assetID, sourceReferenceID: request.source.referenceID,
            recipientScanID: request.recipient.scanID, submissionGeneration: request.recipient.submissionGeneration,
            writerEpoch: request.writerEpoch, requestData: bytes, requestSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
    }
}
