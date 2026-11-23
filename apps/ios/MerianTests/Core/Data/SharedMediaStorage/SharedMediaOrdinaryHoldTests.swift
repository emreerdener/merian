import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Ordinary original hold descriptions", .serialized)
@MainActor
struct SharedMediaOrdinaryHoldTests {
    @Test func canonicalRequestAndAcceptanceBindExactObservationAndSource() throws {
        let request = try fixture(), bytes = try request.encoded()
        #expect(try SharedMediaOrdinaryHoldRequest.decode(bytes, sha256: hash(bytes)) == request)
        #expect(request.recipient.jobID == "scan-ingestion:" + request.recipient.scanID.uuidString.lowercased())
        let receipt = try acceptance(request), receiptBytes = try receipt.encoded(request: request)
        #expect(try SharedMediaOrdinaryHoldAcceptance.decode(receiptBytes, sha256: hash(receiptBytes), request: request) == receipt)
        #expect(throws: (any Error).self) {
            _ = try SharedMediaOrdinaryHoldAcceptance.decode(receiptBytes, sha256: hash(receiptBytes), request: fixture())
        }
        let encoded = try mutation(bytes, path: ["recipient", "preparationSHA256"], value: String(repeating: "d", count: 64))
        let changed = try SharedMediaOrdinaryHoldRequest.decode(encoded, sha256: hash(encoded))
        #expect(throws: (any Error).self) { try receipt.validate(request: changed) }
    }

    @Test(arguments: ["extra", "whitespace", "duplicate", "wrongDigest", "future", "owner", "asset", "reference", "overflow", "zeroCount", "sourceGeneration"])
    func malformedOrReboundRequestsAreRejected(_ fault: String) throws {
        let request = try fixture(), original = try request.encoded()
        let bytes: Data
        switch fault {
        case "extra": bytes = try mutation(original, path: ["extra"], value: true)
        case "whitespace": bytes = original + Data(" ".utf8)
        case "duplicate": bytes = Data("{\"format\":\"ordinaryOriginalHoldV1\",".utf8) + original.dropFirst()
        case "future": bytes = try mutation(original, path: ["format"], value: "ordinaryOriginalHoldV2")
        case "owner": bytes = try mutation(original, path: ["source", "ownerID"], value: UUID().uuidString)
        case "asset": bytes = try mutation(original, path: ["source", "assetID"], value: UUID().uuidString)
        case "reference": bytes = try mutation(original, path: ["id"], value: request.source.referenceID.uuidString)
        case "overflow": bytes = try mutation(original, path: ["inventoryRevision"], value: Int64.max)
        case "zeroCount": bytes = try mutation(original, path: ["liveCount"], value: 0)
        case "sourceGeneration": bytes = try mutation(original, path: ["source", "draftGeneration"], value: UUID().uuidString)
        default: bytes = original
        }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaOrdinaryHoldRequest.decode(bytes, sha256: fault == "wrongDigest" ? String(repeating: "0", count: 64) : hash(bytes))
        }
    }

    @Test func acceptanceRejectsCounterRebaseAndDoesNotOverflowAtBoundary() throws {
        let request = try fixture()
        for (inventory, countRevision, count) in [(request.inventoryRevision, request.countRevision + 1, request.liveCount + 1),
            (request.inventoryRevision + 1, request.countRevision, request.liveCount + 1),
            (request.inventoryRevision + 1, request.countRevision + 1, request.liveCount),
            (request.inventoryRevision + 1, request.countRevision + 1, request.liveCount + 3)] {
            #expect(throws: (any Error).self) {
                _ = try SharedMediaOrdinaryHoldAcceptance(request: request, inventoryRevision: inventory, countRevision: countRevision, liveCount: count)
            }
        }
        let bytes = try mutation(request.encoded(), path: ["liveCount"], value: Int64.max - 1)
        let boundary = try SharedMediaOrdinaryHoldRequest.decode(bytes, sha256: hash(bytes))
        _ = try SharedMediaOrdinaryHoldAcceptance(request: boundary, inventoryRevision: boundary.inventoryRevision + 1,
            countRevision: boundary.countRevision + 1, liveCount: Int64.max)
    }

    @Test func acceptedReceiptSurvivesReopenButDoesNotQualifyOwnership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hold.store"), request = try fixture()
        let receipt = try acceptance(request)
        func open() throws -> ModelContainer {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try open(), context = ModelContext(container), row = try row(request)
            context.autosaveEnabled = false
            row.phaseRaw = "accepted"; row.revision = 1
            row.acceptanceData = try receipt.encoded(request: request); row.acceptanceSHA256 = hash(try #require(row.acceptanceData))
            context.insert(row); try context.save()
        }
        let container = try open(), context = ModelContext(container)
        context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()).first)
        let snapshot = try SharedMediaOrdinaryHoldReceipt.read(row)
        #expect(snapshot.state == .accepted(request, receipt))
        #expect(snapshot.metadataBytes == Int64(row.requestData.count + (row.acceptanceData?.count ?? 0) + 128))
        #expect(try SharedMediaStorageLookup.hasLiabilities(in: context))
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoUnqualifiedOrdinaryTransfers(context) }
        #expect(!context.hasChanges)
    }

    @Test(arguments: ["owner", "asset", "reference", "scan", "generation", "epoch", "inventory", "inventoryGeneration", "schema", "revision", "acceptance", "completion", "retirement", "phase"])
    func rowScalarsAndSidecarsCannotBeAdopted(_ fault: String) throws {
        let row = try row(fixture())
        switch fault {
        case "owner": row.ownerID = UUID()
        case "asset": row.sourceAssetID = UUID()
        case "reference": row.sourceReferenceID = UUID()
        case "scan": row.recipientScanID = UUID()
        case "generation": row.submissionGeneration = UUID()
        case "epoch": row.writerEpoch = UUID()
        case "inventory": row.inventoryID = UUID()
        case "inventoryGeneration": row.inventoryGeneration = UUID()
        case "schema": row.schemaVersion = 2
        case "revision": row.revision = 1
        case "acceptance": row.phaseRaw = "accepted"; row.revision = 1
        case "completion": row.completionData = Data("{}".utf8); row.completionSHA256 = hash(Data("{}".utf8))
        case "retirement": row.retirementSHA256 = String(repeating: "a", count: 64)
        default: row.phaseRaw = "released"
        }
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldReceipt.read(row) }
    }

    @Test func boundsPrecedeDecodeAndSidecarsHaveExactMetadataCharge() throws {
        let tooLarge = Data(repeating: 0, count: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes + 1)
        #expect(throws: SharedMediaStorageFailure.capacity) { _ = try SharedMediaOrdinaryHoldRequest.decode(tooLarge, sha256: hash(tooLarge)) }
        let data = Data("{}".utf8), digest = hash(data)
        #expect(try SharedMediaOrdinaryHoldEncoding.metadataBytes([(data, digest), (nil, nil), (nil, nil), (nil, nil)]) == 66)
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldEncoding.metadataBytes([(data, nil), (nil, nil), (nil, nil), (nil, nil)]) }
    }

    @Test func ownerDescriptionAuditsSharedSourceWithoutTakingAQueueHold() async throws {
        let store = try SharedMediaNativeAppMetadataTests.Store(), owner = try await store.open()
        let acquire = try await owner.prepareAppOriginal(packageID: store.packageID, draftGeneration: store.draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(acquire) { image }
        let source = PhotoOriginalReference(ownerID: acquire.ownerID, packageID: acquire.packageID,
            referenceID: acquire.referenceID, assetID: acquire.assetID, assetGeneration: acquire.assetGeneration,
            draftGeneration: acquire.draftGeneration, referenceRevision: acquired.referenceRevision)
        let share = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner.shareAppOriginal(share)
        let before = try await owner.inspectApp()
        let request = try await owner.describeAppOrdinaryHold(shared, id: UUID(), recipient: recipient())
        #expect(request.source == shared && request.acquisition.packageID == source.packageID)
        #expect(request.acquisition.referenceID == source.referenceID && request.source.referenceID != source.referenceID)
        #expect(request.liveCount == 2)
        #expect(try await owner.inspectApp() == before)
        #expect(try store.context().fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0)
        await #expect(throws: (any Error).self) {
            _ = try await owner.describeAppOrdinaryHold(shared, id: source.assetID, recipient: recipient())
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.describeAppOrdinaryHold(shared, id: UUID(), recipient: recipient()) }
    }

    @Test func cohortRequiresExactCounterDeltaAndCompleteAcceptanceSet() throws {
        let base = try fixture()
        let a = try SharedMediaOrdinaryHoldRequest(id: base.id, profile: base.profile, writerEpoch: base.writerEpoch,
            source: base.source, acquisition: base.acquisition, completion: base.completion, recipient: base.recipient,
            inventoryRevision: 3, sourcePackageRevision: 1, sourceMembershipRevision: 1, liveCount: 2, countRevision: 1)
        let b = try SharedMediaOrdinaryHoldRequest(id: UUID(), profile: a.profile, writerEpoch: a.writerEpoch,
            source: .init(ownerID: a.source.ownerID, packageID: UUID(), referenceID: UUID(), assetID: a.source.assetID,
                assetGeneration: a.source.assetGeneration, draftGeneration: UUID(), referenceRevision: 0),
            acquisition: a.acquisition, completion: a.completion, recipient: a.recipient,
            inventoryRevision: 3, sourcePackageRevision: 0, sourceMembershipRevision: 0, liveCount: 2, countRevision: 1)
        let cohort = try SharedMediaOrdinaryHoldCohort([a, b]), bytes = try cohort.encoded()
        #expect(try SharedMediaOrdinaryHoldCohort.decode(bytes) == cohort)
        let accepted = try cohort.acceptances()
        #expect(accepted.count == 2 && accepted.values.allSatisfy { $0.liveCount == 4 && $0.countRevision == 2 && $0.inventoryRevision == 4 })
        try cohort.requireAcceptances(accepted)
        var partial = accepted; partial.removeValue(forKey: b.id)
        #expect(throws: (any Error).self) { try cohort.requireAcceptances(partial) }
        var wrongDelta = accepted; wrongDelta[a.id] = try acceptance(a)
        #expect(throws: (any Error).self) { try cohort.requireAcceptances(wrongDelta) }
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldCohort([a, a]) }
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldCohort([a, b, base]) }
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldCohort([a, fixture()]) }
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldCohort([]) }
    }

    private func fixture() throws -> SharedMediaOrdinaryHoldRequest {
        let owner = UUID(), inventory = UUID(), generation = UUID(), package = UUID(), draft = UUID(), asset = UUID(), assetGeneration = UUID(), reference = UUID()
        let acquisition = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: inventory, inventoryGeneration: generation,
            ownerID: owner, expectedInventoryRevision: 0, packageID: package, draftGeneration: draft, packageExpectation: .absent,
            assetID: asset, assetGeneration: assetGeneration, referenceID: reference, ordinal: 0, kind: .picker, writerEpoch: UUID(), maximumBytes: 32)
        let completion = try SharedMediaAcquisitionResult(request: acquisition, inventoryRevision: 2, packageRevision: 1,
            membershipRevision: 1, byteCount: 32, sha256: String(repeating: "a", count: 64), contentType: "public.jpeg",
            descriptor: .init(version: 1, file: "1:2:32:4:0:5:0", parent: "1:3", namespace: "1:4"))
        return try .init(id: UUID(), profile: .init(ownerID: owner, inventoryID: inventory, generation: generation,
            storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "b", count: 64), receiptDigest: String(repeating: "c", count: 64)),
            writerEpoch: UUID(), source: .init(ownerID: owner, packageID: package, referenceID: reference, assetID: asset,
                assetGeneration: assetGeneration, draftGeneration: draft, referenceRevision: 0), acquisition: acquisition,
            completion: completion, recipient: recipient(), inventoryRevision: 2, sourcePackageRevision: 1,
            sourceMembershipRevision: 1, liveCount: 1, countRevision: 0)
    }
    private func recipient() -> SharedMediaOrdinaryHoldRequest.Recipient {
        .init(scanID: UUID(), submissionGeneration: UUID(), eventID: UUID(), observationSHA256: String(repeating: "a", count: 64),
            preparationSHA256: String(repeating: "b", count: 64))
    }
    private func acceptance(_ request: SharedMediaOrdinaryHoldRequest) throws -> SharedMediaOrdinaryHoldAcceptance {
        try .init(request: request, inventoryRevision: request.inventoryRevision + 1,
            countRevision: request.countRevision + 1, liveCount: request.liveCount + 1)
    }
    private func row(_ request: SharedMediaOrdinaryHoldRequest) throws -> SharedMediaOrdinaryTransferRecord {
        let data = try request.encoded()
        return .init(id: request.id, inventoryID: request.profile.inventoryID, inventoryGeneration: request.profile.generation,
            ownerID: request.profile.ownerID, sourceAssetID: request.source.assetID, sourceReferenceID: request.source.referenceID,
            recipientScanID: request.recipient.scanID, submissionGeneration: request.recipient.submissionGeneration,
            writerEpoch: request.writerEpoch, requestData: data, requestSHA256: hash(data))
    }
    private func hash(_ data: Data) -> String { SharedMediaAcquisitionEncoding.digest(data) }
    private func mutation(_ data: Data, path: [String], value: Any) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if path.count == 2 {
            var child = try #require(json[path[0]] as? [String: Any]); child[path[1]] = value; json[path[0]] = child
        } else { json[path[0]] = value }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .fragmentsAllowed])
    }
}
