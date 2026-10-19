import Foundation
import SwiftData
import Testing
@testable import Merian

/// Synthetic receiving rows exercise read-only facts only. These fixtures do
/// not claim production atomic admission, transfer, cleanup or executor coverage.
@Suite("Native receiving frozen facts", .serialized)
@MainActor
struct SharedMediaNativeConsumerGraphTests {
    private typealias Harness = SharedMediaNativePreparationTests.Harness
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test func pendingAndRetainedReadbackPreserveExactBytesWithoutSyntheticMembership() async throws {
        let (h, binding) = try await fixture(count: 2)
        let pending = try read(h, binding)
        try promote(h, binding)
        #expect(try read(h, binding) == pending)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(!context.hasChanges)
        // The qualification opener remains closed to receiving rows.
        await #expect(throws: (any Error).self) { _ = try await h.open() }
    }

    @Test func scanToAnalysisTransferDoesNotRebindFrozenPackage() async throws {
        let (h, binding) = try await fixture()
        try promote(h, binding)
        let before = try read(h, binding), context = ModelContext(h.container)
        context.autosaveEnabled = false
        let row = try consumer(context, binding)
        row.kindRaw = "analysis"; row.consumerID = UUID().uuidString.lowercased(); row.revision += 1
        try context.save()
        #expect(try read(h, binding) == before)
    }

    @Test(arguments: [-1, 1, 2])
    func retainedRevisionMustBeExactlyOnePromotionBeyondFreeze(delta: Int64) async throws {
        let (h, binding) = try await fixture()
        try promote(h, binding)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        package.revision += delta; try context.save()
        #expect(throws: (any Error).self) { try read(h, binding) }
    }

    @Test(arguments: ["owner", "execution", "generation", "digest", "freeze", "kind", "currentID", "retiring", "contract"])
    func mismatchedReceivingIdentityFailsClosed(_ fault: String) async throws {
        let (h, binding) = try await fixture(), context = ModelContext(h.container)
        context.autosaveEnabled = false
        let row = try consumer(context, binding)
        switch fault {
        case "owner": row.ownerID = UUID()
        case "execution": row.executionKindRaw = "reanalysisV1"
        case "generation": row.inferenceGeneration = UUID()
        case "digest": row.cohortSHA256 = String(repeating: "0", count: 64)
        case "freeze": row.frozenPackageRevision += 1
        case "kind": row.kindRaw = "legacy"
        case "currentID": row.consumerID = UUID().uuidString.lowercased()
        case "retiring": row.lifecycleRaw = "retiring"; row.retirementID = UUID()
        default: row.contractVersion = PhotoPreparationPolicy.contract
        }
        try context.save()
        #expect(throws: (any Error).self) { try read(h, binding) }
    }

    @Test(arguments: ["counter", "edge", "extraReference", "extraPair", "missingOutput", "originalHash", "memberRevision", "memberBytes"])
    func currentGraphCannotBeReplacedByHistoricalMembership(_ fault: String) async throws {
        let (h, binding) = try await fixture(), context = ModelContext(h.container)
        context.autosaveEnabled = false
        let ref = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>()).first(where: { $0.roleRaw == "original" }))
        let assetID = ref.assetID
        switch fault {
        case "counter":
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })).first)
            row.liveCount += 1
        case "edge":
            let refID = ref.id
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == refID })).first)
            context.delete(row)
        case "extraReference":
            let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>()).first(where: { $0.roleRaw == "display" }))
            row.roleRaw = "original"
        case "extraPair":
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>()).first)
            row.aiWorkID = UUID()
        case "missingOutput":
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>()).first)
            context.delete(row)
        case "originalHash":
            let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).first)
            row.sha256 = String(repeating: "0", count: 64)
        case "memberRevision":
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
            row.revision += 1
        default:
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
            row.membersData = try SharedMediaMembership(groups: []).encoded()
        }
        try context.save()
        #expect(throws: (any Error).self) { try read(h, binding) }
    }

    @Test func retainedMembershipRowIsRejectedRatherThanUsedForRecovery() async throws {
        let (h, binding) = try await fixture(), context = ModelContext(h.container)
        context.autosaveEnabled = false
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        package.accountingTierRaw = "retained"; package.revision += 1
        let row = try consumer(context, binding)
        row.kindRaw = "localScan"; row.consumerID = row.observationID
        try context.save()
        #expect(throws: (any Error).self) { try read(h, binding) }
    }

    @Test func immutableFactsDoNotClaimPhysicalAvailability() async throws {
        let (h, binding) = try await fixture(), before = try read(h, binding)
        let freeze = try SharedMediaNativeFreezeCommit.decode(before.freeze.bytes)
        let cohort = try SharedMediaNativeFrozenCohort.decode(freeze.cohort.bytes)
        let original = try SharedMediaNativeDerivativeIntent.decode(cohort.entries[0].intent.bytes).preparation.original
        try FileManager.default.removeItem(at: h.file(original.reference))
        #expect(try read(h, binding) == before)
        // Only the later typed executor/file owner may authorize a new use.
        #expect(!FileManager.default.fileExists(atPath: h.file(original.reference).path))
    }

    @Test func codecAndDigestBindExecutionAndExactMembership() async throws {
        let (h, binding) = try await fixture(), value = try read(h, binding)
        #expect(try SharedMediaNativeConsumerCohort.decode(value.encoded()) == value)
        let changed = SharedMediaNativeConsumerCohort(format: .receiving, bindingID: UUID(),
            originQueueID: value.originQueueID, observationID: value.observationID,
            executionKind: value.executionKind, inferenceGeneration: value.inferenceGeneration,
            freeze: value.freeze, membership: value.membership)
        #expect(try changed.digest() != value.digest())
        let invalid = SharedMediaNativeConsumerCohort(format: .receiving, bindingID: value.bindingID,
            originQueueID: value.originQueueID, observationID: value.observationID,
            executionKind: value.executionKind, inferenceGeneration: value.inferenceGeneration,
            freeze: value.freeze, membership: try SharedMediaMembership(groups: []).encoded())
        #expect(throws: (any Error).self) { try invalid.encoded() }
        #expect(throws: (any Error).self) { try SharedMediaConsumerCohort.decode(value.encoded()) }
        #expect(throws: (any Error).self) { try SharedMediaNativeConsumerCohort.decode(value.encoded() + Data([32])) }
    }

    private func fixture(count: Int = 1) async throws -> (Harness, UUID) {
        let h = try Harness(), owner = try await h.open()
        var pairs: [UUID] = []
        for ordinal in 0..<count {
            let original = try await h.acquire(owner, ordinal: Int64(ordinal))
            let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
            pairs.append(try ready.intent().pairID)
        }
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: pairs, operationID: UUID())
        _ = try await owner.freeze(request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let id = UUID(), queue = UUID().uuidString.lowercased(), observation = UUID().uuidString.lowercased(), generation = UUID()
        let payload = SharedMediaNativeConsumerCohort(format: .receiving, bindingID: id,
            originQueueID: queue, observationID: observation, executionKind: "ordinaryV1", inferenceGeneration: generation,
            freeze: .init(bytes: try request.commit.encoded()), membership: request.membership)
        let row = SharedMediaConsumerRecord(id: id, kindRaw: "queue", consumerID: queue, originQueueID: queue,
            observationID: observation, inventoryID: h.inventoryID, inventoryGeneration: request.commit.inventoryGeneration,
            ownerID: h.ownerID, packageID: h.packageID, draftGeneration: h.draft,
            frozenPackageRevision: try request.commit.packageRevision, contractVersion: SharedMediaNativeConsumerGraph.contract,
            digestVersion: 1, cohortSHA256: try payload.digest(), executionKindRaw: "ordinaryV1", inferenceGeneration: generation)
        row.cohortData = try payload.encoded(); context.insert(row); try context.save()
        return (h, id)
    }

    private func consumer(_ context: ModelContext, _ id: UUID) throws -> SharedMediaConsumerRecord {
        try #require(try SharedMediaConsumerLookup.one(context, id: id))
    }
    private func read(_ h: Harness, _ id: UUID) throws -> SharedMediaNativeConsumerCohort {
        let context = ModelContext(h.container); context.autosaveEnabled = false
        return try SharedMediaNativeConsumerGraph.validate(consumer(context, id), context: context)
    }
    private func promote(_ h: Harness, _ id: UUID) throws {
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try consumer(context, id)
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
        package.accountingTierRaw = "retained"; package.revision += 1
        row.kindRaw = "localScan"; row.consumerID = row.observationID; row.revision += 1
        context.delete(member); try context.save()
    }
}
