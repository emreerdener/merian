import Foundation
import SwiftData
import Testing
@testable import Merian

enum NativePendingCleanupFault: Error { case injected }

@MainActor
struct NativePendingCleanupHarness {
    let base: URL, container: ModelContainer
    let inventoryID = UUID(), ownerID = UUID(), packageID = UUID(), draft = UUID()
    let runtime = AuthRuntimeState(), bytes = PhotoPreparationTestHarness.image()
    init() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-pending-" + UUID().uuidString)
        print("NATIVE_PENDING_FIXTURE " + base.path)
        for name in ["authority", "photo", "inbox", "database"] { try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true) }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: base.appendingPathComponent("database/ledger.store"), cloudKitDatabase: .none)])
    }
    func open() async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.qualification(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime), drain: .init())
        _ = try await owner.open(container: container, authorityRoot: base.appendingPathComponent("authority"), photoRoot: base.appendingPathComponent("photo"), inboxRoot: base.appendingPathComponent("inbox"), inventoryID: inventoryID)
        return owner
    }
    func request(_ owner: SharedMediaNativeOriginalOwner, ordinal: Int64 = 0) async throws -> SharedMediaAcquisitionIntent {
        try await owner.prepareOriginal(packageID: packageID, draftGeneration: draft, ordinal: ordinal, kind: .picker)
    }
    func held(_ owner: SharedMediaNativeOriginalOwner, final: Bool = false, ordinal: Int64 = 0) async throws -> SharedMediaAcquisitionIntent {
        let request = try await request(owner, ordinal: ordinal)
        if final { try owner.setAcquisitionFault { if $0 == .beforeCompletionSave { throw NativePendingCleanupFault.injected } } }
        let bytes = bytes
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) {
            if final { return bytes }; throw NativePendingCleanupFault.injected
        } }
        try owner.setAcquisitionFault(nil)
        #expect(try receipt(request).phaseRaw == "held")
        return request
    }
    func file(_ request: SharedMediaAcquisitionIntent, partial: Bool = false) -> URL {
        base.appendingPathComponent("photo/PhotoPreparation/" + (partial ? request.partialToken : request.finalToken))
    }
    func seedFile(_ request: SharedMediaAcquisitionIntent, kind: String) throws {
        guard kind != "absent" else { return }
        let url = file(request, partial: kind != "final")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (kind == "zero" ? Data() : bytes).write(to: url)
    }
    func rows<T: PersistentModel>(_ type: T.Type) throws -> Int { try ModelContext(container).fetchCount(FetchDescriptor<T>()) }
    func receipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceiptRecord {
        let id = request.operationID
        return try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
    }
    func work(_ request: SharedMediaAcquisitionIntent) throws -> PhotoPreparationLease {
        let id = request.operationID
        return try #require(ModelContext(container).fetch(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })).first)
    }
    func package() throws -> PhotoPreparationRecord { try #require(ModelContext(container).fetch(FetchDescriptor<PhotoPreparationRecord>()).first) }
    func allocation(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAllocationRecord {
        let id = request.assetID
        return try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id })).first)
    }
    func makeReserved(_ request: SharedMediaAcquisitionIntent) throws {
        let context = ModelContext(container), id = request.operationID, aid = request.assetID
        let row = try #require(context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
        row.phaseRaw = "reserved"; row.revision = 0
        try #require(context.fetch(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })).first).writerStateRaw = "open"
        try #require(context.fetch(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })).first).stateRaw = "open"
        try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == aid })).first).stateRaw = "p1Reserved"
        try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first).phaseRaw = "acquiring"
        try context.save()
    }
    func seedSecond(_ first: SharedMediaAcquisitionIntent, held: Bool) throws -> SharedMediaAcquisitionIntent {
        let context = ModelContext(container)
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
        let request = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: inventoryID, inventoryGeneration: inventory.generation,
            ownerID: ownerID, expectedInventoryRevision: 0, packageID: packageID, draftGeneration: draft, packageExpectation: .absent,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: 1, kind: .picker, writerEpoch: UUID(), maximumBytes: first.maximumBytes)
        let receipt = SharedMediaAcquisitionReceiptRecord(operationID: request.operationID, inventoryID: inventoryID,
            inventoryGeneration: inventory.generation, ownerID: ownerID, requestFingerprint: try request.fingerprint(), packageID: packageID, assetID: request.assetID, requestData: try request.encoded())
        if held { receipt.phaseRaw = "held"; receipt.revision = 1 }
        context.insert(receipt)
        context.insert(SharedMediaAllocationRecord(id: request.assetID, inventoryID: inventoryID, accountID: ownerID, packageID: packageID,
            namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: request.finalToken, poolRaw: "durable", stateRaw: held ? "p1Held" : "p1Reserved", materializedBytes: 0, reservedBytes: request.maximumBytes, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: request.operationID, allocationID: request.assetID, processEpoch: request.writerEpoch, purposeRaw: "p1AcquireV1", stateRaw: held ? "unknown" : "open"))
        context.insert(PhotoPreparationLease(id: request.operationID, packageID: packageID, assetID: request.assetID, ownerID: ownerID, processEpoch: request.writerEpoch,
            purposeRaw: "acquire", partialFileToken: request.partialToken, finalFileToken: request.finalToken, reservedByteCount: request.maximumBytes,
            allocatedByteCount: 0, writerStateRaw: held ? "unknown" : "open", terminalProof: nil))
        inventory.revision += 2; package.revision += 2
        member.membersData = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: packageID).encoded(); member.revision += 1
        try context.save()
        return request
    }
    func corrupt(_ request: SharedMediaAcquisitionIntent, field: String) throws {
        let context = ModelContext(container), id = request.operationID, aid = request.assetID
        switch field {
        case "work": try #require(context.fetch(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })).first).writerStateRaw = "unknown"
        case "lease": try #require(context.fetch(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })).first).stateRaw = "unknown"
        case "allocation": try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == aid })).first).stateRaw = "p1Held"
        default: try #require(context.fetch(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })).first).terminalProof = nil
        }
        try context.save()
    }
    func metadataCharge() throws -> Int64 {
        let context = ModelContext(container), inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        return try #require(SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory).metadataByPackage[packageID])
    }
    func fillMetadata(referenceID: UUID) throws -> Data {
        let context = ModelContext(container), package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        func envelope(_ size: Int) throws -> Data {
            try PhotoPreparationPolicy.encodeDraft(contexts: [.init(freeText: "retained synthetic detail")], presentation: [.init(
                referenceID: referenceID, addedAt: Date(timeIntervalSince1970: 0), isFromGallery: true,
                cropQuarterTurns: 1, cropScale: 1, cropOffsetX: 0, cropOffsetY: 0, focus: nil,
                latitude: nil, longitude: nil, locationName: String(repeating: "x", count: size),
                weatherCondition: nil, weatherTemperature: nil, captureDate: nil)])
        }
        let empty = try envelope(0), existing = package.supportingContextData.count
        let fill = Int(PhotoPreparationPolicy.metadata - (try metadataCharge())) + existing - empty.count
        guard fill >= 0 else { throw NativePendingCleanupFault.injected }
        package.supportingContextData = try envelope(fill); package.revision += 1
        try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
        try context.save(); return package.supportingContextData
    }
    func advancePackage() throws {
        let context = ModelContext(container)
        try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first).revision += 1
        try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
        try context.save()
    }
    func audit() throws {
        let context = ModelContext(container)
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
    }
}

actor NativePendingLoaderGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false, finished = false, released = false
    func enter() async { started = true; if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func finish() { finished = true }
    func status() -> (Bool, Bool) { (started, finished) }
}
