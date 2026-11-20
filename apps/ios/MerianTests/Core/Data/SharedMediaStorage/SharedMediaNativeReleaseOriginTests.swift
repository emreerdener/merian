import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Read-only held-release origin reconstruction", .serialized)
@MainActor
struct SharedMediaNativeReleaseOriginTests {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Origin = SharedMediaNativeReleaseOrigin
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test(arguments: [1, 2])
    func canonicalOriginsAndRestagedPredecessorsRemainExact(_ count: Int) async throws {
        let fixture = try await Fixture.load(count: count).freshP2()
        let first = try Intent.Prepared(fixture.request)
        let ids = try acquisitionIDs(fixture, first)
        for revision: Int64 in [0, 2] {
            let prepared = revision == 0 ? first : try Fixture.copy(first, changes: [
                "intentRevision": revision, "restagedFromSHA256": String(repeating: "a", count: 64)])
            let transaction = try prepared.descriptorForTransaction(header: fixture.request.header)
            let received = try Intent.Received(prepared: prepared, request: transaction)
            let plan = try Values.Plan(prepared: prepared, received: received,
                header: SharedMediaNativeAppMetadataFacts.successor(transaction.header), releaseID: UUID(), acquisitionIDs: ids)
            let envelope = try transaction.frozenPackage().envelope
            let restored = try Origin.reconstruct(plan, frozenEnvelope: envelope,
                consumer: transaction.cohort, timestamp: transaction.timestamp)
            #expect(try restored.prepared.encoded() == prepared.encoded())
            #expect(try restored.received.encoded(prepared: restored.prepared) == received.encoded(prepared: prepared))
            #expect(try Intent.canonicalRequest(restored.transaction) == Intent.canonicalRequest(transaction))
            #expect(throws: (any Error).self) {
                _ = try Origin.reconstruct(plan, frozenEnvelope: envelope,
                    consumer: transaction.cohort, timestamp: transaction.timestamp.addingTimeInterval(1))
            }
            #expect(throws: (any Error).self) {
                _ = try Origin.reconstruct(plan, frozenEnvelope: prepared.package.envelope,
                    consumer: transaction.cohort, timestamp: transaction.timestamp)
            }
            for field in ["preparedSHA256", "receivedSHA256", "requestSHA256", "cohortSHA256"] {
                let changed = try Fixture.copy(plan, changes: [field: String(repeating: "b", count: 64)])
                #expect(throws: (any Error).self) {
                    _ = try Origin.reconstruct(changed, frozenEnvelope: envelope,
                        consumer: transaction.cohort, timestamp: transaction.timestamp)
                }
            }
            let changedEvent = try Fixture.copy(plan, changes: ["eventID": UUID().uuidString])
            #expect(throws: (any Error).self) {
                _ = try Origin.reconstruct(changedEvent, frozenEnvelope: envelope,
                    consumer: transaction.cohort, timestamp: transaction.timestamp)
            }
            let changedPackage = try Fixture.copy(plan.package, changes: ["allocated": plan.package.allocated + 1])
            let changedMember = try Fixture.copy(plan.member, changes: ["revision": plan.member.revision + 1])
            for changes: [String: Any] in [["package": try Fixture.object(changedPackage)], ["member": try Fixture.object(changedMember)]] {
                let changed = try Fixture.copy(plan, changes: changes)
                #expect(throws: (any Error).self) {
                    _ = try Origin.reconstruct(changed, frozenEnvelope: envelope,
                        consumer: transaction.cohort, timestamp: transaction.timestamp)
                }
            }
            // Acquisition IDs are not part of Prepared/Received. This leaf
            // deliberately cannot prove their current ledger ownership.
            let otherPlan = try Values.Plan(prepared: prepared, received: received, header: plan.preHeader,
                releaseID: plan.releaseID, acquisitionIDs: ids.map { _ in UUID() })
            _ = try Origin.reconstruct(otherPlan, frozenEnvelope: envelope,
                consumer: transaction.cohort, timestamp: transaction.timestamp)
            let header = try Fixture.copy(plan.preHeader, changes: ["bootstrapRevision": plan.preHeader.bootstrapRevision + 1])
            let changedHeader = try Fixture.copy(plan, changes: ["preHeader": Fixture.object(header)])
            #expect(throws: (any Error).self) {
                _ = try Origin.reconstruct(changedHeader, frozenEnvelope: envelope,
                    consumer: transaction.cohort, timestamp: transaction.timestamp)
            }
            let binding = try #require(transaction.cohort.intentBinding)
            let changedBinding = try Fixture.copy(binding, changes: ["restagedFromSHA256": String(repeating: "c", count: 64)])
            let changedConsumer = try Fixture.copy(transaction.cohort, changes: ["intentBinding": Fixture.object(changedBinding)])
            #expect(throws: (any Error).self) {
                _ = try Origin.reconstruct(plan, frozenEnvelope: envelope,
                    consumer: changedConsumer, timestamp: transaction.timestamp)
            }
        }
    }

    @Test(arguments: [1, 2])
    func persistedQuartetIsRequiredWhileCurrentMembershipIsAuditedSeparately(_ count: Int) async throws {
        let (store, owner, initial) = try await SharedMediaNativeAppReceivingTests().fixture(count: count, staged: true)
        let prepared = try Intent.Prepared(initial)
        _ = try await owner.receiveAppPrepared(prepared)
        let context = store.context()
        let slot = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        guard case .received(_, let received, let transaction) = try SharedMediaNativeReceivingSlot.decode(.init(slot), profile: prepared.profile) else {
            Issue.record("Expected received P2 fixture"); return
        }
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let ids = try cohort.entries.map { entry in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let assetID = intent.preparation.original.reference.assetID
            let row = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, _) = try SharedMediaAcquisitionReceipt.read(row) else {
                throw SharedMediaStorageFailure.conflict
            }
            return request.operationID
        }
        let scope = SharedMediaNativeScopeIdentity(inventoryID: prepared.profile.inventoryID,
            generation: prepared.profile.generation, ownerID: prepared.profile.ownerID,
            storeIdentity: prepared.profile.storeIdentity, rootBinding: try prepared.profile.rootIdentity)
        let header = try SharedMediaNativeAppEligibility.snapshot(context: store.context(), scope: scope)
        let plan = try Values.Plan(prepared: prepared, received: received, header: header, releaseID: UUID(), acquisitionIDs: ids)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = store.context()
        let witness = try Origin.read(plan, in: cold)
        #expect(try Intent.canonicalRequest(witness.snapshot.transaction) == Intent.canonicalRequest(transaction))
        #expect(!cold.hasChanges)

        // Controlled corruptions prove this leaf rejects execution changes. It
        // never repairs, saves, or invokes a provider. Roll each fault back.
        for field in ["queue", "job", "event", "consumer", "missing"] {
            let c = store.context(), rows = try Origin.read(plan, in: c).rows
            switch field {
            case "queue": rows.queue.queueAttemptCount = 1
            case "job": rows.job.attemptCount = 1
            case "event": rows.event.metadataJSON = "changed"
            case "consumer": rows.consumer.revision += 1
            default: c.delete(rows.event)
            }
            #expect(throws: (any Error).self) { _ = try Origin.read(plan, in: c) }
            c.rollback()
            _ = try Origin.read(plan, in: store.context())
        }

        // Synthetic partial cleanup proves separation of origin and current
        // state checks only; it is NOT an accepted release or recovery fixture.
        let partial = store.context(), package = try store.package(in: partial), packageID = package.id
        let member = try SharedMediaNativePairPlanGraph.one(partial,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        package.revision += 1; package.allocatedByteCount = 0
        member.revision += 1; member.membersData = try SharedMediaMembership(groups: []).encoded()
        try partial.save()
        let reopened = store.context(), reconstructed = try Origin.read(plan, in: reopened)
        #expect(try reconstructed.snapshot.prepared.encoded() == prepared.encoded())
        #expect(!reopened.hasChanges)
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: reopened)
        }
        let broken = store.context(), rows = try Origin.read(plan, in: broken).rows
        rows.queue.timestamp = rows.queue.timestamp.addingTimeInterval(1)
        try broken.save()
        #expect(throws: (any Error).self) { _ = try Origin.read(plan, in: store.context()) }
    }

    private func acquisitionIDs(_ fixture: Fixture, _ prepared: Intent.Prepared) throws -> [UUID] {
        try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes).entries.map { entry in
            let assetID = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference.assetID
            return try #require(fixture.receipts.first { $0.0.assetID == assetID }).0.operationID
        }
    }
}
