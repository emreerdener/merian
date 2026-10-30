import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Native single-role transfer reservation", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativePhotoTransferReservationTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Mapping = SharedMediaNativePhotoRoleMapping
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row

    private func allocate(_ owner: SharedMediaNativeOriginalOwner, _ p: SharedMediaNativeReceivingIntent.Prepared) async throws -> Allocation {
        try await owner.allocateAppPhotoRoles(p, authorizeCreate: { prepared, _ in
            .init(recipient: try #require(prepared.photoAdmission).expectedProcessorPermission, validate: {})
        }) { request, validate, settle in
            try validate(); try settle()
            let entries = try Mapping.references(request.allocation.claim).enumerated().map { index, reference in
                Mapping.Entry(photoOrdinal: index / 3, role: Mapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
            }
            return .allocated(.init(receipt: .init(assignmentDigest: String(repeating: "a", count: 64),
                createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001), entries: entries))
        }
    }
    private func row(_ h: Store) throws -> Row {
        let id = h.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func budget(_ h: Store) throws -> SharedMediaStoragePolicy.Totals {
        let c = h.context(), id = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: h.ownerID, format: .appV2).totals
    }
    private func minimumAvailable(_ totals: SharedMediaStoragePolicy.Totals) -> Int64 {
        var lower: Int64 = 0, upper: Int64 = 1 << 40
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if (try? totals.checkAvailable(middle)) != nil { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }

    @Test(arguments: Mapping.Role.allCases)
    func exactRoleIsChargedOnceAndSurvivesColdReopen(_ role: Mapping.Role) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), before = try row(h), oldBudget = try budget(h)
        let entry = try #require(allocation.roleMapping?.entries.first { $0.role == role })
        let held = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        #expect(held.version == 3 && held.claim == allocation.claim && held.receipt == allocation.receipt)
        #expect(held.roleMapping == allocation.roleMapping && held.remainingAdvances == 0)
        #expect(try held.transferReservation == SharedMediaNativePhotoTransferReservation(prepared: p, selection: entry))
        try allocation.requireSuccessor(held)
        #expect(throws: (any Error).self) { try held.requireSuccessor(allocation) }
        #expect(try Allocation.decode(held.encoded(), sha256: SharedMediaAcquisitionEncoding.digest(held.encoded())) == held)
        let after = try row(h), totals = try budget(h)
        #expect(after.preparedData == before.preparedData && after.resultData == before.resultData && after.revision == before.revision)
        // Both sidecars are fully materialized. Their metadata remains charged
        // to durable storage, but only the future copy needs free-space headroom.
        let oldMetadata = try allocation.storageCharge, heldMetadata = try held.storageCharge
        #expect(oldMetadata == Int64(try allocation.encoded().count) + 64)
        #expect(heldMetadata == Int64(try held.encoded().count) + 64)
        #expect(heldMetadata > oldMetadata)
        let additionalHeadroom = minimumAvailable(totals) - minimumAvailable(oldBudget)
        #expect(additionalHeadroom == SharedMediaNativePhotoTransferReservation.copyAllowance)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Replay attempted another save") } }
        #expect(try await owner.reserveAppPhotoTransfer(p, selection: entry) == held)
        #expect(try row(h) == after && budget(h) == totals)
        let other = try #require(allocation.roleMapping?.entries.first { $0.role != role })
        await #expect(throws: SharedMediaStorageFailure.inUse) { _ = try await owner.reserveAppPhotoTransfer(p, selection: other) }
        await #expect(throws: (any Error).self) { _ = try await owner.appReleaseStageRequest(p, releaseID: UUID()) }
        await #expect(throws: (any Error).self) { _ = try await owner.abandonAppReceiving(p) }
        #expect(try row(h) == after && budget(h) == totals)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.reserveAppPhotoTransfer(p, selection: entry) == held)
        #expect(try row(h) == after && budget(h) == totals)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["afterSave", "readback", "capacity", "revision", "cancel"])
    func failedOrAmbiguousReservationNeverDiscardsTheHold(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p)
        let entry = try #require(allocation.roleMapping?.entries.first), before = try row(h)
        var saved = false
        if fault == "revision" {
            let c = h.context(), id = h.inventoryID
            let inventory = try SharedMediaNativePairPlanGraph.one(c,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            inventory.revision = Int64.max; try c.save()
        }
        try owner.setMetadataFault({ boundary in
            if boundary == .afterSave { saved = true; if fault == "afterSave" { throw SharedMediaStorageFailure.unavailable } }
            if boundary == .beforeReadback && saved && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
            if boundary == .beforeSave && fault == "cancel" { throw CancellationError() }
        }, availableBytes: fault == "capacity" ? minimumAvailable(try budget(h)) : nil)
        if fault == "afterSave" { _ = try await owner.reserveAppPhotoTransfer(p, selection: entry) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPhotoTransfer(p, selection: entry) } }
        if fault == "afterSave" || fault == "readback" {
            let current = try row(h)
            let value = try Allocation.decode(#require(current.allocationData), sha256: #require(current.allocationSHA256))
            #expect(value.transferReservation?.selection == entry)
            try owner.setMetadataFault(nil)
            #expect(try await owner.reserveAppPhotoTransfer(p, selection: entry) == value)
            #expect(try row(h) == current)
        } else { #expect(try row(h) == before) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["object", "reference", "ordinal", "role"])
    func alteredMappingCannotReserve(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), before = try row(h)
        let entry = try #require(allocation.roleMapping?.entries.first)
        let altered = Mapping.Entry(photoOrdinal: fault == "ordinal" ? 1 : entry.photoOrdinal,
            role: fault == "role" ? .display : entry.role, referenceID: fault == "reference" ? UUID() : entry.referenceID,
            objectID: fault == "object" ? UUID() : entry.objectID)
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPhotoTransfer(p, selection: altered) }
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func unrelatedMutationPreservesTransferChargeAndExcludesAnotherPackage() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let other = UUID(), draft = UUID(), image = PhotoPreparationTestHarness.image()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: draft, ordinal: 0, kind: .picker)
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        _ = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        let held = try row(h), before = try budget(h)
        var competing = before
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try competing.include(.init(packageID: other, pool: .transfer, materialized: 0, reserved: 1))
        }
        let edit = try await owner.prepareAppMetadata(packageID: other, draftGeneration: draft,
            contexts: [.init(freeText: "Independent draft after transfer reservation")])
        _ = try await owner.saveAppMetadata(edit)
        #expect(try row(h) == held)
        var after = try budget(h)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try after.include(.init(packageID: other, pool: .transfer, materialized: 0, reserved: 1))
        }
        #expect(minimumAvailable(after) >= SharedMediaStoragePolicy.reserve + SharedMediaNativePhotoTransferReservation.copyAllowance)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["assetGeneration", "descriptor", "state", "copyAllowance", "version"])
    func malformedPersistedReservationFailsClosed(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        let held = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        var object = try SharedMediaNativeReceivingTestFixture.object(held)
        var transfer = try #require(object["transferReservation"] as? [String: Any])
        switch fault {
        case "assetGeneration": transfer["assetGeneration"] = UUID().uuidString
        case "descriptor": transfer["descriptor"] = [:]
        case "state": transfer["state"] = "closed"
        case "copyAllowance": transfer["copyAllowance"] = 0
        default: object["version"] = 2
        }
        object["transferReservation"] = transfer
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let c = h.context(), id = h.packageID
        let slot = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        slot.allocationData = bytes; slot.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(bytes); try c.save()
        #expect(throws: (any Error).self) { _ = try budget(h) }
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPhotoTransfer(p, selection: entry) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func status(_ allocation: Allocation, state: String?, closed: Bool = false,
                        id: UUID, objectID: UUID? = nil, created: Int64 = 100) throws -> InitialPhotoUploadStatus {
        let receipt = try #require(allocation.receipt)
        let object = try objectID ?? #require(allocation.transferReservation).selection.objectID
        let attempt: Any = state.map { ["attempt_id": id.uuidString.lowercased(), "state": $0,
            "created_at_ms": created, "capability_expires_at_ms": min(receipt.expiresAtMilliseconds, created + 600_000),
            "write_closed": closed] as [String: Any] } ?? NSNull()
        let wire: [String: Any] = ["version": 1, "authority": "none", "scan_id": allocation.claim.observationID.uuidString.lowercased(),
            "assignment_digest": receipt.assignmentDigest, "object_id": object.uuidString.lowercased(), "attempt": attempt]
        return try InitialPhotoUploadStatus(data: JSONSerialization.data(withJSONObject: wire), allocation: allocation, objectID: object)
    }

    @Test(arguments: Mapping.Role.allCases)
    func historicalAttemptProgressKeepsIdentityAndCopyLiability(_ role: Mapping.Role) async throws {
        let (h, initialOwner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        var owner = initialOwner
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first { $0.role == role })
        let v3 = try await owner.reserveAppPhotoTransfer(p, selection: entry), legacyBytes = try v3.encoded()
        var current = try await owner.reserveAppPhotoRemoteAttempt(p)
        let reservedCharge = try current.storageCharge, attemptID = UUID()
        #expect(current.version == 4 && current.remoteAttempt == nil && current.remainingAdvances == 3)
        #expect(reservedCharge > (try v3.storageCharge))
        #expect(try v3.encoded() == legacyBytes)
        #expect(try Allocation.decode(legacyBytes, sha256: SharedMediaAcquisitionEncoding.digest(legacyBytes)) == v3)
        let before = try row(h)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Absent/replayed status attempted a save") } }
        #expect(try await owner.reserveAppPhotoRemoteAttempt(p) == current)
        #expect(try await owner.observeAppPhotoRemoteAttempt(p, allocation: current,
            status: status(current, state: nil, id: attemptID)) == current)
        #expect(try row(h) == before)
        try owner.setMetadataFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        owner = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await owner.reserveAppPhotoRemoteAttempt(p) == current)
        for (index, value) in [("bound", false), ("may_have_issued", false), ("may_have_issued", true)].enumerated() {
            let (state, closed) = value
            let remaining = Int64(2 - index)
            let old = current
            current = try await owner.observeAppPhotoRemoteAttempt(p, allocation: old,
                status: status(old, state: state, closed: closed, id: attemptID))
            try old.requireSuccessor(current)
            #expect(current.remainingAdvances == remaining && current.remoteAttempt?.id == attemptID)
            #expect(current.remoteAttempt?.createdAtMilliseconds == 100 && current.remoteAttempt?.capabilityExpiresAtMilliseconds == 600_100)
            #expect(current.claim == v3.claim && current.receipt == v3.receipt && current.transferReservation == v3.transferReservation)
            #expect(try current.storageCharge == reservedCharge)
            let facts = try row(h)
            #expect(facts.preparedData == before.preparedData && facts.resultData == before.resultData && facts.revision == before.revision)
            #expect(minimumAvailable(try budget(h)) >= SharedMediaStoragePolicy.reserve + SharedMediaNativePhotoTransferReservation.copyAllowance)
            let bytes = try current.encoded()
            #expect(try Allocation.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)) == current)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            owner = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            #expect(try await owner.reserveAppPhotoRemoteAttempt(p) == current)
        }
        let final = try row(h)
        let summary = try await owner.verifyAppPhotoTransfer(p, allocation: current)
        #expect(summary.selection == entry && current.remoteAttempt?.writeClosed == true)
        #expect(try row(h) == final)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.reserveAppPhotoRemoteAttempt(p) == current)
        #expect(try await cold.observeAppPhotoRemoteAttempt(p, allocation: current,
            status: status(current, state: "may_have_issued", closed: true, id: attemptID)) == current)
        #expect(try row(h) == final)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["absent", "backward", "identity", "clocks", "role", "stale", "reopen"])
    func historicalObservationCannotEraseOrReplaceSavedFacts(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        _ = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        let empty = try await owner.reserveAppPhotoRemoteAttempt(p), id = UUID()
        let current = try await owner.observeAppPhotoRemoteAttempt(p, allocation: empty,
            status: status(empty, state: "may_have_issued", closed: true, id: id))
        let before = try row(h), totals = try budget(h)
        let otherObject = try #require(allocation.roleMapping?.entries.first { $0.objectID != entry.objectID }).objectID
        let response = try status(current, state: fault == "absent" ? nil : (fault == "backward" ? "bound" : "may_have_issued"),
            closed: fault != "backward" && fault != "reopen", id: fault == "identity" ? UUID() : id,
            objectID: fault == "role" ? otherObject : nil, created: fault == "clocks" ? 200 : 100)
        await #expect(throws: (any Error).self) {
            _ = try await owner.observeAppPhotoRemoteAttempt(p, allocation: fault == "stale" ? empty : current, status: response)
        }
        #expect(try row(h) == before && budget(h) == totals)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["afterSave", "readback", "cancel", "capacity", "deleted", "account"])
    func observationFailureKeepsExactRecoverableHold(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        _ = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        let empty = try await owner.reserveAppPhotoRemoteAttempt(p), id = UUID()
        let response = try status(empty, state: "bound", id: id), before = try row(h)
        var didSave = false
        try owner.setMetadataFault({ boundary in
            if boundary == .afterSave { didSave = true; if fault == "afterSave" { throw SharedMediaStorageFailure.unavailable } }
            if boundary == .beforeReadback && didSave && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
            if boundary == .beforeSave && fault == "cancel" { throw CancellationError() }
        }, availableBytes: fault == "capacity" ? 0 : nil)
        if fault == "deleted" {
            let c = h.context(), key = p.queueID.uuidString.lowercased()
            let queue = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == key }))
            c.delete(queue); try c.save()
        }
        if fault == "account" { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        if fault == "afterSave" { _ = try await owner.observeAppPhotoRemoteAttempt(p, allocation: empty, status: response) } else { await #expect(throws: (any Error).self) { _ = try await owner.observeAppPhotoRemoteAttempt(p, allocation: empty, status: response) } }
        if fault == "afterSave" || fault == "readback" {
            let saved = try row(h), data = try #require(saved.allocationData)
            let current = try Allocation.decode(data, sha256: #require(saved.allocationSHA256))
            #expect(current.remoteAttempt?.id == id && current.remainingAdvances == 2)
            try owner.setMetadataFault(nil)
            #expect(try await owner.observeAppPhotoRemoteAttempt(p, allocation: current, status: response) == current)
            #expect(try row(h) == saved)
        } else { #expect(try row(h) == before) }
        if fault != "account" { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test func statusRunwayCannotBeSpentByAnIndependentDraft() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let other = UUID(), draft = UUID(), image = PhotoPreparationTestHarness.image()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: draft, ordinal: 0, kind: .picker)
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        _ = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        let c = h.context(), id = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        inventory.revision = Int64.max - 3; try c.save()
        let before = try row(h)
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPhotoRemoteAttempt(p) }
        #expect(try row(h) == before)
        inventory.revision = Int64.max - 4; try c.save()
        var current = try await owner.reserveAppPhotoRemoteAttempt(p)
        await #expect(throws: (any Error).self) {
            let edit = try await owner.prepareAppMetadata(packageID: other, draftGeneration: draft, contexts: [.init(freeText: "later selection")])
            _ = try await owner.saveAppMetadata(edit)
        }
        let attemptID = UUID()
        for (state, closed) in [("bound", false), ("may_have_issued", false), ("may_have_issued", true)] {
            current = try await owner.observeAppPhotoRemoteAttempt(p, allocation: current,
                status: status(current, state: state, closed: closed, id: attemptID))
        }
        let fresh = h.context()
        #expect(try SharedMediaNativePairPlanGraph.one(fresh, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id })).revision == Int64.max)
        #expect(current.remoteAttempt?.writeClosed == true)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["version", "state", "closed", "created", "expiry", "ticket"])
    func corruptDurableAttemptFailsClosed(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await allocate(owner, p), entry = try #require(allocation.roleMapping?.entries.first)
        _ = try await owner.reserveAppPhotoTransfer(p, selection: entry)
        let empty = try await owner.reserveAppPhotoRemoteAttempt(p)
        let held = try await owner.observeAppPhotoRemoteAttempt(p, allocation: empty, status: status(empty, state: "bound", id: UUID()))
        var object = try SharedMediaNativeReceivingTestFixture.object(held)
        var attempt = try #require(object["remoteAttempt"] as? [String: Any])
        switch fault {
        case "version": object["version"] = 3
        case "state": attempt["state"] = "uploadAuthorized"
        case "closed": attempt["writeClosed"] = true
        case "created": attempt["createdAtMilliseconds"] = 0
        case "expiry": attempt["capabilityExpiresAtMilliseconds"] = 600_101
        default: attempt["ticket"] = "forbidden"
        }
        object["remoteAttempt"] = attempt
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) { _ = try Allocation.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)) }
        #expect(try row(h).allocationData == held.encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

}
