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

    private struct PutFixture {
        let store: Store
        let owner: SharedMediaNativeOriginalOwner
        let prepared: SharedMediaNativeReceivingIntent.Prepared
        let reserved: SharedMediaNativePhotoAllocation
    }
    private func putFixture(_ role: Mapping.Role = .source, nearExpiry: Bool = false) async throws -> PutFixture {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture(role,
            boundBackend: true, receiptClock: { Int64(Date().timeIntervalSince1970 * 1000) - (nearExpiry ? 900_000 : 1_000) })
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        _ = try await owner.reserveAppPhotoRemoteAttempt(prepared)
        return .init(store: store, owner: owner, prepared: prepared, reserved: try await owner.reserveAppPhotoPutStart(prepared))
    }

    @Test(arguments: Mapping.Role.allCases, [201, 503])
    func freshTicketRequiresDurablePutAndNeverRepeats(_ role: Mapping.Role, status: Int) async throws {
        let context = try await putFixture(role), store = context.store, owner = context.owner, prepared = context.prepared, reserved = context.reserved
        let fixture = InitialPhotoUploadTicketTests(), catalog = try InitialPhotoUploadDestination.Catalog([fixture.destination()])
        let issued = try reserved.startingTicketRequest(), wire = try fixture.row(issued)
        let decoded = try InitialPhotoUploadTicket(data: fixture.bytes(wire), allocation: issued,
            destination: fixture.destination(), nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
        let expected = try issued.startingPut(#require(decoded.issuedAttempt)), expectedBytes = try expected.encoded()
        let mock = ScopedMockTransport(), session = mock.makeSession()
        defer { session.invalidateAndCancel() }
        let address = try #require(wire["url"] as? String), path = try #require(URL(string: address)?.path)
        let puts = OSAllocatedUnfairLock(initialState: 0)
        mock.register(path: path) { request in
            puts.withLock { $0 += 1 }
            #expect(request.httpMethod == "PUT" && request.value(forHTTPHeaderField: "If-None-Match") == "*")
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)), Data())
        }
        let transportFixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: issued.claim.profile.ownerID)
        defer { transportFixture.close() }
        let ticketBytes = try fixture.bytes(wire)
        transportFixture.mock.register(path: "/initial-photo-transfer") { request in
            #expect(request.httpMethod == "POST")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, ticketBytes)
        }
        var sends = 0, constructions = 0
        let result = try await owner.transferAppPhoto(prepared, catalog: catalog, send: { request, validate in
            sends += 1
            #expect(request.allocation == issued)
            return try await transportFixture.transport.performTransfer(request, validateAttempt: validate)
        }, makeTask: {
            constructions += 1
            // Construction is downstream of acknowledged durable V12, not just an in-memory proposal.
            do { #expect(try self.row(store).allocationData == expectedBytes) } catch { Issue.record(error) }
            return .init(session: session)
        })
        #expect(result == status && sends == 1 && constructions == 1 && puts.withLock { $0 } == 1)
        let retained = try row(store)
        #expect(retained.allocationData == expectedBytes)
        let read = try await owner.verifyAppPhotoTransfer(prepared, allocation: expected)
        #expect(read.selection == expected.transferReservation?.selection && read.sha256 == expected.transferReservation?.sha256)
        #expect(try await owner.transferAppPhoto(prepared, catalog: catalog, send: { _, _ in
            Issue.record("Repeated ticket request"); return Data()
        }, makeTask: { Issue.record("Repeated PUT"); return .init(session: session) }) == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        #expect(try await cold.transferAppPhoto(prepared, catalog: catalog, send: { _, _ in
            Issue.record("Cold request recreated authority"); return Data()
        }, makeTask: { Issue.record("Cold PUT recreated authority"); return .init(session: session) }) == nil)
        #expect(try row(store) == retained)
        let candidates = try await cold.discoverAppReceivedCandidates()
        #expect(candidates.count == 1 && candidates.first?.operationID == prepared.operationID)
        let attempt = try #require(expected.remoteAttempt)
        let closedBytes = try NativePhotoStatusRecoveryTests().statusBytes(expected, state: "may_have_issued", closed: true, id: attempt.id)
        let statusBody = try InitialPhotoTransferRequest(allocation: expected, action: .status).body
        transportFixture.mock.register(path: "/initial-photo-transfer") { request in
            #expect(MockURLProtocol.bodyData(for: request) == statusBody)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, closedBytes)
        }
        let closed = try await cold.recoverAppPhotoTransferStatus(prepared, send: transportFixture.transport.performTransfer)
        #expect(closed.version == 12 && closed.remoteAttempt?.writeClosed == true)
        #expect(closed.remoteAttempt?.id == attempt.id && closed.remoteAttempt?.createdAtMilliseconds == attempt.createdAtMilliseconds)
        let closedCharge = try closed.storageCharge, expectedCharge = try expected.storageCharge
        #expect(closed.transferReservation == expected.transferReservation && closedCharge == expectedCharge)
        #expect(try await cold.discoverAppReceivedCandidates() == candidates)
        let closedRow = try row(store)
        try cold.setMetadataFault { if $0 == .beforeSave { Issue.record("Closed status replay saved") } }
        #expect(try await cold.recoverAppPhotoTransferStatus(prepared, send: transportFixture.transport.performTransfer) == closed)
        #expect(try row(store) == closedRow)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave"], [1, 2])
    func ambiguousTicketOrPutSaveCannotConstructUpload(_ fault: String, save: Int) async throws {
        let context = try await putFixture(), store = context.store, owner = context.owner, prepared = context.prepared, reserved = context.reserved
        let fixture = InitialPhotoUploadTicketTests(), catalog = try InitialPhotoUploadDestination.Catalog([fixture.destination()])
        let session = ScopedMockTransport().makeSession()
        defer { session.invalidateAndCancel() }
        var saves = 0, sends = 0, constructions = 0
        try owner.setMetadataFault { boundary in
            if boundary == .beforeSave { saves += 1 }
            if saves == save && ((fault == "beforeSave" && boundary == .beforeSave) || (fault == "afterSave" && boundary == .afterSave)) {
                throw SharedMediaStorageFailure.unavailable
            }
        }
        do {
            let result = try await owner.transferAppPhoto(prepared, catalog: catalog, send: { request, validate in
                sends += 1; try validate(); return try fixture.bytes(fixture.row(request.allocation))
            }, makeTask: { constructions += 1; return .init(session: session) })
            #expect(fault == "afterSave" && result == nil)
        } catch { #expect(fault == "beforeSave") }
        try owner.setMetadataFault(nil)
        #expect(constructions == 0 && sends == save - 1)
        #expect(await session.allTasks.isEmpty)
        let retained = try row(store)
        if save == 1 && fault == "beforeSave" { #expect(try retained.allocationData == reserved.encoded()) } else {
            #expect(try await owner.transferAppPhoto(prepared, catalog: catalog, send: { _, _ in
                Issue.record("Ambiguous state retried"); return Data()
            }, makeTask: { Issue.record("Ambiguous state minted PUT"); return .init(session: session) }) == nil)
            #expect(try row(store) == retained)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["held", "malformed", "cancel"])
    func unusableTicketRetainsMarkerWithoutPut(_ mode: String) async throws {
        let context = try await putFixture(), store = context.store, owner = context.owner, prepared = context.prepared, reserved = context.reserved
        let fixture = InitialPhotoUploadTicketTests(), catalog = try InitialPhotoUploadDestination.Catalog([fixture.destination()])
        let session = ScopedMockTransport().makeSession()
        defer { session.invalidateAndCancel() }
        var constructions = 0
        do {
            let result = try await owner.transferAppPhoto(prepared, catalog: catalog, send: { _, validate in
                try validate()
                if mode == "cancel" { throw CancellationError() }
                return try fixture.bytes(mode == "held" ? ["outcome": "held", "attempt_id": UUID().uuidString.lowercased()] : [:])
            }, makeTask: { constructions += 1; return .init(session: session) })
            #expect(mode == "held" && result == nil)
        } catch { #expect(mode != "held") }
        #expect(constructions == 0)
        #expect(await session.allTasks.isEmpty)
        #expect(try row(store).allocationData == reserved.startingTicketRequest().encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func expiredSignedCapabilityCreatesNoTaskAndIsSpent() async throws {
        let session = ScopedMockTransport().makeSession(), task = PinnedPhotoUploadTask(session: session)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try #require(URL(string: "https://sealed-role.invalid/photo-upload")))
        request.httpMethod = "PUT"
        await #expect(throws: (any Error).self) {
            _ = try await task.response(for: request, fromFile: URL(fileURLWithPath: "/synthetic-unopened-file"),
                timeout: 300, expiresAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1000) - 1)
        }
        await task.waitForLocalTermination()
        #expect(await session.allTasks.isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await task.response(for: request, fromFile: URL(fileURLWithPath: "/synthetic-unopened-file"), timeout: 300)
        }
        #expect(await session.allTasks.isEmpty)
    }

    @Test func expiryBetweenCreationAndResumeCancelsRetainedTask() async throws {
        let mock = ScopedMockTransport(), session = mock.makeSession(), hooks = OSAllocatedUnfairLock(initialState: 0)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        mock.register(path: "/photo-upload") { _ in Issue.record("Expired suspended upload resumed"); throw URLError(.badURL) }
        let task = PinnedPhotoUploadTask(session: session, beforeResume: {
            hooks.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 2.2)
        })
        var request = URLRequest(url: try #require(URL(string: "https://sealed-role.invalid/photo-upload")))
        request.httpMethod = "PUT"
        let expiry = Int64(Date().timeIntervalSince1970 * 1000) + 2_000
        await #expect(throws: (any Error).self) {
            _ = try await task.response(for: request, fromFile: file, timeout: 300, expiresAtMilliseconds: expiry)
        }
        await task.waitForLocalTermination()
        #expect(hooks.withLock { $0 } == 1)
        #expect(await session.allTasks.isEmpty)
    }

    @Test(arguments: ["owner", "deletion"], ["beforeSave", "beforeConsume"])
    func issuedTicketLosesOwnershipBeforePut(_ fault: String, phase: String) async throws {
        let fixtureContext = try await putFixture(), store = fixtureContext.store, owner = fixtureContext.owner, prepared = fixtureContext.prepared
        let fixture = InitialPhotoUploadTicketTests(), catalog = try InitialPhotoUploadDestination.Catalog([fixture.destination()])
        let session = ScopedMockTransport().makeSession()
        defer { session.invalidateAndCancel() }
        func loseOwnership() throws {
            let context = store.context()
            if fault == "owner" {
                let id = store.inventoryID
                let inventory = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
                inventory.generation = UUID()
            } else {
                let id = store.packageID
                let row = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                context.delete(row)
            }
            try context.save()
        }
        var saves = 0, sends = 0, constructions = 0
        try owner.setMetadataFault { boundary in
            if boundary == .beforeSave {
                saves += 1
                if saves == 2 && phase == "beforeSave" { try loseOwnership() }
            }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.transferAppPhoto(prepared, catalog: catalog, send: { request, validate in
                sends += 1; try validate(); return try fixture.bytes(fixture.row(request.allocation))
            }, makeTask: {
                constructions += 1
                do { try loseOwnership() } catch { Issue.record(error) }
                return .init(session: session)
            })
        }
        #expect(sends == 1 && constructions == (phase == "beforeConsume" ? 1 : 0))
        #expect(await session.allTasks.isEmpty)
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }

    @Test(arguments: Mapping.Role.allCases)
    func sealedRoleResponseNeverSettlesOrReleases(_ role: Mapping.Role) async throws {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture(role)
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        let allocation = reservedFixture.allocation
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
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        let allocation = reservedFixture.allocation
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
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        let allocation = reservedFixture.allocation
        let before = try row(store), pause = PhotoUploadCompletionPause()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoUploadHangingProtocol.self]
        let session = URLSession(configuration: config)
        let started = PhotoUploadTestSignal()
        PhotoUploadHangingProtocol.startSignal.withLock { $0 = started }
        defer { PhotoUploadHangingProtocol.startSignal.withLock { $0 = nil }; session.invalidateAndCancel() }
        let concrete = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: concrete, timeout: mode == "timeout" ? 0.2 : 10)
        var finished = false, drained = false, acquired = false
        let call = Task {
            defer { finished = true; started.finish(); pause.finishWaiting() }
            return try await owner.uploadAppPhotoTransfer(prepared, upload: upload)
        }
        var contender: Task<Void, Never>?
        var transition: Task<Bool, Never>?
        do {
            try await started.wait()
            let coordinator = ScanInferencePersistenceCoordinator.shared
            contender = Task {
                let held = await coordinator.acquireAll(scanIds: [prepared.queueID.uuidString, prepared.observationID.uuidString])
                acquired = true
                await coordinator.releaseAll(scanIds: held)
            }
            if mode == "account" {
                transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
            } else if mode == "cancel" { call.cancel() }
            try await pause.waitForEntry()
            try await Task.sleep(for: .milliseconds(30))
            #expect(!finished && !drained && !acquired)
            #expect(try row(store) == before)
            pause.release()
            await #expect(throws: (any Error).self) { _ = try await call.value }
            await contender?.value
            let after = try row(store)
            #expect(acquired && finished && after == before)
            if let transition {
                let result = await transition.value
                #expect(result && drained)
            } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        } catch {
            pause.release(); call.cancel()
            _ = await call.result
            await contender?.value
            if let transition { _ = await transition.value } else { _ = await owner.invalidateAndAwaitForAccountTransition() }
            throw error
        }
    }

    @Test(arguments: ["cancel", "account", "timeout"])
    func freshPutTerminationRetainsLeaseAndLocks(_ mode: String) async throws {
        let began = ContinuousClock.now
        var phase = "fixture"
        let context = try await putFixture(nearExpiry: mode == "timeout"), store = context.store, owner = context.owner, prepared = context.prepared
        let fixture = InitialPhotoUploadTicketTests(), catalog = try InitialPhotoUploadDestination.Catalog([fixture.destination()])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoUploadHangingProtocol.self]
        let session = URLSession(configuration: config), started = PhotoUploadTestSignal(), pause = PhotoUploadCompletionPause()
        PhotoUploadHangingProtocol.startSignal.withLock { $0 = started }
        defer { PhotoUploadHangingProtocol.startSignal.withLock { $0 = nil }; session.invalidateAndCancel() }
        var finished = false, drained = false, acquired = false, observedStart = false
        phase = "opening-ticket-owner"
        let call = Task {
            defer { finished = true; started.finish(); pause.finishWaiting() }
            return try await owner.transferAppPhoto(prepared, catalog: catalog, send: { request, validate in
                phase = "ticket-sender-validation"
                try validate()
                phase = "ticket-response"
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                // A delayed ticket response leaves the same short PUT window;
                // allocation preparation must not consume that window first.
                let created = now - (mode == "timeout" ? 590_000 : 0)
                let wire = try fixture.row(request.allocation, createdAtMilliseconds: created)
                if mode == "timeout" {
                    let receipt = try #require(request.allocation.receipt)
                    let expiry = try #require(wire["capability_expires_at_ms"] as? Int64)
                    let signed = try #require(wire["signed_expires_at_ms"] as? Int64)
                    #expect(receipt == context.reserved.receipt)
                    #expect(created >= receipt.createdAtMilliseconds && created < receipt.expiresAtMilliseconds)
                    #expect(receipt.expiresAtMilliseconds > now + 10_000)
                    #expect(expiry == min(receipt.expiresAtMilliseconds, created + 600_000) && expiry == now + 10_000)
                    #expect(signed == (expiry / 1000) * 1000 && signed > now)
                }
                return try fixture.bytes(wire)
            }, makeTask: {
                phase = "construct-upload"
                return .init(session: session, completionPause: { pause.wait() })
            })
        }
        var contender: Task<Void, Never>?, transition: Task<Bool, Never>?
        do {
            try await started.wait()
            observedStart = true
            phase = "upload-started"
            let held = try row(store)
            let coordinator = ScanInferencePersistenceCoordinator.shared
            contender = Task {
                let locks = await coordinator.acquireAll(scanIds: [prepared.queueID.uuidString, prepared.observationID.uuidString])
                acquired = true
                await coordinator.releaseAll(scanIds: locks)
            }
            if mode == "account" {
                transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
            } else if mode == "cancel" { call.cancel() }
            try await pause.waitForEntry()
            phase = "completion-paused"
            #expect(observedStart && (mode != "timeout" || !call.isCancelled))
            #expect(try NativePhotoStatusRecoveryTests().saved(store).receipt == context.reserved.receipt)
            try await Task.sleep(for: .milliseconds(30))
            #expect(!finished && !drained && !acquired)
            #expect(try row(store) == held)
            pause.release()
            await #expect(throws: (any Error).self) { _ = try await call.value }
            await contender?.value
            #expect(finished && acquired)
            #expect(try row(store) == held)
            #expect(try NativePhotoStatusRecoveryTests().saved(store).receipt == context.reserved.receipt)
            if let transition { #expect(await transition.value); #expect(drained) } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        } catch {
            let completedBeforeCleanup = finished
            pause.release(); call.cancel()
            let outcome = await call.result
            await contender?.value
            if let transition { _ = await transition.value } else { _ = await owner.invalidateAndAwaitForAccountTransition() }
            print("Native PUT diagnostic mode=\(mode) phase=\(phase) elapsed=\(began.duration(to: .now)) completedBeforeCleanup=\(completedBeforeCleanup)")
            // A closed start signal must not hide a child failure that preceded cleanup.
            if !observedStart, completedBeforeCleanup, case .failure(let underlying) = outcome { throw underlying }
            throw error
        }
    }

    @Test(arguments: ["file", "saved"])
    func postflightFailureJoinsBeforeRejecting(_ fault: String) async throws {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        let allocation = reservedFixture.allocation
        let before = try row(store), mock = ScopedMockTransport(), session = mock.makeSession(), pause = PhotoUploadCompletionPause()
        defer { session.invalidateAndCancel() }
        mock.register(path: "/photo-upload") { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let concrete = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        let upload = try SharedMediaNativePhotoUpload.forTesting(allocation: allocation, task: concrete)
        var finished = false
        let call = Task {
            defer { finished = true; pause.finishWaiting() }
            return try await owner.uploadAppPhotoTransfer(prepared, upload: upload)
        }
        do {
            try await pause.waitForEntry()
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
        } catch {
            pause.release(); call.cancel()
            _ = await call.result
            _ = await owner.invalidateAndAwaitForAccountTransition()
            throw error
        }
    }
}

/// The runner owns the test deadline. Failure before the event also ends the wait.
private final class PhotoUploadTestSignal: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = pair.stream; continuation = pair.continuation
    }
    func signal() { continuation.yield(()); continuation.finish() }
    func finish() { continuation.finish() }
    func wait() async throws {
        for await _ in stream { return }
        throw URLError(.cannotLoadFromNetwork)
    }
}

private final class PhotoUploadCompletionPause: Sendable {
    private let entry = PhotoUploadTestSignal()
    private let semaphore = DispatchSemaphore(value: 0)
    func waitForEntry() async throws { try await entry.wait() }
    func finishWaiting() { entry.finish() }
    func wait() {
        entry.signal()
        _ = semaphore.wait(timeout: .now() + 15)
    }
    func release() { semaphore.signal() }
}
private final class PhotoUploadHangingProtocol: URLProtocol {
    static let startSignal = OSAllocatedUnfairLock<PhotoUploadTestSignal?>(initialState: nil)
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.startSignal.withLock { $0 }?.signal() }
    override func stopLoading() {}
}
