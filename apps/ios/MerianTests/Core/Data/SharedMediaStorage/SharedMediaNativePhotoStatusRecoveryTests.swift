import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@Suite("Retained photo status recovery", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativePhotoStatusRecoveryTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Role = SharedMediaNativePhotoRoleMapping.Role
    struct Fixture {
        let store: Store
        let owner: SharedMediaNativeOriginalOwner
        let prepared: SharedMediaNativeReceivingIntent.Prepared
        let allocation: Allocation
    }

    func row(_ store: Store) throws -> SharedMediaNativeReceivingIntentGraph.Row {
        let id = store.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(store.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    func saved(_ store: Store) throws -> Allocation {
        let row = try row(store)
        return try Allocation.decode(#require(row.allocationData), sha256: #require(row.allocationSHA256))
    }
    func statusBytes(_ value: Allocation, state: String?, closed: Bool = false, id: UUID) throws -> Data {
        let receipt = try #require(value.receipt), transfer = try #require(value.transferReservation)
        let created = value.remoteAttempt?.createdAtMilliseconds ?? receipt.createdAtMilliseconds + 99
        let expires = value.remoteAttempt?.capabilityExpiresAtMilliseconds ?? min(receipt.expiresAtMilliseconds, created + 600_000)
        let attempt: Any = state.map { ["attempt_id": id.uuidString.lowercased(), "state": $0,
            "created_at_ms": created, "capability_expires_at_ms": expires, "write_closed": closed] as [String: Any] } ?? NSNull()
        return try JSONSerialization.data(withJSONObject: ["version": 1, "authority": "none",
            "scan_id": value.claim.observationID.uuidString.lowercased(), "assignment_digest": receipt.assignmentDigest,
            "object_id": transfer.selection.objectID.uuidString.lowercased(), "attempt": attempt], options: [.sortedKeys])
    }
    private func fixture(_ phase: Int, role: Role = .source) async throws -> Fixture {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture(role, boundBackend: phase >= 8)
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        do {
            _ = try await owner.reserveAppPhotoRemoteAttempt(prepared)
            if phase == 5 || phase == 9 {
                #expect(try await owner.requestAppPhotoTicketForTesting(prepared) { _, continuation in try continuation.validateConsumed() })
            }
            if phase >= 10 { _ = try await owner.reserveAppPhotoPutStart(prepared) }
            if phase == 11 {
                let unusedSession = ScopedMockTransport().makeSession()
                defer { unusedSession.invalidateAndCancel() }
                let catalog = try InitialPhotoUploadDestination.Catalog([InitialPhotoUploadTicketTests().destination()])
                await #expect(throws: (any Error).self) {
                    _ = try await owner.transferAppPhoto(prepared, catalog: catalog, send: { _, validate in
                        try validate(); throw URLError(.networkConnectionLost)
                    }, makeTask: { Issue.record("Lost response constructed a PUT"); return .init(session: unusedSession) })
                }
            }
            let value = try saved(store)
            #expect(value.version == phase)
            return .init(store: store, owner: owner, prepared: prepared, allocation: value)
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(arguments: [false, true])
    func unreservedStatusCannotDispatch(boundBackend: Bool) async throws {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture(boundBackend: boundBackend)
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        do {
            let before = try row(store)
            let candidates = try await owner.discoverAppReceivedCandidates()
            #expect(candidates.count == 1 && candidates.first?.operationID == prepared.operationID)
            await #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try await owner.recoverAppPhotoTransferStatus(prepared) { _, _ in
                    Issue.record("Unreserved status dispatched"); return Data()
                }
            }
            #expect(try row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [4, 5, 8, 9, 10, 11], Role.allCases)
    func historicalStatusIsExactMonotonicAndColdReplayDoesNotSave(phase: Int, role: Role) async throws {
        let f = try await fixture(phase, role: role), before = try row(f.store)
        var owner = f.owner
        let candidates = try await owner.discoverAppReceivedCandidates()
        #expect(candidates.count == 1 && candidates.first?.operationID == f.prepared.operationID)
        let network = InitialPhotoAllocationTransportTests.Fixture(ownerID: f.prepared.profile.ownerID)
        defer { network.close() }
        let count = OSAllocatedUnfairLock(initialState: 0), id = UUID()
        do {
            var current = f.allocation
            let charge = try current.storageCharge
            for (state, closed) in [(nil, false), ("bound", false), ("may_have_issued", false), ("may_have_issued", true)] as [(String?, Bool)] {
                let bytes = try statusBytes(current, state: state, closed: closed, id: id)
                let body = try InitialPhotoTransferRequest(allocation: current, action: .status).body
                network.mock.register(path: "/initial-photo-transfer") { request in
                    count.withLock { $0 += 1 }
                    #expect(request.httpMethod == "POST" && MockURLProtocol.bodyData(for: request) == body)
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!, bytes)
                }
                if state == nil { try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Null status saved") } } }
                let old = current
                current = try await owner.recoverAppPhotoTransferStatus(f.prepared, send: network.transport.performTransfer)
                try owner.setMetadataFault(nil)
                if state == nil { #expect(current == old) } else { try old.requireSuccessor(current) }
                #expect(current.version == phase && current.claim == f.allocation.claim && current.receipt == f.allocation.receipt)
                let currentCharge = try current.storageCharge
                #expect(current.transferReservation == f.allocation.transferReservation && currentCharge == charge)
                #expect(try saved(f.store) == current)
                #expect(try await owner.discoverAppReceivedCandidates() == candidates)
                let immutable = try row(f.store)
                #expect(immutable.preparedData == before.preparedData && immutable.resultData == before.resultData)
                #expect(await owner.invalidateAndAwaitForAccountTransition())
                owner = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
                #expect(try await owner.discoverAppReceivedCandidates() == candidates)
                try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Unchanged cold status saved") } }
                #expect(try await owner.recoverAppPhotoTransferStatus(f.prepared, send: network.transport.performTransfer) == current)
                #expect(try row(f.store) == immutable)
                try owner.setMetadataFault(nil)
            }
            #expect(count.withLock { $0 } == 8)
            #expect(current.remoteAttempt?.writeClosed == true)
            #expect(throws: (any Error).self) { _ = try current.startingTicketRequest() }
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: ["lost", "malformed", "oversized", "null", "backward", "identity", "clocks", "reopened"])
    func unusableStatusPreservesSavedAttempt(fault: String) async throws {
        let f = try await fixture(11), id = UUID()
        do {
            let initial = try statusBytes(f.allocation, state: "may_have_issued", closed: true, id: id)
            let current = try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { _, validate in try validate(); return initial }
            let before = try row(f.store)
            var object = try #require(JSONSerialization.jsonObject(with: initial) as? [String: Any])
            var attempt = try #require(object["attempt"] as? [String: Any])
            if fault == "backward" { attempt["state"] = "bound"; attempt["write_closed"] = false }
            if fault == "identity" { attempt["attempt_id"] = UUID().uuidString.lowercased() }
            if fault == "clocks" { attempt["created_at_ms"] = 101; attempt["capability_expires_at_ms"] = 600_101 }
            if fault == "reopened" { attempt["write_closed"] = false }
            if fault == "null" { object["attempt"] = NSNull() } else { object["attempt"] = attempt }
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try f.owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Rejected status saved") } }
            await #expect(throws: (any Error).self) {
                _ = try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { request, validate in
                    #expect(request.action == .status); try validate()
                    if fault == "lost" { throw URLError(.networkConnectionLost) }
                    if fault == "malformed" { return Data() }
                    if fault == "oversized" { return Data(repeating: 32, count: 2049) }
                    return bytes
                }
            }
            #expect(try saved(f.store) == current)
            #expect(try row(f.store) == before)
            #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await f.owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: ["owner", "revision", "deletion"])
    func changesAcrossStatusAwaitCannotSave(fault: String) async throws {
        let f = try await fixture(11), bytes = try statusBytes(f.allocation, state: "bound", id: UUID())
        do {
            var saves = 0
            try f.owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
            await #expect(throws: (any Error).self) {
                _ = try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { _, validate in
                    try validate()
                    let context = f.store.context()
                    if fault == "deletion" {
                        let id = f.store.packageID
                        let row = try SharedMediaNativePairPlanGraph.one(context,
                            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                        context.delete(row)
                    } else {
                        let id = f.store.inventoryID
                        let inventory = try SharedMediaNativePairPlanGraph.one(context,
                            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
                        if fault == "owner" { inventory.generation = UUID() } else { inventory.revision += 1 }
                    }
                    try context.save()
                    return bytes
                }
            }
            #expect(saves == 0)
            _ = await f.owner.invalidateAndAwaitForAccountTransition()
        } catch { _ = await f.owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func interruptedObservationRecoversSameFactWithoutAnotherSave(fault: String) async throws {
        let f = try await fixture(11), bytes = try statusBytes(f.allocation, state: "bound", id: UUID())
        do {
            try f.owner.setMetadataFault { boundary in
                if (fault == "beforeSave" && boundary == .beforeSave) || (fault == "afterSave" && boundary == .afterSave)
                    || (fault == "beforeReadback" && boundary == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
            }
            if fault == "afterSave" {
                _ = try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { _, validate in try validate(); return bytes }
            } else {
                await #expect(throws: (any Error).self) {
                    _ = try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { _, validate in try validate(); return bytes }
                }
            }
            try f.owner.setMetadataFault(nil)
            #expect(await f.owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
            do {
                var saves = 0
                try cold.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
                let recovered = try await cold.recoverAppPhotoTransferStatus(f.prepared) { _, validate in try validate(); return bytes }
                #expect(recovered.remoteAttempt?.state == .bound && saves == (fault == "beforeSave" ? 1 : 0))
                let immutable = try row(f.store)
                let repeated = try await cold.recoverAppPhotoTransferStatus(f.prepared) { _, validate in try validate(); return bytes }
                #expect(repeated == recovered)
                #expect(try row(f.store) == immutable)
                #expect(await cold.invalidateAndAwaitForAccountTransition())
            } catch { _ = await cold.invalidateAndAwaitForAccountTransition(); throw error }
        } catch { _ = await f.owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [false, true])
    func cancellationKeepsOwnerUntilStatusSenderDrains(accountTransition: Bool) async throws {
        let f = try await fixture(11), before = try row(f.store), pause = PhotoStatusRecoveryPause()
        let bytes = try statusBytes(f.allocation, state: "bound", id: UUID())
        var returned = false, drained = false
        var transition: Task<Bool, Never>?
        let began = ContinuousClock.now
        let call = Task {
            defer { returned = true }
            return try await f.owner.recoverAppPhotoTransferStatus(f.prepared) { _, validate in
                try validate(); await pause.wait(); return bytes
            }
        }
        do {
            try await waitUntil { pause.entered }
            if accountTransition {
                transition = Task { let result = await f.owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
            } else { call.cancel() }
            try await Task.sleep(for: .milliseconds(30))
            #expect(!returned && !drained)
            pause.release()
            if case .success = await call.result { Issue.record("Cancelled status applied a response") }
            #expect(try row(f.store) == before)
            if let transition { #expect(await transition.value) } else { #expect(await f.owner.invalidateAndAwaitForAccountTransition()) }
        } catch {
            print("Native photo status entry diagnostic elapsed=\(began.duration(to: .now)) entered=\(pause.entered) returned=\(returned)")
            pause.release(); call.cancel(); _ = await call.result
            if let transition { _ = await transition.value } else { _ = await f.owner.invalidateAndAwaitForAccountTransition() }
            throw error
        }
    }
}

@MainActor
private final class PhotoStatusRecoveryPause {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
