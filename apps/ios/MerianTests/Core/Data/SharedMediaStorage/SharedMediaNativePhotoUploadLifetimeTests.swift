import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@Suite("Sealed photo upload ownership", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativePhotoUploadLifetimeTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Mapping = SharedMediaNativePhotoRoleMapping

    private func row(_ store: Store) throws -> SharedMediaNativeReceivingIntentGraph.Row {
        let id = store.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(store.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(8)
        while !(await predicate()) {
            guard ContinuousClock.now < end else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(arguments: Mapping.Role.allCases)
    func sealedRoleResponseNeverSettlesOrReleases(_ role: Mapping.Role) async throws {
        let (store, owner, prepared, allocation) = try await SharedMediaNativePhotoTransferReadbackTests().fixture(role)
        let before = try row(store), mock = ScopedMockTransport(), session = mock.makeSession()
        defer { session.invalidateAndCancel() }
        mock.register(path: "/photo-upload") { request in
            #expect(request.httpMethod == "PUT" && request.url?.host == "sealed-role.invalid")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: .init(session: session))
        #expect(try await owner.uploadAppPhotoTransfer(prepared, upload: upload) == 201)
        #expect(try row(store) == before)
        await #expect(throws: (any Error).self) { _ = try await owner.uploadAppPhotoTransfer(prepared, upload: upload) }
        #expect(try row(store) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func staleAllocationCannotCreateUploadTask() async throws {
        let (store, owner, prepared, allocation) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let mock = ScopedMockTransport(), session = mock.makeSession()
        defer { session.invalidateAndCancel() }
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: .init(session: session))
        _ = try await owner.reserveAppPhotoRemoteAttempt(prepared)
        let before = try row(store)
        await #expect(throws: (any Error).self) { _ = try await owner.uploadAppPhotoTransfer(prepared, upload: upload) }
        #expect(await session.allTasks.isEmpty)
        #expect(try row(store) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["cancel", "timeout", "account"])
    func terminationRetainsOwnerAndCoordinatorExclusion(_ mode: String) async throws {
        let (store, owner, prepared, allocation) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let before = try row(store), pause = PhotoUploadCompletionPause()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoUploadHangingProtocol.self]
        let session = URLSession(configuration: config)
        defer { pause.release(); session.invalidateAndCancel() }
        let concrete = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: concrete, timeout: mode == "timeout" ? 0.2 : 10)
        var finished = false, drained = false, acquired = false
        let call = Task { defer { finished = true }; return try await owner.uploadAppPhotoTransfer(prepared, upload: upload) }
        try await waitUntil { !(await session.allTasks).isEmpty }
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let contender = Task {
            let held = await coordinator.acquireAll(scanIds: [prepared.queueID.uuidString, prepared.observationID.uuidString])
            acquired = true
            await coordinator.releaseAll(scanIds: held)
        }
        var transition: Task<Bool, Never>?
        if mode == "account" {
            transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
        } else if mode == "cancel" { call.cancel() }
        try await waitUntil { pause.entered }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!finished && !drained && !acquired)
        #expect(try row(store) == before)
        pause.release()
        await #expect(throws: (any Error).self) { _ = try await call.value }
        await contender.value
        let after = try row(store)
        #expect(acquired && finished && after == before)
        if let transition {
            let result = await transition.value
            #expect(result && drained)
        } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test(arguments: ["file", "saved"])
    func postflightFailureJoinsBeforeRejecting(_ fault: String) async throws {
        let (store, owner, prepared, allocation) = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let before = try row(store), mock = ScopedMockTransport(), session = mock.makeSession(), pause = PhotoUploadCompletionPause()
        defer { pause.release(); session.invalidateAndCancel() }
        mock.register(path: "/photo-upload") { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let concrete = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: concrete)
        var finished = false
        let call = Task { defer { finished = true }; return try await owner.uploadAppPhotoTransfer(prepared, upload: upload) }
        try await waitUntil { pause.entered }
        if fault == "file" {
            let reservation = try #require(allocation.transferReservation)
            let file = store.parent.appendingPathComponent("photo/PhotoPreparation")
                .appendingPathComponent(store.ownerID.uuidString.lowercased()).appendingPathComponent(store.packageID.uuidString.lowercased())
                .appendingPathComponent(reservation.assetID.uuidString.lowercased())
            // Out-of-band corruption, not a permitted writer path.
            try Data([0]).write(to: file)
        } else {
            let context = store.context(), id = store.packageID
            let value = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            value.revision += 1; try context.save()
        }
        #expect(!finished)
        pause.release()
        await #expect(throws: (any Error).self) { _ = try await call.value }
        let after = try row(store)
        #expect(after.allocationData == before.allocationData && after.allocationSHA256 == before.allocationSHA256)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

private final class PhotoUploadCompletionPause: Sendable {
    private let reached = OSAllocatedUnfairLock(initialState: false)
    private let semaphore = DispatchSemaphore(value: 0)
    var entered: Bool { reached.withLock { $0 } }
    func wait() {
        reached.withLock { $0 = true }
        _ = semaphore.wait(timeout: .now() + 15)
    }
    func release() { semaphore.signal() }
}
private final class PhotoUploadHangingProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
