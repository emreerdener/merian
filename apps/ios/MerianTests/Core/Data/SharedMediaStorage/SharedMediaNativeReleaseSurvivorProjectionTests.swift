import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Held-release survivor metadata bounds", .serialized)
@MainActor
struct SharedMediaNativeReleaseSurvivorProjectionTests {
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Reader = SharedMediaNativeReleaseMetadataSnapshot
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection

    @Test(arguments: [1, 2])
    func boundsEveryPersistedPhysicalStageWithoutReconstructingDeletedPairs(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        var previous: [Projection.Projection] = []
        func check() throws -> Reader.Snapshot {
            let c = f.store.context()
            let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: c)
            let result = try Projection.maximum(snapshot)
            #expect(!c.hasChanges)
            #expect(result.currentBytes == (try snapshot.currentSerializedBytes))
            #expect(result.maximumBytes >= result.currentBytes && result.futureGrowthBytes >= 0)
            try result.requireMetadataCapacity()
            #expect(result.maximumPackagePayloadBytes <= PhotoPreparationPolicy.metadata)
            for old in previous { #expect(old.maximumBytes >= result.currentBytes) }
            for charge in result.charges { #expect(try charge.total <= result.maximumBytes) }
            previous.append(result)
            return snapshot
        }
        let initial = try check(), initialResult = try Projection.maximum(initial)
        #expect(initialResult.charges.filter { !$0.terminal }.count == (count == 1 ? 6 : 36))
        #expect(initialResult.charges.filter(\.terminal).count == (count == 1 ? 2 : 4))
        let slot = try SharedMediaNativeReceivingReleaseValues.slotBound(plan: f.progress.plan, prepared: f.prepared,
            received: f.received, acquisitionIDs: f.progress.plan.targets.map(\.acquisitionID))
        let physical = try #require(initialResult.charges.first { $0.terminal && $0.stages.allSatisfy { $0 == 4 } })
        #expect(physical.packageBytes == slot.maximumReleasedBytes && physical.originBytes == 0)
        let shared = try #require(initialResult.charges.first { $0.terminal && $0.stages.allSatisfy { $0 == 5 } })
        #expect(shared.originBytes == (try initial.originReceiptBytes + Int64(count) * 512))
        // At the all-originals-retiring stage there are no pair charges. The
        // old slot and old identity are replaced, not retained beside bounds.
        let retiring = try #require(initialResult.charges.first { !$0.terminal && $0.stages.allSatisfy { $0 == 3 } })
        #expect(retiring.originBytes == shared.originBytes)

        try f.retirePair(0); _ = try check()
        if count == 2 {
            try f.retirePair(1); _ = try check()
            try f.removePair(1); _ = try check()
            try f.retireOriginal(1); _ = try check()
            try f.removeOriginal(1); _ = try check()
        }
        try f.removePair(0); _ = try check()
        try f.retireOriginal(0)
        let last = try check(), lastResult = try Projection.maximum(last)
        let same = try #require(lastResult.charges.first { !$0.terminal && $0.stages[0] == 3 })
        let immutable = try PhotoPreparationPolicy.add([last.envelopeBytes, last.consumerBytes, last.executionBytes])
        #expect(same.packageBytes == immutable + last.membershipBytes + slot.charged)
        #expect(same.originBytes == (try last.originReceiptBytes + 512))
        try f.removeOriginal(0)
        let done = try check(), doneResult = try Projection.maximum(done)
        #expect(done.pairs.isEmpty && done.ownedOriginals.isEmpty)
        #expect(doneResult.charges.count == 2)
        #expect(doneResult.charges.allSatisfy { $0.originBytes == 0 })
    }

    @Test func foreignTargetIsClassifiedWithoutChargingItsOriginLocally() async throws {
        let f = try await Fixture.make(count: 1, foreignOriginal: true)
        let c = f.store.context(), target = f.progress.plan.targets[0]
        let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: c)
        let origin = try #require(snapshot.targetOrigins.first)
        guard case .present(let packageID) = origin.location else { Issue.record("Missing physical origin"); return }
        #expect(packageID != f.store.packageID && origin.assetID == target.original.assetID)
        #expect(origin.acquisitionID == target.acquisitionID && snapshot.ownedOriginals.isEmpty)
        let receiptID = target.acquisitionID
        let receipt = try Fixture.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
        #expect(receipt.packageID == packageID && receipt.resultData != nil)
        #expect(try Projection.maximum(snapshot).charges.allSatisfy { $0.originBytes == 0 })
        #expect(!c.hasChanges)
        let memo = Projection.Memo()
        let expected = try Projection.maximum(Projection.components(snapshot), memo: memo)
        let otherForeign = Reader.TargetOrigin(assetID: origin.assetID, acquisitionID: origin.acquisitionID,
            location: .present(packageID: UUID()))
        #expect(try Projection.maximum(Projection.components(copy(snapshot, origins: [otherForeign])), memo: memo) == expected)
        #expect(memo.hits == 0 && memo.count == 2)
        // A foreign classification cannot conceal a missing local origin, or
        // be charged once here and again by the physical owner's budget pass.
        let fakeLocal = Reader.TargetOrigin(assetID: origin.assetID, acquisitionID: origin.acquisitionID,
            location: .present(packageID: f.store.packageID))
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(snapshot, origins: [fakeLocal])) }
    }

    @Test func rejectsAmbiguousOriginsAndInvalidArithmetic() async throws {
        let f = try await Fixture.make(count: 2)
        let s = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let first = try #require(s.ownedOriginals.first)
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, originals: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, originals: s.ownedOriginals + [first])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, origins: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, pairs: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, execution: -1)) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, execution: Int64.max)) }
        for invalid in [Int64(0), 513] {
            let wrong = Reader.Original(assetID: first.assetID, physicalOriginID: first.physicalOriginID,
                receiptBytes: first.receiptBytes, identityBytes: invalid, retiring: first.retiring)
            #expect(throws: (any Error).self) {
                _ = try Projection.maximum(copy(s, originals: [wrong] + s.ownedOriginals.dropFirst()))
            }
        }
        let extra = Reader.Original(assetID: UUID(), physicalOriginID: f.store.packageID,
            receiptBytes: 100, identityBytes: 40, retiring: false)
        let ordinary = try Projection.maximum(s), withExtra = try Projection.maximum(copy(s, originals: s.ownedOriginals + [extra]))
        #expect(withExtra.currentBytes == ordinary.currentBytes + 140)
        #expect(withExtra.currentIdentityExcludedBytes == ordinary.currentIdentityExcludedBytes + 100)
        #expect(withExtra.maximumIdentityExcludedBytes == ordinary.maximumIdentityExcludedBytes + 100)
        for (left, right) in zip(ordinary.charges, withExtra.charges) {
            #expect(left.packageBytes == right.packageBytes)
            #expect(right.originBytes == left.originBytes + 612)
        }
        // Preserve the existing cap categories: live package payload and its
        // owned receipts count toward 1 MiB; allocation identities are global.
        // These synthetic arithmetic boundaries do not authorize admission.
        let offset = PhotoPreparationPolicy.metadata - ordinary.maximumLivePackageMetadataBytes
        #expect(offset >= 0)
        let exact = try Projection.maximum(copy(s, execution: s.executionBytes + offset))
        #expect(exact.maximumLivePackageMetadataBytes == PhotoPreparationPolicy.metadata)
        #expect(exact.maximumIdentityExcludedBytes == PhotoPreparationPolicy.metadata)
        #expect(exact.maximumBytes > PhotoPreparationPolicy.metadata)
        try exact.requireMetadataCapacity()
        let over = try Projection.maximum(copy(s, execution: s.executionBytes + offset + 1))
        #expect(over.maximumLivePackageMetadataBytes == PhotoPreparationPolicy.metadata + 1)
        #expect(over.maximumIdentityExcludedBytes == PhotoPreparationPolicy.metadata + 1)
        #expect(throws: SharedMediaStorageFailure.capacity) { try over.requireMetadataCapacity() }
        #expect(exact.maximumTerminalSlotBytes == ordinary.maximumTerminalSlotBytes)
        for charge in exact.charges where charge.terminal {
            #expect(try charge.metadataCapBytes == charge.packageBytes)
            #expect(charge.packageBytes == exact.maximumTerminalSlotBytes)
        }
        let identity = Reader.Original(assetID: first.assetID, physicalOriginID: first.physicalOriginID,
            receiptBytes: first.receiptBytes, identityBytes: 512, retiring: first.retiring)
        let identities = try Projection.maximum(copy(s, originals: [identity] + s.ownedOriginals.dropFirst()))
        #expect(identities.currentBytes == ordinary.currentBytes + 512 - first.identityBytes)
        #expect(identities.currentIdentityExcludedBytes == ordinary.currentIdentityExcludedBytes)
        #expect(identities.maximumIdentityExcludedBytes == ordinary.maximumIdentityExcludedBytes)
        #expect(identities.maximumLivePackageMetadataBytes == ordinary.maximumLivePackageMetadataBytes)
        #expect(identities.maximumTerminalSlotBytes == ordinary.maximumTerminalSlotBytes)
        let targetIndex = try #require(s.release.progress.plan.targets.firstIndex { $0.original.assetID == first.assetID })
        for (left, right) in zip(ordinary.charges, identities.charges) {
            #expect(try left.metadataCapBytes == right.metadataCapBytes)
            #expect(left.originReceiptBytes == right.originReceiptBytes)
            let delta = left.stages[targetIndex] <= 2 ? 512 - first.identityBytes : 0
            #expect(right.originIdentityBytes == left.originIdentityBytes + delta)
            #expect(try right.total == left.total + delta)
        }
    }

    @Test func memoRetainsOnlyExactSizingValuesWithinEntryAndByteBounds() async throws {
        let f = try await Fixture.make(count: 1)
        let s = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let input = Projection.components(s), memo = Projection.Memo()
        let baseline = try Projection.maximum(input)
        #expect(try Projection.maximum(input, memo: memo) == baseline)
        #expect(memo.hits == 0 && memo.count == 1)
        #expect(try Projection.maximum(Projection.components(s), memo: memo) == baseline)
        #expect(memo.hits == 1 && memo.count == 1)
        // Same snapshot/header, different scalar liability must never reuse it.
        for delta in 1...5 {
            let changed = Projection.components(copy(s, execution: s.executionBytes + Int64(delta)))
            #expect(try Projection.maximum(changed, memo: memo) == Projection.maximum(changed))
            #expect(memo.hits == 1)
            #expect(memo.count <= PhotoPreparationPolicy.maximumPackages)
            #expect(memo.retainedBytes <= Projection.Memo.byteLimit)
        }
        _ = try Projection.maximum(input, memo: memo)
        #expect(memo.hits == 1) // oldest full-value key was evicted
        let fresh = Projection.Memo(), tiny = Projection.Memo(byteLimit: 1)
        #expect(try Projection.maximum(input, memo: fresh) == baseline)
        #expect(fresh.hits == 0)
        for _ in 0..<2 { #expect(try Projection.maximum(input, memo: tiny) == baseline) }
        #expect(tiny.isEmpty && tiny.hits == 0 && tiny.retainedBytes == 0)
        let small = Projection.Memo(byteLimit: 512)
        #expect(try Projection.maximum(input, memo: small) == baseline)
        #expect(small.isEmpty && small.retainedBytes == 0)
        let extra = (0..<2).map { _ in Reader.Original(assetID: UUID(), physicalOriginID: f.store.packageID,
            receiptBytes: 100, identityBytes: 40, retiring: false) }
        let oversized = Projection.components(copy(s, originals: s.ownedOriginals + extra))
        let oldCount = memo.count, oldBytes = memo.retainedBytes, oldHits = memo.hits
        #expect(try Projection.maximum(oversized, memo: memo) == Projection.maximum(oversized))
        #expect(memo.count == oldCount && memo.retainedBytes == oldBytes && memo.hits == oldHits)
    }

    @Test func memoRevalidatesOriginsPairsAndArithmeticBeforeReuse() async throws {
        let f = try await Fixture.make(count: 1)
        let s = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let memo = Projection.Memo()
        _ = try Projection.maximum(Projection.components(s), memo: memo)
        for invalid in [copy(s, originals: []), copy(s, origins: []), copy(s, pairs: []), copy(s, execution: -1)] {
            #expect(throws: (any Error).self) { _ = try Projection.maximum(Projection.components(invalid), memo: memo) }
        }
        #expect(memo.hits == 0 && memo.count == 1)
        let original = try #require(s.ownedOriginals.first)
        let changed = copy(s, originals: [.init(assetID: original.assetID, physicalOriginID: original.physicalOriginID,
            receiptBytes: original.receiptBytes + 1, identityBytes: original.identityBytes, retiring: original.retiring)])
        #expect(try Projection.maximum(Projection.components(changed), memo: memo) == Projection.maximum(changed))
        #expect(memo.hits == 0 && memo.count == 2)
        try f.retirePair(0)
        let advanced = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        #expect(try Projection.maximum(Projection.components(advanced), memo: memo) == Projection.maximum(advanced))
        #expect(memo.hits == 0 && memo.count == 3)
    }

    @Test func presentationCompanionPreservesLegacyFundingAndKeysExactBytes() async throws {
        let f = try await Fixture.make(count: 1)
        let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let original = Projection.components(snapshot), baseline = try Projection.maximum(original)
        let identity = AnalysisRecoveryPresentation.Identity(ownerID: f.prepared.profile.ownerID,
            observationID: f.prepared.observationID, operationID: f.prepared.operationID)
        let first = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID())
        let second = try first.settle(current: first.reserved, elapsed: .zero).reserve(id: UUID())
        let firstBytes = try first.reserved.encoded(), secondBytes = try second.reserved.encoded()
        #expect(firstBytes != secondBytes && firstBytes.count == secondBytes.count)
        var input = original; input.recoveryPresentationData = firstBytes
        let memo = Projection.Memo(), measured = try Projection.maximum(input, memo: memo)
        #expect(measured.recoveryPresentation.bytes == firstBytes)
        #expect(measured.recoveryPresentation.materializedBytes == Int64(firstBytes.count))
        #expect(measured.recoveryPresentation.chargedBytes == 512)
        #expect(measured.recoveryPresentation.remainingTransitions == 59)
        #expect(measured.charges == baseline.charges)
        #expect(measured.currentBytes == baseline.currentBytes && measured.maximumBytes == baseline.maximumBytes)
        #expect(measured.currentIdentityExcludedBytes == baseline.currentIdentityExcludedBytes)
        #expect(measured.maximumIdentityExcludedBytes == baseline.maximumIdentityExcludedBytes)
        let funding = SharedMediaNativeReceivedReleaseSnapshot.Liability(current: baseline.currentIdentityExcludedBytes,
            reserved: baseline.maximumIdentityExcludedBytes - baseline.currentIdentityExcludedBytes)
        let oldFunding = try SharedMediaNativeReceivedReleaseSnapshot.Funding(before: funding, projection: baseline)
        let newFunding = try SharedMediaNativeReceivedReleaseSnapshot.Funding(before: funding, projection: measured)
        #expect(oldFunding.before == newFunding.before && oldFunding.after == newFunding.after)
        try newFunding.requireExistingFunding()
        #expect(try Projection.maximum(input, memo: memo) == measured)
        #expect(memo.hits == 1 && memo.count == 1)
        input.recoveryPresentationData = secondBytes
        let changed = try Projection.maximum(input, memo: memo)
        #expect(changed.recoveryPresentation.bytes == secondBytes && changed != measured)
        #expect(memo.hits == 1 && memo.count == 2)
        // The queue companion consumes package capacity without changing B/S.
        let offset = PhotoPreparationPolicy.metadata - baseline.maximumLivePackageMetadataBytes
        var exact = Projection.components(copy(snapshot, execution: snapshot.executionBytes + offset - 512))
        exact.recoveryPresentationData = firstBytes
        try Projection.maximum(exact).requireMetadataCapacity()
        var over = Projection.components(copy(snapshot, execution: snapshot.executionBytes + offset - 511))
        over.recoveryPresentationData = firstBytes
        #expect(throws: SharedMediaStorageFailure.capacity) { try Projection.maximum(over).requireMetadataCapacity() }
        let foreign = AnalysisRecoveryPresentation.Identity(ownerID: identity.ownerID,
            observationID: identity.observationID, operationID: UUID())
        for invalid in [Data(), Data("{}".utf8), try AnalysisRecoveryPresentation.initial(for: foreign).encoded()] {
            input.recoveryPresentationData = invalid
            #expect(throws: (any Error).self) { _ = try Projection.maximum(input, memo: memo) }
        }
        #expect(memo.hits == 1 && memo.count == 2)
        #expect(baseline.recoveryPresentation.bytes == nil && baseline.recoveryPresentation.chargedBytes == 0)
    }

    @Test func presentationRunwaySurvivesCleanupAndAggregatesWithOtherRoots() async throws {
        let f = try await Fixture.make(count: 1)
        var snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let baseline = try SharedMediaNativeReceivingCleanGraph.Witness.releasing(snapshot).remainingAdvances
        let identity = AnalysisRecoveryPresentation.Identity(ownerID: f.prepared.profile.ownerID,
            observationID: f.prepared.observationID, operationID: f.prepared.operationID)
        let reservation = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID())
        snapshot.recoveryPresentationData = try reservation.reserved.encoded()
        let witness = SharedMediaNativeReceivingCleanGraph.Witness.releasing(snapshot)
        #expect(try witness.remainingAdvances == baseline + 59)
        try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - baseline - 59,
            witnesses: [witness])
        #expect(throws: (any Error).self) {
            try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - baseline - 58,
                witnesses: [witness])
        }
        // Pure aggregate arithmetic; duplicate synthetic roots grant no identity
        // or admission authority. The clean reader checks uniqueness separately.
        #expect(throws: (any Error).self) {
            try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - baseline - 59,
                witnesses: [witness, witness])
        }
        let exhausted = try reservation.settle(current: reservation.reserved, elapsed: .seconds(30))
        snapshot.recoveryPresentationData = try exhausted.encoded()
        #expect(try Projection.maximum(snapshot).recoveryPresentation.chargedBytes == 512)
        #expect(try SharedMediaNativeReceivingCleanGraph.Witness.releasing(snapshot).remainingAdvances == baseline + 58)
    }

    @Test func presentationFreshnessRejectsExactByteAndQueueIdentityChanges() async throws {
        let f = try await Fixture.make(count: 1)
        let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let request = snapshot.release.origin.transaction, queueID = request.cohort.originQueueID
        let context = f.store.context()
        let queue = try Fixture.one(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        func check(_ expected: Data?) throws {
            try SharedMediaNativeReceivingRows.requireRecoveryPresentation(expected, request: request, in: context)
        }
        try check(nil)
        let initial = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: f.prepared.profile.ownerID,
            observationID: f.prepared.observationID, operationID: f.prepared.operationID))
        let first = try initial.reserve(id: UUID()).reserved.encoded()
        let second = try initial.reserve(id: UUID()).reserved.encoded()
        #expect(first != second && first.count == second.count)
        // Same revision and length still require the exact reservation bytes.
        queue.recoveryPresentationData = first
        #expect(context.hasChanges)
        try check(first)
        #expect(throws: SharedMediaStorageFailure.stale) { try check(nil) }
        queue.recoveryPresentationData = second
        #expect(throws: SharedMediaStorageFailure.stale) { try check(first) }
        try check(second)
        queue.recoveryPresentationData = nil
        #expect(throws: SharedMediaStorageFailure.stale) { try check(second) }
        try context.save()
        try check(nil)
        // A pending canonical/uppercase alias or reverse binding must not be
        // hidden by a bounded fetch. All faults are rolled back independently.
        for alias in [queueID, queueID.uppercased(), request.cohort.observationID,
                      request.cohort.observationID.uppercased(), UUID().uuidString.lowercased()] {
            let duplicate = OfflineQueuedScan(id: alias, timestamp: request.timestamp)
            if alias != queueID && alias != queueID.uppercased() &&
                alias != request.cohort.observationID && alias != request.cohort.observationID.uppercased() {
                duplicate.sharedMediaConsumerID = request.cohort.bindingID
            }
            context.insert(duplicate)
            #expect(context.hasChanges)
            #expect(throws: SharedMediaStorageFailure.stale) { try check(nil) }
            context.rollback()
            try check(nil)
        }
        let current = try Fixture.one(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        current.id = queueID.uppercased()
        #expect(throws: SharedMediaStorageFailure.stale) { try check(nil) }
        current.id = queueID
        current.sharedMediaConsumerID = UUID()
        #expect(throws: SharedMediaStorageFailure.stale) { try check(nil) }
        current.sharedMediaConsumerID = request.cohort.bindingID
        context.delete(current)
        #expect(throws: SharedMediaStorageFailure.stale) { try check(nil) }
        context.rollback()
        try check(nil)
    }

    @Test func liveReadersKeepPresentationAdmissionClosed() async throws {
        let f = try await Fixture.make(count: 1)
        let context = f.store.context(), queueID = f.prepared.queueID.uuidString.lowercased()
        let queue = try Fixture.one(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        queue.recoveryPresentationData = try AnalysisRecoveryPresentation.initial(for: .init(
            ownerID: f.prepared.profile.ownerID, observationID: f.prepared.observationID,
            operationID: f.prepared.operationID)).reserve(id: UUID()).reserved.encoded()
        try context.save()
        #expect(throws: (any Error).self) {
            _ = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        }
    }

    private func copy(_ s: Reader.Snapshot, originals: [Reader.Original]? = nil,
                      origins: [Reader.TargetOrigin]? = nil, pairs: [SharedMediaNativePairFileState]? = nil,
                      execution: Int64? = nil) -> Reader.Snapshot {
        .init(release: s.release, inventoryRevision: s.inventoryRevision, envelopeBytes: s.envelopeBytes,
            membershipBytes: s.membershipBytes, consumerBytes: s.consumerBytes, executionBytes: execution ?? s.executionBytes,
            slotBytes: s.slotBytes, pairs: pairs ?? s.pairs, ownedOriginals: originals ?? s.ownedOriginals,
            targetOrigins: origins ?? s.targetOrigins, recoveryPresentationData: s.recoveryPresentationData)
    }
}
