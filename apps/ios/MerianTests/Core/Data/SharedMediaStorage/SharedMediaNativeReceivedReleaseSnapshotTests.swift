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

    @Test(arguments: [false, true])
    func rejectsPersistedPairReceiptAndFrozenPackageCorruption(_ staged: Bool) async throws {
        let store = try await received(count: 1)
        let initial = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
            releaseID: UUID(), context: store.context())
        let target = initial.components.progress.plan.targets[0]
        if staged {
            let c = store.context(), inventoryID = store.inventoryID
            let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let request = try SharedMediaNativeReleaseStartRequest(prepared: initial.components.prepared,
                received: initial.components.received, stagePreHeader: initial.header,
                releaseID: initial.components.progress.plan.releaseID)
            let encoding = try request.encoding()
            let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
            row.releaseStartData = encoding.data; row.releaseStartSHA256 = encoding.sha256
            inventory.revision += 1; try c.save()
        }
        func read(_ c: ModelContext) throws {
            if staged {
                let inventoryID = store.inventoryID
                let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
                let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
                let origin = try SharedMediaNativeStagedReleaseOrigin.read(.init(row), inventory: inventory, context: c)
                _ = try Reader.readStaged(origin, context: c)
            } else {
                _ = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
                    releaseID: initial.components.progress.plan.releaseID, context: c)
            }
        }
        try read(store.context())
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
            let fresh = store.context()
            #expect(throws: (any Error).self) { try read(fresh) }
            #expect(!fresh.hasChanges)
            package.revision = oldRevision; pair.phaseRaw = oldPhase; receipt.packageID = oldOwner
            try c.save()
        }
        let c = store.context(), id = store.inventoryID
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        inventory.revision = Int64.max - 1
        try c.save()
        #expect(throws: (any Error).self) {
            try read(store.context())
        }
    }

    @Test(arguments: [98, 99, 998, 999], [false, true])
    func stagedFundingPreservesHistoricalAccountingAndCurrentReleaseSizing(_ stageRevision: Int, _ foreign: Bool) async throws {
        let store = try await received(count: foreign ? 1 : 2, foreign: foreign)
        let c = store.context(), inventoryID = store.inventoryID
        let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        inventory.revision = Int64(stageRevision); try c.save()
        let ordinary = try Reader.read(packageID: store.packageID, inventoryID: inventoryID, releaseID: UUID(), context: c)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: store.ownerID, format: .appV2)
        let request = try SharedMediaNativeReleaseStartRequest(prepared: ordinary.components.prepared,
            received: ordinary.components.received, stagePreHeader: ordinary.header,
            releaseID: ordinary.components.progress.plan.releaseID)
        let encoding = try request.encoding()
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: c))
        let original = SharedMediaNativeReceivingIntentGraph.Row(row)
        // Test-only persisted staging shape; no writer or accounting dispatch.
        row.releaseStartData = encoding.data; row.releaseStartSHA256 = encoding.sha256
        inventory.revision += 1; try c.save()
        for advance in [Int64(0), Int64(1000)] {
            inventory.revision += advance; try c.save()
            let fresh = store.context()
            let inv = try Fixture.one(fresh, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let saved = try #require(try SharedMediaNativeReceivingPhaseGraph.row(store.packageID, in: fresh))
            let origin = try SharedMediaNativeStagedReleaseOrigin.read(.init(saved), inventory: inv, context: fresh)
            let measured = try Reader.readStaged(origin, context: fresh)
            #expect(measured.historical.liability == ordinary.funding.before)
            #expect(measured.historical.baseBytes == budget.baseMetadataByPackage[store.packageID])
            #expect(measured.historical.originIDs.count == (foreign ? 0 : 2))
            #expect(measured.funding.staged.current == ordinary.funding.before.current + encoding.metadataBytes)
            #expect(try measured.funding.staged.charged == ordinary.funding.before.charged)
            #expect(measured.components.progress.plan.preHeader == origin.header)
            #expect(measured.components.pairs.allSatisfy { $0.plan.inventoryRevision == inv.revision + 1 })
            #expect(origin.row.preparedData == original.preparedData && origin.row.resultData == original.resultData)
            #expect(!fresh.hasChanges)
            #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: fresh, inventory: inv,
                    ownerID: store.ownerID, format: .appV2)
            }
            // Compare both adapters at the same current revision. Removing and
            // restoring the sidecar is fixture construction, never product repair.
            saved.releaseStartData = nil; saved.releaseStartSHA256 = nil; try fresh.save()
            let currentOrdinary = try Reader.read(packageID: store.packageID, inventoryID: inventoryID,
                releaseID: request.releaseID, context: fresh)
            #expect(currentOrdinary.funding.projection == measured.funding.release.projection)
            #expect(currentOrdinary.funding.before == measured.funding.historical)
            let currentBudget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: fresh, inventory: inv,
                ownerID: store.ownerID, format: .appV2)
            #expect(currentBudget.totals == budget.totals)
            #expect(currentBudget.metadataByPackage == budget.metadataByPackage)
            #expect(currentBudget.baseMetadataByPackage == budget.baseMetadataByPackage)
            #expect(currentBudget.receivedLiabilityByPackage == budget.receivedLiabilityByPackage)
            let originalIdentity = try #require(budget.originalIdentity)
            let currentIdentity = try #require(currentBudget.originalIdentity)
            #expect(currentIdentity == .init(inventoryID: originalIdentity.inventoryID, generation: originalIdentity.generation,
                revision: inv.revision, entries: originalIdentity.entries, retainedTargets: originalIdentity.retainedTargets))
            saved.releaseStartData = encoding.data; saved.releaseStartSHA256 = encoding.sha256; try fresh.save()
        }
    }

    @Test func stagedFundingRequiresBothReplacementBoundsWithoutNewCapacity() async throws {
        let store = try await received(count: 1)
        let value = try Reader.read(packageID: store.packageID, inventoryID: store.inventoryID,
            releaseID: UUID(), context: store.context())
        let projection = value.funding.projection, historical = value.funding.before
        let exactStage = try Reader.StagedFunding(historical: historical,
            sidecarBytes: historical.reserved, projection: projection)
        #expect(exactStage.staged.reserved == 0)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try Reader.StagedFunding(historical: historical, sidecarBytes: historical.reserved + 1, projection: projection)
        }
        let maximum = projection.maximumIdentityExcludedBytes
        let exactRelease = try Reader.StagedFunding(historical: .init(current: 0, reserved: maximum),
            sidecarBytes: 1, projection: projection)
        #expect(try exactRelease.release.after.charged == exactRelease.historical.charged)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try Reader.StagedFunding(historical: .init(current: 0, reserved: maximum - 1), sidecarBytes: 1, projection: projection)
        }
        #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try Reader.StagedFunding(historical: .init(current: 0, reserved: PhotoPreparationPolicy.metadata + 1),
                sidecarBytes: 1, projection: projection)
        }
        for invalid in [Int64(-1), Int64.max] {
            #expect(throws: (any Error).self) {
                _ = try Reader.StagedFunding(historical: historical, sidecarBytes: invalid, projection: projection)
            }
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
