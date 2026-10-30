import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Durable photo ticket request boundary", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativePhotoTicketRequestTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Mapping = SharedMediaNativePhotoRoleMapping

    private func saved(_ store: Store) throws -> Allocation {
        let id = store.packageID
        let row = try SharedMediaNativePairPlanGraph.one(store.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let data = try #require(row.allocationData), digest = try #require(row.allocationSHA256)
        return try Allocation.decode(data, sha256: digest)
    }
    private func status(_ allocation: Allocation, state: String?, closed: Bool = false, id: UUID) throws -> InitialPhotoUploadStatus {
        let receipt = try #require(allocation.receipt), transfer = try #require(allocation.transferReservation)
        let attempt: Any = state.map { ["attempt_id": id.uuidString.lowercased(), "state": $0,
            "created_at_ms": 100, "capability_expires_at_ms": 600_100, "write_closed": closed] as [String: Any] } ?? NSNull()
        let wire: [String: Any] = ["version": 1, "authority": "none", "scan_id": allocation.claim.observationID.uuidString.lowercased(),
            "assignment_digest": receipt.assignmentDigest, "object_id": transfer.selection.objectID.uuidString.lowercased(), "attempt": attempt]
        return try InitialPhotoUploadStatus(data: JSONSerialization.data(withJSONObject: wire), allocation: allocation,
            objectID: transfer.selection.objectID)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(8)
        while !predicate() {
            guard ContinuousClock.now < end else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(arguments: Mapping.Role.allCases)
    func freshOnceAndColdRecoveryNeverReconstructPermission(_ role: Mapping.Role) async throws {
        let (h, owner, p, v3) = try await SharedMediaNativePhotoTransferReadbackTests().fixture(role)
        let v4 = try await owner.reserveAppPhotoRemoteAttempt(p)
        #expect(try !SharedMediaNativeReceivingTestFixture.object(v4).keys.contains("ticketRequestStarted"))
        var escaped: SharedMediaNativePhotoTicketContinuation?
        let requested = try await owner.requestAppPhotoTicketForTesting(p) { allocation, continuation in
            escaped = continuation
            #expect(try self.saved(h) == allocation)
            #expect(allocation.version == 5 && allocation.ticketRequestStarted == true && allocation.remainingAdvances == 3)
            #expect(allocation.transferReservation == v3.transferReservation && allocation.remoteAttempt == nil)
            #expect(throws: SharedMediaStorageFailure.closed) { try continuation.consume() }
            try continuation.validateConsumed()
        }
        #expect(requested)
        let continuation = try #require(escaped)
        #expect(throws: SharedMediaStorageFailure.closed) { try continuation.validateConsumed() }
        let held = try saved(h)
        #expect(try held.storageCharge > v4.storageCharge)
        #expect(try await owner.reserveAppPhotoRemoteAttempt(p) == held)
        #expect(try await !owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Repeated fresh request") })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await !cold.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Recovered fresh request") })
        #expect(try saved(h) == held)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["afterSave", "readback", "beforeSave", "capacity", "generation"])
    func failedAcknowledgementNeverInvokesRequest(_ fault: String) async throws {
        let (h, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let v4 = try await owner.reserveAppPhotoRemoteAttempt(p)
        var didSave = false, calls = 0
        try owner.setMetadataFault({ boundary in
            if boundary == .afterSave {
                didSave = true
                if fault == "afterSave" { throw SharedMediaStorageFailure.unavailable }
                if fault == "generation" {
                    let c = h.context(), id = h.inventoryID
                    let inventory = try SharedMediaNativePairPlanGraph.one(c,
                        FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
                    inventory.revision += 1; try c.save()
                }
            }
            if boundary == .beforeReadback && didSave && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
            if boundary == .beforeSave && fault == "beforeSave" { throw CancellationError() }
        }, availableBytes: fault == "capacity" ? 0 : nil)
        if fault == "afterSave" {
            #expect(try await !owner.requestAppPhotoTicketForTesting(p) { _, _ in calls += 1 })
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.requestAppPhotoTicketForTesting(p) { _, _ in calls += 1 } }
        }
        #expect(calls == 0)
        try owner.setMetadataFault(nil)
        let held = try saved(h)
        if didSave {
            #expect(held.version == 5 && held.ticketRequestStarted == true)
            #expect(try await !owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Ambiguous retry") })
        } else { #expect(held == v4) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func markerAndThreeStatusSavesRetainMaximumCharge() async throws {
        let (h, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let v4 = try await owner.reserveAppPhotoRemoteAttempt(p)
        let other = UUID(), draft = UUID(), image = PhotoPreparationTestHarness.image()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: draft, ordinal: 0, kind: .picker)
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let c = h.context(), inventoryID = h.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        inventory.revision = Int64.max - 3; try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("No marker runway") } }
        #expect(try saved(h) == v4)
        inventory.revision = Int64.max - 4; try c.save()
        #expect(try await owner.requestAppPhotoTicketForTesting(p) { _, _ in })
        var current = try saved(h)
        let maximum = try current.storageCharge, attemptID = UUID()
        await #expect(throws: (any Error).self) {
            let edit = try await owner.prepareAppMetadata(packageID: other, draftGeneration: draft, contexts: [.init(freeText: "later selection")])
            _ = try await owner.saveAppMetadata(edit)
        }
        current = try await owner.observeAppPhotoRemoteAttempt(p, allocation: current, status: status(current, state: nil, id: attemptID))
        #expect(try await !owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Absent status granted a retry") })
        for (state, closed) in [("bound", false), ("may_have_issued", false), ("may_have_issued", true)] {
            current = try await owner.observeAppPhotoRemoteAttempt(p, allocation: current, status: status(current, state: state, closed: closed, id: attemptID))
            #expect(current.version == 5 && current.ticketRequestStarted == true)
            #expect(try current.storageCharge == maximum)
        }
        #expect(current.remainingAdvances == 0 && current.transferReservation == v4.transferReservation)
        #expect(throws: (any Error).self) { try current.requireSuccessor(v4) }
        #expect(throws: (any Error).self) { _ = try current.startingTicketRequest() }
        #expect(try SharedMediaNativePairPlanGraph.one(h.context(), FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })).revision == Int64.max)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["legacy", "false", "null", "missing"])
    func malformedMarkerIsRejected(_ fault: String) async throws {
        let (_, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let v4 = try await owner.reserveAppPhotoRemoteAttempt(p), v5 = try v4.startingTicketRequest()
        var object = try SharedMediaNativeReceivingTestFixture.object(v5)
        switch fault {
        case "legacy": object["version"] = 4
        case "false": object["ticketRequestStarted"] = false
        case "null": object["ticketRequestStarted"] = NSNull()
        default: object.removeValue(forKey: "ticketRequestStarted")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) { _ = try Allocation.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["bound", "may_have_issued", "closed"])
    func historicalRemoteFactCannotStartFreshRequest(_ state: String) async throws {
        let (h, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let v4 = try await owner.reserveAppPhotoRemoteAttempt(p)
        let held = try await owner.observeAppPhotoRemoteAttempt(p, allocation: v4,
            status: status(v4, state: state == "bound" ? "bound" : "may_have_issued", closed: state == "closed", id: UUID()))
        #expect(try await !owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Historical fact authorized fresh request") })
        #expect(try saved(h) == held)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func simultaneousReservationsInvokeOnlyOneRequest() async throws {
        let (_, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        _ = try await owner.reserveAppPhotoRemoteAttempt(p)
        let pause = PhotoTicketRequestPause()
        var calls = 0
        let first = Task {
            defer { pause.finishWaiting() }
            return try await owner.requestAppPhotoTicketForTesting(p) { _, _ in
                calls += 1
                await pause.wait()
            }
        }
        var second: Task<Bool, Error>?
        do {
            try await pause.waitForEntry()
            let next = Task { try await owner.requestAppPhotoTicketForTesting(p) { _, _ in calls += 1 } }
            second = next
            await Task.yield()
            pause.release()
            #expect(try await first.value)
            #expect(try await !next.value)
            #expect(calls == 1)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch {
            pause.release(); first.cancel(); second?.cancel()
            _ = await first.result
            if let second { _ = await second.result }
            _ = await owner.invalidateAndAwaitForAccountTransition()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func pausedRequestRetainsOperationAndRejectsLateCompletion(_ accountTransition: Bool) async throws {
        let (h, owner, p, _) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        _ = try await owner.reserveAppPhotoRemoteAttempt(p)
        let pause = PhotoTicketRequestPause()
        var finished = false, drained = false, contenderEntered = false
        let call = Task {
            defer { finished = true; pause.finishWaiting() }
            return try await owner.requestAppPhotoTicketForTesting(p) { _, _ in await pause.wait() }
        }
        var contender: Task<Void, Never>?
        var transition: Task<Bool, Never>?
        do {
            try await pause.waitForEntry()
            let held = try saved(h)
            contender = Task {
                let coordinator = ScanInferencePersistenceCoordinator.shared
                let locks = await coordinator.acquireAll(scanIds: [p.queueID.uuidString, p.observationID.uuidString])
                contenderEntered = true
                await coordinator.releaseAll(scanIds: locks)
            }
            if accountTransition {
                transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
                try await waitUntil { owner.heldOriginalAdmissionClosedForTesting }
            } else { call.cancel() }
            try await Task.sleep(for: .milliseconds(30))
            #expect(!finished && !drained && !contenderEntered)
            pause.release()
            await #expect(throws: (any Error).self) { _ = try await call.value }
            await contender?.value
            #expect(try saved(h) == held)
            if let transition { #expect(await transition.value) } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            #expect(try await !cold.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Late result resurrected request") })
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        } catch {
            pause.release(); call.cancel()
            _ = await call.result
            await contender?.value
            if let transition { _ = await transition.value } else { _ = await owner.invalidateAndAwaitForAccountTransition() }
            throw error
        }
    }
}

/// Coordinates actual callback entry, excluding durable preparation from the
/// test's cancellation assertions. The runner retains its test deadline.
@MainActor
private final class PhotoTicketRequestPause {
    private let entry: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        entry = pair.stream; signal = pair.continuation
    }
    func waitForEntry() async throws {
        for await _ in entry { return }
        throw URLError(.cannotLoadFromNetwork)
    }
    func wait() async {
        signal.yield(()); signal.finish()
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func finishWaiting() { signal.finish() }
    func release() {
        released = true
        continuation?.resume(); continuation = nil
    }
}
