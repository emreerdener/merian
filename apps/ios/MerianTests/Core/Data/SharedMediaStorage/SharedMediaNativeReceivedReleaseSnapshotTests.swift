import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Received release funding measurement", .serialized)
@MainActor
struct SharedMediaNativeReceivedReleaseSnapshotTests {
    typealias Reader = SharedMediaNativeReceivedReleaseSnapshot
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    @Test(arguments: [1, 2])
    func measuresExactReplacementAcrossInventoryDigitBoundary(_ count: Int) async throws {
        let store = try await received(count: count)
        let c = store.context(), id = store.inventoryID
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        inventory.revision = count == 1 ? 99 : 999
        try c.save()
        let before = try Reader.read(packageID: store.packageID, inventoryID: id, releaseID: UUID(), context: c)
        #expect(!c.hasChanges)
        #expect(before.components.progress.plan.preHeader == before.header)
        #expect(before.components.progress.plan.preHeader.inventory.revision > before.components.received.preHeader.inventory.revision)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: store.ownerID, format: .appV2)
        #expect(try before.funding.before.charged == budget.metadataByPackage[store.packageID])
        #expect(before.funding.before == budget.receivedLiabilityByPackage[store.packageID])
        #expect(before.components.ownedOriginals.count == count)
        try before.funding.requireExistingFunding()
        let package = SharedMediaNativeAppMetadataFacts.Package(try store.package(in: c))
        let packageID = store.packageID
        let member = SharedMediaNativeAppMetadataFacts.Member(try Fixture.one(c,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })))
        let rawPackage = try store.package(in: c)
        let rawMember = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        for predicted in before.components.pairs {
            let raw = try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory,
                package: rawPackage, member: rawMember, pairID: predicted.intent().pairID)
            #expect(raw.plan.inventoryRevision + 1 == predicted.plan.inventoryRevision)
            #expect(try SharedMediaNativeDraftEnvelope.bytes(raw).count + 1 == SharedMediaNativeDraftEnvelope.bytes(predicted).count)
        }
        let pairRowsBefore = try pairRowScalars(before.components.progress.plan.targets.map(\.pairID), context: c)
        // Test-only saved-state construction. No production start writer exists.
        let live = try Fixture(store: store, prepared: before.components.prepared,
            received: before.components.received, plan: before.components.progress.plan)
        try live.save(c)
        let after = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: store.packageID,
            inventoryID: id, context: store.context())
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(after)
        #expect(after.release.state.package == package && after.release.state.member == member)
        #expect(try pairRowScalars(before.components.progress.plan.targets.map(\.pairID), context: store.context()) == pairRowsBefore)
        #expect(after.inventoryRevision == before.header.inventory.revision + 1)
        #expect(try after.pairs.map { try SharedMediaNativeDraftEnvelope.bytes($0) } ==
            before.components.pairs.map { try SharedMediaNativeDraftEnvelope.bytes($0) })
        #expect(projection == before.funding.projection)
        #expect(before.funding.after.current == projection.currentIdentityExcludedBytes)
        #expect(try before.funding.after.charged == projection.maximumIdentityExcludedBytes)
    }

    @Test func preservesForeignPhysicalOwnershipAndRejectsUnderfundingWithoutWrites() async throws {
        let store = try await received(count: 1, foreign: true)
        let c = store.context()
        let value = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID, releaseID: UUID(), context: c)
        #expect(value.components.ownedOriginals.isEmpty)
        let origin = try #require(value.components.targetOrigins.first)
        guard case .present(let physicalOwner) = origin.location else { Issue.record("Expected physical origin"); return }
        #expect(physicalOwner != store.packageID)
        #expect(value.funding.projection.charges.allSatisfy { $0.originReceiptBytes == 0 && $0.originIdentityBytes == 0 })
        try value.funding.requireExistingFunding()
        let maximum = try value.funding.after.charged
        // Arithmetic feasibility rejects total underfunding, but never requires
        // reserve monotonicity or a new disk-availability query.
        let exact = try Reader.Funding(before: .init(current: maximum, reserved: 0), projection: value.funding.projection)
        try exact.requireExistingFunding()
        #expect(exact.after.reserved > exact.before.reserved)
        let short = try Reader.Funding(before: .init(current: maximum - 1, reserved: 0), projection: value.funding.projection)
        #expect(throws: SharedMediaStorageFailure.capacity) { try short.requireExistingFunding() }
        #expect(throws: (any Error).self) {
            _ = try Reader.Funding(before: .init(current: Int64.max, reserved: 1), projection: value.funding.projection)
        }
        #expect(!c.hasChanges)
        let again = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
            releaseID: value.components.progress.plan.releaseID, context: store.context())
        #expect(again.slot == value.slot && again.header == value.header)
        #expect(again.funding.before == value.funding.before && again.funding.after == value.funding.after)
    }

    @Test func rejectsPersistedPairReceiptAndFrozenPackageCorruption() async throws {
        let store = try await received(count: 1)
        let initial = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
            releaseID: UUID(), context: store.context())
        let target = initial.components.progress.plan.targets[0]
        for fault in ["package", "pair", "receipt"] {
            let c = store.context(), pairID = target.pairID, receiptID = target.acquisitionID
            let package = try store.package(in: c)
            let pair = try Fixture.one(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
            let receipt = try Fixture.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
            let oldRevision = package.revision, oldPhase = pair.phaseRaw, oldOwner = receipt.packageID
            switch fault {
            case "package": package.revision += 1
            case "pair": pair.phaseRaw = "writing"
            default: receipt.packageID = UUID()
            }
            try c.save()
            let read = store.context()
            #expect(throws: (any Error).self) {
                _ = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
                    releaseID: initial.components.progress.plan.releaseID, context: read)
            }
            #expect(!read.hasChanges)
            package.revision = oldRevision; pair.phaseRaw = oldPhase; receipt.packageID = oldOwner
            try c.save()
        }
        let c = store.context(), id = store.inventoryID
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        inventory.revision = Int64.max - 1
        try c.save()
        #expect(throws: (any Error).self) {
            _ = try Reader.read(packageID: store.packageID, inventoryID: id, releaseID: UUID(), context: store.context())
        }
    }

    private func pairRowScalars(_ ids: [UUID], context: ModelContext) throws -> [[String]] {
        try ids.map { id in
            let row = try Fixture.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
            return [String(row.expectedInventoryRevision), String(row.expectedPackageRevision), row.nonce.uuidString,
                row.phaseRaw, String(describing: row.publishedRevision)]
        }
    }

    private func received(count: Int, foreign: Bool = false) async throws -> Store {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count,
            staged: true, foreignOriginal: foreign)
        _ = try await owner.receiveAppPrepared(Intent.Prepared(request))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        return store
    }
}
