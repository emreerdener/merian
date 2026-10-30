import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native allocation role enrichment", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativePhotoEnrichmentTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Mapping = SharedMediaNativePhotoRoleMapping
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    private var receipt: Allocation.Receipt {
        .init(assignmentDigest: String(repeating: "a", count: 64), createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
    }
    private func row(_ h: Store) throws -> Row {
        let id = h.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func allocation(_ h: Store) throws -> Allocation {
        let r = try row(h)
        return try .decode(#require(r.allocationData), sha256: #require(r.allocationSHA256))
    }
    private func inventory(_ h: Store, _ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func revision(_ h: Store) throws -> Int64 { try inventory(h, h.context()).revision }
    private func mapping(_ allocation: Allocation) throws -> Mapping {
        .init(entries: try Mapping.references(allocation.claim).enumerated().map { index, reference in
            .init(photoOrdinal: index / 3, role: Mapping.Role.allCases[index % 3], referenceID: reference,
                  objectID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 100))!)
        })
    }
    private func authorize(_ p: SharedMediaNativeReceivingIntent.Prepared) throws -> IdentificationDispatchAuthorization {
        .init(recipient: try #require(p.photoAdmission).expectedProcessorPermission, validate: {})
    }

    @Test(arguments: [false, true])
    func canonicalLegacyBytesAndMonotonicBudgetArePreserved(settled: Bool) throws {
        let fixture = InitialPhotoAllocationRoleReplyTests(), projected = try fixture.projection()
        let legacy = try fixture.request(receipt: settled ? projected.receipt : nil).allocation
        let bytes = try legacy.encoded(), reserved = try legacy.reservingRoleMapping()
        #expect(try Allocation.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)).encoded() == bytes)
        #expect(try reserved.legacyEncoded() == bytes)
        #expect(reserved.claim == legacy.claim && reserved.receipt == legacy.receipt)
        #expect(reserved.remainingAdvances == (settled ? 1 : 2))
        try legacy.requireSuccessor(reserved)
        let mapping = Mapping(entries: projected.entries)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try legacy.enriching(projected.receipt, mapping: mapping) }
        let enriched = try reserved.enriching(projected.receipt, mapping: mapping)
        try reserved.requireSuccessor(enriched)
        #expect(enriched.remainingAdvances == 0)
        #expect(try enriched.storageCharge <= reserved.storageCharge)
        #expect(try enriched.enriching(projected.receipt, mapping: mapping) == enriched)
        #expect(try enriched.settling(projected.receipt) == enriched)
        #expect(throws: (any Error).self) { try enriched.requireSuccessor(reserved) }
        let actual = try enriched.encoded()
        #expect(try Allocation.decode(actual, sha256: SharedMediaAcquisitionEncoding.digest(actual)) == enriched)
        let maximum = Allocation.Receipt(assignmentDigest: String(repeating: "f", count: 64),
            createdAtMilliseconds: 8_639_999_998_200_000, expiresAtMilliseconds: 8_640_000_000_000_000)
        if !settled {
            let maximumSuccessor = try reserved.enriching(maximum, mapping: mapping)
            #expect(try reserved.storageCharge == Int64(maximumSuccessor.encoded().count) + 64)
            let lateLegacy = try reserved.settling(projected.receipt)
            try reserved.requireSuccessor(lateLegacy)
            #expect(lateLegacy.version == 2 && lateLegacy.remainingAdvances == 1)
            #expect(try lateLegacy.storageCharge <= reserved.storageCharge)
        }
    }

    @Test(arguments: ["noReceipt", "legacyMapping", "wrongRole", "duplicateObject", "changedClock", "changedClaim", "unknownField"])
    func malformedPersistedEnrichmentCannotEnterGraph(_ fault: String) throws {
        let fixture = InitialPhotoAllocationRoleReplyTests(), projected = try fixture.projection()
        let reserved = try fixture.request().allocation.reservingRoleMapping()
        let enriched = try reserved.enriching(projected.receipt, mapping: .init(entries: projected.entries))
        var object = try #require(JSONSerialization.jsonObject(with: enriched.encoded()) as? [String: Any])
        switch fault {
        case "noReceipt": object.removeValue(forKey: "receipt")
        case "legacyMapping": object["version"] = 1
        case "wrongRole", "duplicateObject":
            var mapping = try #require(object["roleMapping"] as? [String: Any])
            var entries = try #require(mapping["entries"] as? [[String: Any]])
            if fault == "wrongRole" { entries[0]["role"] = "display" }
            else { entries[1]["objectID"] = entries[0]["objectID"] }
            mapping["entries"] = entries; object["roleMapping"] = mapping
        case "changedClock":
            let changed = Allocation.Receipt(assignmentDigest: projected.receipt.assignmentDigest,
                createdAtMilliseconds: projected.receipt.createdAtMilliseconds + 1,
                expiresAtMilliseconds: projected.receipt.expiresAtMilliseconds + 1)
            #expect(throws: (any Error).self) { _ = try enriched.enriching(changed, mapping: .init(entries: projected.entries)) }
            return
        case "changedClaim":
            var claim = try #require(object["claim"] as? [String: Any]); claim["contentDigest"] = String(repeating: "b", count: 64); object["claim"] = claim
        case "unknownField": object["authority"] = "upload"
        default: throw SharedMediaStorageFailure.invalid
        }
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) { _ = try Allocation.decode(invalid, sha256: SharedMediaAcquisitionEncoding.digest(invalid)) }
    }

    @Test func settledLegacyRejectsCapacityThenRecoversAmbiguousReservationAndColdMapping() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture(), receipt = receipt
        let legacy = try await owner.allocateAppPhoto(p, authorizeCreate: { p, _ in try authorize(p) }) { _, _, _ in .allocated(receipt) }
        let before = try row(h), originalRevision = try revision(h), legacyBytes = try legacy.encoded()
        try owner.setMetadataFault(nil, availableBytes: 0)
        await #expect(throws: (any Error).self) {
            _ = try await owner.enrichAppPhotoAllocation(p) { _, _ in Issue.record("Capacity failure dispatched"); return .held(.notFound) }
        }
        #expect(try row(h) == before && revision(h) == originalRevision)
        try owner.setMetadataFault(nil)
        let c = h.context(), inv = try inventory(h, c); inv.revision = Int64.max - 1; try c.save()
        await #expect(throws: (any Error).self) {
            _ = try await owner.enrichAppPhotoAllocation(p) { _, _ in Issue.record("Revision exhaustion dispatched"); return .held(.notFound) }
        }
        #expect(try row(h) == before && revision(h) == Int64.max - 1)
        let reset = h.context(); try inventory(h, reset).revision = originalRevision; try reset.save()
        var fault = true
        try owner.setMetadataFault { if $0 == .afterSave && fault { fault = false; throw SharedMediaStorageFailure.unavailable } }
        let reserved = try await owner.enrichAppPhotoAllocation(p) { request, validate in
            try validate(); #expect(request.version == 2 && request.receipt == receipt)
            #expect(try allocation(h) == request && request.legacyEncoded() == legacyBytes)
            return .held(.expired)
        }
        #expect(reserved.roleMapping == nil && reserved.remainingAdvances == 1)
        #expect(try revision(h) == originalRevision + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h), expected = try mapping(reserved)
        let enriched = try await cold.enrichAppPhotoAllocation(p) { request, validate in
            try validate(); #expect(request == reserved)
            return .allocated(.init(receipt: receipt, entries: expected.entries))
        }
        #expect(enriched.roleMapping == expected && enriched.receipt == receipt)
        #expect(try revision(h) == originalRevision + 2)
        let final = try row(h)
        #expect(final.preparedData == before.preparedData && final.resultData == before.resultData && final.revision == before.revision)
        let replay = try await cold.allocateAppPhoto(p, authorizeCreate: { p, _ in try authorize(p) }) { request, _, _ in
            #expect(request.action == .status && request.allocation == enriched); return .allocated(receipt)
        }
        #expect(replay == enriched)
        #expect(try row(h) == final)
        let held = try await cold.enrichAppPhotoAllocation(p) { _, _ in .held(.cancelled) }
        #expect(held == enriched)
        #expect(try row(h) == final)
        var changed = expected.entries
        let first = changed[0]
        changed[0] = .init(photoOrdinal: first.photoOrdinal, role: first.role, referenceID: first.referenceID, objectID: UUID())
        await #expect(throws: (any Error).self) {
            _ = try await cold.enrichAppPhotoAllocation(p) { _, _ in .allocated(.init(receipt: receipt, entries: changed)) }
        }
        #expect(try row(h) == final)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func freshReservationAndDelayedLegacyReceiptKeepPeerRunway() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture(), receipt = receipt
        let before = try row(h), second = UUID(), draft = UUID()
        let acquisition = try await owner.prepareAppOriginal(packageID: second, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let reserved = try await owner.allocateAppPhoto(p, reserveRoleMapping: true, authorizeCreate: { p, _ in try authorize(p) }) { request, _, _ in
            #expect(request.action == .create && request.allocation.version == 2)
            #expect(request.allocation.remainingAdvances == 2)
            let saved = try allocation(h)
            #expect(saved == request.allocation)
            return .held(.notFound)
        }
        let maximum = try reserved.storageCharge
        let settled = try await owner.allocateAppPhoto(p, authorizeCreate: { p, _ in try authorize(p) }) { request, _, _ in
            #expect(request.action == .status); return .allocated(receipt)
        }
        #expect(settled.version == 2 && settled.remainingAdvances == 1 && settled.roleMapping == nil)
        #expect(try settled.storageCharge <= maximum)
        let context = h.context(), inv = try inventory(h, context)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inv,
            ownerID: h.ownerID, format: .appV2)
        #expect(try #require(budget.metadataByPackage[h.packageID]) >= settled.storageCharge)
        inv.revision = Int64.max - 1; try context.save()
        await #expect(throws: (any Error).self) {
            let edit = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft,
                contexts: [.init(freeText: "A later independent selection must retain enrichment runway")])
            _ = try await owner.saveAppMetadata(edit)
        }
        let expected = try mapping(settled)
        let enriched = try await owner.enrichAppPhotoAllocation(p) { request, _ in
            #expect(request == settled); return .allocated(.init(receipt: receipt, entries: expected.entries))
        }
        #expect(enriched.remainingAdvances == 0)
        #expect(try revision(h) == Int64.max)
        let final = try row(h)
        #expect(final.preparedData == before.preparedData && final.resultData == before.resultData && final.revision == before.revision)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    private var binding: Allocation.BackendBinding {
        .init(generation: UUID(uuidString: "00000000-0000-4000-8000-000000000077")!, configurationDigest: String(repeating: "c", count: 64))
    }

    @Test(arguments: ["v1", "v1Receipt", "v2", "v2Receipt", "v2Mapping"])
    func bindingReservationPreservesLegacyAndRetainsMaximumCharge(_ predecessor: String) throws {
        let fixture = InitialPhotoAllocationRoleReplyTests(), projection = try fixture.projection()
        var legacy = try fixture.request().allocation
        if predecessor.hasPrefix("v2") { legacy = try legacy.reservingRoleMapping() }
        if predecessor.hasSuffix("Receipt") { legacy = try legacy.settling(projection.receipt) }
        if predecessor == "v2Mapping" { legacy = try legacy.enriching(projection.receipt, mapping: .init(entries: projection.entries)) }
        let bytes = try legacy.encoded(), reserved = try legacy.reservingBackendBinding()
        #expect(try Allocation.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)).encoded() == bytes)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(original["backendBinding"] == nil)
        try legacy.requireSuccessor(reserved)
        #expect(reserved.claim == legacy.claim && reserved.receipt == legacy.receipt && reserved.roleMapping == legacy.roleMapping)
        #expect(reserved.remainingAdvances == (legacy.receipt == nil ? 2 : 1))
        let delayed = try reserved.settling(projection.receipt)
        if delayed != reserved { try reserved.requireSuccessor(delayed) }
        #expect(delayed.version == 6 && delayed.remainingAdvances == 1)
        let enriched = try delayed.enriching(projection.receipt, mapping: .init(entries: projection.entries), binding: binding)
        try delayed.requireSuccessor(enriched)
        #expect(enriched.remainingAdvances == 0 && enriched.backendBinding == binding)
        #expect(try enriched.storageCharge == reserved.storageCharge)
        #expect(try enriched.storageCharge >= Int64(enriched.encoded().count) + 64)
        #expect(try enriched.settling(projection.receipt) == enriched)
        #expect(try enriched.enriching(projection.receipt, mapping: .init(entries: projection.entries), binding: binding) == enriched)
        #expect(throws: (any Error).self) { try enriched.requireSuccessor(legacy) }
        #expect(throws: (any Error).self) { _ = try enriched.enriching(projection.receipt, mapping: .init(entries: projection.entries)) }
        #expect(throws: (any Error).self) { _ = try enriched.reservingRemoteAttempt() }
        #expect(throws: (any Error).self) { _ = try enriched.startingTicketRequest() }
    }

    @Test(arguments: [false, true])
    func legacyReceiptAndBoundReplyPreserveFactsInBothOrders(boundFirst: Bool) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture(), receipt = receipt
        let recoveryAuthorization: SharedMediaNativePhotoAllocationAccess.Authorize = { _, _ in
            Issue.record("Recovery requested create authorization"); throw SharedMediaStorageFailure.closed
        }
        do {
            // The owner rejects overlapping dispatch. Exercise both supported
            // response/replay orders through complete retained operations.
            let legacy = try await owner.allocateAppPhoto(p, authorizeCreate: { p, _ in try authorize(p) }) { _, _, _ in .held(.notFound) }
            let reserved = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: recoveryAuthorization) { request, _, _ in
                #expect(request.action == .status && request.allocation.claim == legacy.claim)
                return .held(.notFound)
            }
            #expect(reserved.version == 6 && reserved.remainingAdvances == 2)
            if !boundFirst {
                let delayed = try await owner.allocateAppPhoto(p, authorizeCreate: recoveryAuthorization) { request, _, _ in
                    #expect(request.action == .status && request.allocation.claim == legacy.claim)
                    return .allocated(receipt)
                }
                #expect(delayed.version == 6 && delayed.remainingAdvances == 1 && delayed.backendBinding == nil)
            }
            let enriched = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: recoveryAuthorization) { request, _, _ in
                .allocated(.init(receipt: receipt, entries: try mapping(request.allocation).entries, backendBinding: binding))
            }
            let before = try row(h), savedRevision = try revision(h)
            if boundFirst {
                let delayed = try await owner.allocateAppPhoto(p, authorizeCreate: recoveryAuthorization) { request, _, _ in
                    #expect(request.action == .status && request.allocation.claim == legacy.claim)
                    return .allocated(receipt)
                }
                #expect(delayed == enriched)
                #expect(try row(h) == before && revision(h) == savedRevision)
            }
            #expect(try allocation(h) == enriched && enriched.backendBinding == binding)
            #expect(try enriched.storageCharge == reserved.storageCharge)
            let conflicting = Allocation.Receipt(assignmentDigest: String(repeating: "d", count: 64),
                createdAtMilliseconds: receipt.createdAtMilliseconds, expiresAtMilliseconds: receipt.expiresAtMilliseconds)
            await #expect(throws: (any Error).self) {
                _ = try await owner.allocateAppPhoto(p, authorizeCreate: recoveryAuthorization) { _, _, _ in .allocated(conflicting) }
            }
            #expect(try row(h) == before && revision(h) == savedRevision)
            let entry = try #require(enriched.roleMapping?.entries.first)
            let transfer = try await owner.reserveAppPhotoTransfer(p, selection: entry)
            #expect(transfer.version == 7 && transfer.backendBinding == enriched.backendBinding)
            #expect(transfer.claim == enriched.claim && transfer.receipt == enriched.receipt && transfer.roleMapping == enriched.roleMapping)
            #expect(try revision(h) == savedRevision + 1)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch {
            _ = await owner.invalidateAndAwaitForAccountTransition()
            throw error
        }
    }

    @Test(arguments: ["capacity", "revision", "afterSave"])
    func bindingReservationFailsBeforeDispatchOrRecoversOnlyStatus(_ fault: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let before = try row(h)
        if fault == "revision" {
            let c = h.context(); try inventory(h, c).revision = Int64.max - 2; try c.save()
        }
        var fail = true, calls = 0
        try owner.setMetadataFault({ boundary in
            if fault == "afterSave", boundary == .afterSave, fail { fail = false; throw SharedMediaStorageFailure.unavailable }
        }, availableBytes: fault == "capacity" ? 0 : nil)
        let send: SharedMediaNativePhotoAllocationTransportAccess.RolesSend = { request, _, _ in
            calls += 1; #expect(request.action == .status && request.allocation.version == 6)
            return .held(.notFound)
        }
        if fault == "afterSave" {
            let saved = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { p, _ in try authorize(p) }, send: send)
            #expect(saved.backendBinding == nil && saved.remainingAdvances == 2 && calls == 1)
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { p, _ in try authorize(p) }, send: send)
            }
            #expect(calls == 0)
            #expect(try row(h) == before)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func ambiguousBindingSaveColdRecoveryAndChangedTupleCannotReleaseFacts() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture(), receipt = receipt
        _ = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { p, _ in try authorize(p) }) { _, _, _ in .held(.notFound) }
        var fail = true
        try owner.setMetadataFault { if $0 == .afterSave, fail { fail = false; throw SharedMediaStorageFailure.unavailable } }
        let enriched = try await owner.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { p, _ in try authorize(p) }) { request, _, _ in
            .allocated(.init(receipt: receipt, entries: try mapping(request.allocation).entries, backendBinding: binding))
        }
        let before = try row(h), charge = try enriched.storageCharge
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let replay = try await cold.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { _, _ in
            Issue.record("Cold recovery authorized create"); throw SharedMediaStorageFailure.closed
        }) { request, _, _ in
            #expect(request.action == .status && request.allocation == enriched)
            return .allocated(.init(receipt: receipt, entries: try mapping(request.allocation).entries, backendBinding: binding))
        }
        #expect(replay == enriched)
        #expect(try replay.storageCharge == charge && row(h) == before)
        await #expect(throws: (any Error).self) {
            _ = try await cold.allocateAppPhotoRoles(p, backendBinding: true, authorizeCreate: { p, _ in try authorize(p) }) { request, _, _ in
                .allocated(.init(receipt: receipt, entries: try mapping(request.allocation).entries,
                    backendBinding: .init(generation: UUID(), configurationDigest: binding.configurationDigest)))
            }
        }
        #expect(try row(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

}
