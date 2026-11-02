import Foundation
import SwiftData
import Testing
import os
@testable import Merian

@Suite("Durable initial photo allocation", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativePhotoAllocationTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    private var receipt: Allocation.Receipt {
        .init(assignmentDigest: String(repeating: "a", count: 64), createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
    }
    private func authorization(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> IdentificationDispatchAuthorization {
        let admission = try #require(prepared.photoAdmission)
        return .init(recipient: admission.expectedProcessorPermission, validate: {})
    }

    func fixture() async throws -> (Store, SharedMediaNativeOriginalOwner, Intent.Prepared) {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(temporaryStore: true, fenceBootstrap: true)
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(request),
            photoAdmission: .init(authorization: .init(recipient: .gemini, validate: {})))
        _ = try await owner.receiveAppPrepared(p)
        return (h, owner, p)
    }
    private func row(_ h: Store) throws -> Row {
        let id = h.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func allocation(_ h: Store) throws -> Allocation {
        let saved = try row(h)
        return try .decode(#require(saved.allocationData), sha256: #require(saved.allocationSHA256))
    }
    private func revision(_ h: Store) throws -> Int64 {
        try SharedMediaNativeReceivingStagingTests().inventory(h).revision
    }

    @Test func savedBeforeCreateAndNegativeThenPositiveRetainsExactSubmission() async throws {
        let (h, owner, p) = try await fixture(), before = try row(h), initialRevision = try revision(h)
        let expected = receipt
        let held = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, validate, _ in
            try validate()
            #expect(request.action == .create)
            #expect(try allocation(h) == request.allocation)
            #expect(try revision(h) == initialRevision + 1)
            return .held(.notFound)
        }
        #expect(held.receipt == nil)
        let saved = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, validate, _ in
            try validate(); #expect(request.action == .status)
            #expect(request.allocation == held)
            return .allocated(expected)
        }
        #expect(saved.receipt == expected)
        let final = try row(h)
        #expect(final.preparedData == before.preparedData && final.resultData == before.resultData && final.revision == before.revision)
        #expect(try revision(h) == initialRevision + 2)
        for reply in [InitialPhotoAllocationReply.allocated(expected), .held(.expired), .held(.cancelled)] {
            let replay = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
                #expect(request.action == .status); return reply
            }
            #expect(replay == saved)
        }
        #expect(try row(h) == final && revision(h) == initialRevision + 2)
        await #expect(throws: (any Error).self) { _ = try await owner.appReleaseStageRequest(p, releaseID: UUID()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func lostCreateAndColdRestartUseStatusOnly() async throws {
        let (h, owner, p) = try await fixture()
        await #expect(throws: SharedMediaStorageFailure.unavailable) {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
                #expect(request.action == .create)
                throw SharedMediaStorageFailure.unavailable
            }
        }
        let held = try allocation(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let expected = receipt
        let saved = try await cold.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, validate, _ in
            try validate(); #expect(request.action == .status && request.allocation == held)
            return .allocated(expected)
        }
        #expect(saved.receipt == expected)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func ambiguousClaimAcknowledgementCannotMintCreate() async throws {
        let (h, owner, p) = try await fixture()
        var fail = true
        try owner.setMetadataFault { if $0 == .afterSave && fail { fail = false; throw SharedMediaStorageFailure.unavailable } }
        let saved = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, validate, _ in
            try validate(); #expect(request.action == .status)
            #expect(try allocation(h) == request.allocation)
            return .held(.notFound)
        }
        #expect(saved.receipt == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func conflictingAssignmentNeverOverwritesReceipt() async throws {
        let (h, owner, p) = try await fixture(), expected = receipt
        _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .allocated(expected) }
        let before = try row(h), rev = try revision(h)
        await #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in
                .allocated(.init(assignmentDigest: String(repeating: "b", count: 64), createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001))
            }
        }
        #expect(try row(h) == before && revision(h) == rev)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func envelopeAndReceiptBoundsAreExact() async throws {
        let (h, owner, p) = try await fixture()
        let held = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        let encoded = try held.encoded(), settled = try held.settling(receipt)
        #expect(try Allocation.decode(encoded, sha256: SharedMediaAcquisitionEncoding.digest(encoded)) == held)
        #expect(try held.storageCharge >= settled.storageCharge)
        #expect(throws: (any Error).self) { _ = try held.settling(.init(assignmentDigest: receipt.assignmentDigest,
            createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_002)) }
        let request = try InitialPhotoAllocationRequest(allocation: held, action: .status)
        let claim = held.claim
        let fields: [String: Any] = ["version": 1, "variant": "client_prepared_photo", "authority": "none",
            "scan_id": claim.observationID.uuidString.lowercased(), "package_id": claim.packageID.uuidString.lowercased(),
            "candidate_digest": claim.candidateDigest, "content_digest": claim.contentDigest, "outcome": "allocated",
            "assignment_digest": receipt.assignmentDigest, "created_at_ms": 1, "expires_at_ms": 1_800_001]
        #expect(try InitialPhotoAllocationReply(data: JSONSerialization.data(withJSONObject: fields), request: request) == .allocated(receipt))
        for mutation: [String: Any] in [["version": true], ["created_at_ms": 1.5], ["authority": "execute"],
            ["expires_at_ms": 1_800_002], ["private_configuration": "forbidden"], ["candidate_digest": String(repeating: "b", count: 64)]] {
            let invalid = fields.merging(mutation) { _, new in new }
            #expect(throws: (any Error).self) { _ = try InitialPhotoAllocationReply(data: JSONSerialization.data(withJSONObject: invalid), request: request) }
        }
        #expect(try allocation(h) == held)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func aggregateRevisionExhaustionStopsBeforeClaimAndSend() async throws {
        let (h, owner, p) = try await fixture()
        let context = h.context(), id = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        inventory.revision = Int64.max - 1; try context.save()
        let before = try row(h)
        await #expect(throws: (any Error).self) {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in
                Issue.record("Revision exhaustion sent a request"); return .held(.notFound)
            }
        }
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func escapedCandidateMustFitActualEnvelopeAndPositiveReservation() async throws {
        let (h, owner, p) = try await fixture()
        let saved = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        let fixture = SharedMediaNativeReceivingTestFixture.self
        var claim = try fixture.object(saved.claim)
        claim["candidateCanonical"] = String(repeating: "\"", count: 600_000)
        let oversized = try fixture.copy(saved, changes: ["claim": claim])
        #expect(throws: (any Error).self) { _ = try oversized.encoded() }
        #expect(throws: (any Error).self) { _ = try InitialPhotoAllocationRequest(allocation: oversized, action: .create) }
        #expect(try allocation(h) == saved)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [200, 401, 409, 429, 503])
    func actualBoundedAuthenticatedAdapterUsesSavedClaimAndNeverRetries(status: Int) async throws {
        let (h, owner, p) = try await fixture()
        let mock = ScopedMockTransport(), pinned = PinnedNetworkTransport(), session = mock.makeSession()
        pinned.overridingSession = session
        defer { session.invalidateAndCancel() }
        let dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
        dispatcher.overridingAuthUserID = h.ownerID
        dispatcher.overridingAuthSessionRefresh = { Issue.record("Allocation refreshed authentication"); return true }
        let transport = InitialPhotoAllocationTransport(baseURL: "https://example.supabase.co", dispatcher: dispatcher)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let candidate = try SharedMediaNativePhotoCandidate(prepared: p), content = try SharedMediaNativePhotoContent(prepared: p)
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "variant": "client_prepared_photo", "authority": "none",
            "scan_id": p.observationID.uuidString.lowercased(), "package_id": p.package.id.uuidString.lowercased(),
            "candidate_digest": candidate.unverifiedDigest, "content_digest": content.unverifiedDigest,
            "outcome": "terminal_held", "reason": "not_found"])
        mock.register(path: "/initial-photo-allocation") { wire in
            calls.withLock { $0 += 1 }
            #expect(wire.timeoutInterval == 5 && wire.httpMethod == "POST")
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            let body = try #require(MockURLProtocol.bodyData(for: wire))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["action"] as? String == "create")
            #expect(payload["candidate_canonical"] as? String == String(decoding: candidate.canonicalBytes, as: UTF8.self))
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        if status == 200 {
            #expect(try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }, transport: transport).receipt == nil)
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }, transport: transport) }
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(try allocation(h).receipt == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func transportCancellationAndAccountTeardownDrainAndKeepStatusOnly(shutdown: Bool) async throws {
        let (h, owner, p) = try await fixture(), gate = Gate(), expected = receipt
        let task = Task { try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
            #expect(request.action == .create)
            await gate.pause()
            return .allocated(expected) // Intentionally ignores cancellation to exercise late completion.
        } }
        await gate.arrived()
        let unresolved = try allocation(h)
        await #expect(throws: PhotoPreparationFailure.busy) {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in
                Issue.record("Overlapping allocation dispatched"); return .held(.notFound)
            }
        }
        var drained = false
        let closing: Task<Bool, Never>?
        if shutdown {
            closing = Task { let value = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return value }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
            #expect(!drained)
        } else { closing = nil; task.cancel() }
        gate.release()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        if let closing { #expect(await closing.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        #expect(try allocation(h) == unresolved)
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, validate, _ in
            try validate(); #expect(request.action == .status && request.allocation == unresolved)
            return .allocated(expected)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["after", "readback"])
    func ambiguousPositiveSettlementRecoversExactReceipt(fault: String) async throws {
        let (h, owner, p) = try await fixture(), expected = receipt
        _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        var saved = false
        try owner.setMetadataFault {
            if $0 == .afterSave { saved = true; if fault == "after" { throw SharedMediaStorageFailure.unavailable } }
            if saved && $0 == .beforeReadback && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "after" {
            let recovered = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
                #expect(request.action == .status); return .allocated(expected)
            }
            #expect(recovered.receipt == expected)
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
                    #expect(request.action == .status); return .allocated(expected)
                }
            }
        }
        #expect(try allocation(h).receipt == expected)
        let before = try row(h), rev = try revision(h)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Exact receipt replay saved again") } }
        let replay = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
            #expect(request.action == .status); return .allocated(expected)
        }
        #expect(replay.receipt == expected)
        #expect(try row(h) == before && revision(h) == rev)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func sidecarSealRejectsExtraDirtyRowAndPreservesImmutableBytes() async throws {
        let (h, owner, p) = try await fixture()
        let unresolved = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        let before = try row(h), context = h.context(), id = h.packageID, inventoryID = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let slot = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let package = try h.package(in: context), after = try unresolved.settling(receipt)
        let seal = try SharedMediaNativePhotoAllocationPoststate(row: slot, inventory: inventory, after: after, prepared: p, context: context)
        slot.allocationData = try after.encoded()
        slot.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(slot.allocationData!)
        inventory.revision += 1
        try seal.validate(context, row: slot, inventory: inventory)
        package.revision += 1
        #expect(throws: SharedMediaStorageFailure.conflict) { try seal.validate(context, row: slot, inventory: inventory) }
        context.rollback()
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func allocationSealPinsExactPresentationAcrossFreshPreSaveRead() async throws {
        let (h, owner, prepared) = try await fixture()
        let unresolved = try await owner.allocateAppPhoto(prepared, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let queueID = prepared.queueID.uuidString.lowercased(), packageID = h.packageID, inventoryID = h.inventoryID
        func queue(_ c: ModelContext) throws -> OfflineQueuedScan {
            try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        }
        func inventory(_ c: ModelContext) throws -> SharedMediaInventoryRecord {
            try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        }
        func slot(_ c: ModelContext) throws -> SharedMediaReceivingIntentRecord {
            try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        }
        let initial = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: prepared.profile.ownerID,
            observationID: prepared.observationID, operationID: prepared.operationID))
        let first = try initial.reserve(id: UUID()).reserved.encoded(), second = try initial.reserve(id: UUID()).reserved.encoded()
        #expect(first.count == second.count && first != second)
        let changes: [(Data?, Data?)] = [(nil, first), (first, second), (first, nil)]
        for (before, afterBytes) in changes {
            let seed = h.context(); try queue(seed).recoveryPresentationData = before; try seed.save()
            let c = h.context(), r = try slot(c), i = try inventory(c), after = try unresolved.settling(receipt)
            let seal = try SharedMediaNativePhotoAllocationPoststate(row: r, inventory: i, after: after, prepared: prepared, context: c)
            let unchanged = h.context()
            try seal.requirePredecessor(row: slot(unchanged), inventory: inventory(unchanged), context: unchanged)
            r.allocationData = try after.encoded(); r.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(r.allocationData!)
            i.revision += 1; try seal.validate(c, row: r, inventory: i)
            try queue(c).recoveryPresentationData = afterBytes
            #expect(throws: (any Error).self) { try seal.validate(c, row: r, inventory: i) }
            c.rollback()
            // Out-of-band same-header drift: fresh budget success must not
            // silently replace the presentation predecessor captured by the seal.
            let external = h.context(); try queue(external).recoveryPresentationData = afterBytes; try external.save()
            let fresh = h.context()
            #expect(throws: SharedMediaStorageFailure.stale) {
                try seal.requirePredecessor(row: slot(fresh), inventory: inventory(fresh), context: fresh)
            }
        }
    }

    @Test(arguments: [false, true])
    func changedClaimOrDeletedSlotCannotAcceptLateResponse(deleted: Bool) async throws {
        let (h, owner, p) = try await fixture(), expected = receipt
        await #expect(throws: (any Error).self) {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
                let context = h.context(), id = h.packageID
                let slot = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                if deleted { context.delete(slot) }
                else {
                    var claim = try SharedMediaNativeReceivingTestFixture.object(request.allocation.claim)
                    claim["attemptID"] = UUID().uuidString
                    let changed = try SharedMediaNativeReceivingTestFixture.copy(request.allocation, changes: ["claim": claim])
                    slot.allocationData = try changed.encoded()
                    slot.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(slot.allocationData!)
                }
                try context.save()
                return .allocated(expected)
            }
        }
        if !deleted { #expect(try allocation(h).receipt == nil) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func anotherPackageCannotSpendUnresolvedRevisionOrMetadataReservation() async throws {
        let (h, owner, p) = try await fixture(), second = UUID(), draft = UUID()
        let request = try await owner.prepareAppOriginal(packageID: second, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(request) { image }
        let before = try budget(h)
        let held = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        let after = try budget(h)
        #expect(after.metadataByPackage[second] == before.metadataByPackage[second])
        let charged = try #require(after.metadataByPackage[h.packageID]), previous = try #require(before.metadataByPackage[h.packageID])
        #expect(try charged == previous + held.storageCharge)
        // A capacity rejection must not hide a blanket ban on unrelated drafts.
        let allocationRow = try row(h), allocationRevision = try revision(h)
        let edit = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft,
            contexts: [.init(freeText: "A later independent selection")])
        _ = try await owner.saveAppMetadata(edit)
        let edited = try budget(h)
        #expect(try row(h) == allocationRow && allocation(h) == held)
        #expect(try revision(h) == allocationRevision + 1)
        #expect(edited.metadataByPackage[h.packageID] == charged)
        #expect(try #require(edited.metadataByPackage[second]) > #require(after.metadataByPackage[second]))
        let newRequest = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        _ = try await owner.acquireAppOriginal(newRequest) { image }
        #expect(try row(h) == allocationRow && allocation(h) == held)
        #expect(try budget(h).metadataByPackage[h.packageID] == charged)
        let context = h.context(), inventoryID = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        inventory.revision = Int64.max - 1; try context.save()
        let saved = try row(h)
        await #expect(throws: SharedMediaStorageFailure.invalid) {
            let edit = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft, contexts: [.init(freeText: "later edit")])
            _ = try await owner.saveAppMetadata(edit)
        }
        #expect(try row(h) == saved && revision(h) == Int64.max - 1)
        let expected = receipt
        _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
            #expect(request.action == .status); return .allocated(expected)
        }
        #expect(try revision(h) == Int64.max)
        #expect(try budget(h).metadataByPackage[second] == edited.metadataByPackage[second])
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["slot", "consumer", "removed", "inserted", "membership", "receivedQueue"])
    func changedAllocationPeerCannotCommitAnIndependentEdit(target: String) async throws {
        let (h, owner, p) = try await fixture(), second = UUID(), draft = UUID()
        let acquisition = try await owner.prepareAppOriginal(packageID: second, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { _, _, _ in .held(.notFound) }
        let before = try h.package(second).supportingContextData
        let edit = try await owner.prepareAppMetadata(packageID: second, draftGeneration: draft,
            contexts: [.init(freeText: "Must not commit across changed peer")])
        var reachedSave = false
        try owner.setMetadataFault { boundary in
            guard boundary == .beforeSave else { return }
            reachedSave = true
            let context = h.context(), id = h.packageID
            let slot = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            switch target {
            case "slot":
                slot.allocationSHA256 = String(repeating: "b", count: 64)
            case "consumer":
                let consumer = try #require(try SharedMediaConsumerLookup.one(context, packageID: id))
                consumer.cohortSHA256 = String(repeating: "b", count: 64)
            case "removed":
                context.delete(slot)
            case "inserted":
                // A newly inserted sidecar cannot borrow the validated peer's
                // bytes to enter the baseline during another package's save.
                let inserted = SharedMediaReceivingIntentRecord(packageID: second,
                    inventoryID: slot.inventoryID, inventoryGeneration: slot.inventoryGeneration,
                    ownerID: slot.ownerID, draftGeneration: draft, operationID: UUID(),
                    preparedData: try #require(slot.preparedData), preparedSHA256: slot.preparedSHA256)
                inserted.allocationData = slot.allocationData; inserted.allocationSHA256 = slot.allocationSHA256
                context.insert(inserted)
            case "membership":
                let member = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                member.revision += 1
            case "receivedQueue":
                let queueID = p.queueID.uuidString.lowercased()
                let queue = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
                queue.queueNeedsAttention = false
            default:
                Issue.record("Unknown peer mutation")
            }
            try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(edit) }
        #expect(reachedSave)
        #expect(try h.package(second).supportingContextData == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["stream", "timeout", "redirect"])
    func authenticatedAdapterBoundsResponseAndLeavesClaimRecoverable(kind: String) async throws {
        let (h, owner, p) = try await fixture()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoAllocationBoundaryProtocol.self]
        config.httpAdditionalHeaders = ["X-Merian-Test-Boundary": kind]
        let session = URLSession(configuration: config), pinned = PinnedNetworkTransport()
        pinned.overridingSession = session
        defer { session.invalidateAndCancel() }
        let dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
        dispatcher.overridingAuthUserID = h.ownerID
        dispatcher.overridingAuthSessionRefresh = { Issue.record("Boundary failure refreshed authentication"); return true }
        let transport = InitialPhotoAllocationTransport(baseURL: "https://example.supabase.co", dispatcher: dispatcher)
        await #expect(throws: (any Error).self) { _ = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }, transport: transport) }
        let saved = try allocation(h)
        #expect(saved.receipt == nil)
        let recovered = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try self.authorization(value) }) { request, _, _ in
            #expect(request.action == .status && request.allocation == saved)
            return .held(.notFound)
        }
        #expect(recovered == saved)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func budget(_ h: Store) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        let context = h.context(), id = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: h.ownerID, format: .appV2)
    }

    @MainActor private final class Gate {
        private var entered = false
        private var waiting: CheckedContinuation<Void, Never>?, arrival: CheckedContinuation<Void, Never>?
        func pause() async {
            entered = true; arrival?.resume(); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func arrived() async { if !entered { await withCheckedContinuation { arrival = $0 } } }
        func release() { waiting?.resume(); waiting = nil }
    }

}

private final class PhotoAllocationBoundaryProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "example.supabase.co" else {
            Issue.record("Allocation followed a redirect")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let kind = request.value(forHTTPHeaderField: "X-Merian-Test-Boundary")
        if kind == "timeout" { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: kind == "redirect" ? 302 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json", "Location": "https://other.example/forbidden"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 1024))
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 1025))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
