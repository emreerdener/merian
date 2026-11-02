import Foundation
import os
import SwiftData
import Testing
@testable import Merian

@Suite("Native exact received status", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativeReceivedStatusTests {
    @Test func releaseStagingInvalidatesPreviouslySelectedCandidate() async throws {
        let (_, owner, prepared) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let selected = try #require(try await owner.discoverAppReceivedCandidates().first)
        let release = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(release)
        await #expect(throws: (any Error).self) {
            _ = try await owner.checkAppReceivedStatus(selected) { _, _, _ in
                Issue.record("Release state reached status transport"); return Data()
            }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountShutdownDrainsOutstandingTransportBeforeReturning() async throws {
        let (h, owner, _) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let selected = try #require(try await owner.discoverAppReceivedCandidates().first)
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: h.ownerID)
        let entered = OSAllocatedUnfairLock(initialState: false), release = DispatchSemaphore(value: 0)
        defer { release.signal(); fixture.close() }
        fixture.mock.register(path: "/check-scan-status") { request in
            entered.withLock { $0 = true }
            _ = release.wait(timeout: .now() + 5)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data("{\"status\":\"found\"}".utf8))
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        var senderTerminated = false
        let call = Task {
            try await owner.checkAppReceivedStatus(selected) { scan, account, validate in
                defer { senderTerminated = true }
                return try await transport.perform(scanID: scan, ownerID: account, validate: validate)
            }
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while !entered.withLock({ $0 }) {
            guard ContinuousClock.now < deadline else {
                call.cancel(); release.signal(); _ = await call.result
                _ = await owner.invalidateAndAwaitForAccountTransition(); throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        var closingStarted = false
        let close = Task {
            closingStarted = true
            let closed = await owner.invalidateAndAwaitForAccountTransition()
            #expect(senderTerminated)
            return closed
        }
        while !closingStarted { await Task.yield() }
        release.signal()
        await #expect(throws: (any Error).self) { _ = try await call.value }
        #expect(await close.value)
    }

    @Test(arguments: [false, true])
    func actualTransportPreservesPositiveReceivedState(allocated: Bool) async throws {
        let (h, owner, prepared) = try await SharedMediaNativePhotoAllocationTests().fixture()
        if allocated {
            _ = try await owner.allocateAppPhoto(prepared, authorizeCreate: { _, _ in .init(recipient: .gemini, validate: {}) }) { _, _, _ in .held(.notFound) }
        }
        let selected = try #require(try await owner.discoverAppReceivedCandidates().first)
        let reservation = try await owner.reserveAppRecoveryPresentationForTesting(prepared, reservationID: UUID())
        #expect(reservation.acknowledged)
        let before = try NativePhotoStatusRecoveryTests().row(h)
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: h.ownerID)
        defer { fixture.close() }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        for found in [false, true] {
            fixture.mock.register(path: "/check-scan-status") { request in
                let body = try #require(MockURLProtocol.bodyData(for: request))
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
                #expect(object == ["scan_id": prepared.observationID.uuidString.lowercased()])
                #expect(request.httpMethod == "POST" && request.timeoutInterval == 5)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!, Data((found ? "{\"status\":\"found\"}" : "{\"status\":\"not_found\"}").utf8))
            }
            #expect(try await owner.checkAppReceivedStatus(selected) { scan, account, validate in
                try await transport.perform(scanID: scan, ownerID: account, validate: validate)
            } == found)
            #expect(try NativePhotoStatusRecoveryTests().row(h) == before)
            #expect(try await owner.reconcileAppRecoveryPresentationForTesting(reservation))
        }
        let settled = try await owner.settleAppRecoveryPresentationForTesting(reservation, elapsed: .milliseconds(1))
        #expect(settled.acknowledged && settled.presentation.chargedMilliseconds == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func everyCandidateIdentityFieldIsRequiredBeforeSend() async throws {
        let (h, owner, _) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let selected = try #require(try await owner.discoverAppReceivedCandidates().first)
        for field in 0..<7 {
            let foreignProfile = SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: h.inventoryID,
                generation: selected.profile.generation, storeIdentity: selected.profile.storeIdentity,
                physicalBinding: selected.profile.physicalBinding, receiptDigest: selected.profile.receiptDigest)
            let changed = SharedMediaNativeReceivedCandidate(profile: field == 0 ? foreignProfile : selected.profile,
                packageID: field == 1 ? UUID() : selected.packageID,
                draftGeneration: field == 2 ? UUID() : selected.draftGeneration,
                operationID: field == 3 ? UUID() : selected.operationID,
                revision: field == 4 ? selected.revision + 1 : selected.revision,
                preparedSHA256: field == 5 ? String(repeating: "f", count: 64) : selected.preparedSHA256,
                receivedSHA256: field == 6 ? String(repeating: "f", count: 64) : selected.receivedSHA256)
            await #expect(throws: (any Error).self) {
                _ = try await owner.checkAppReceivedStatus(changed) { _, _, _ in
                    Issue.record("Changed identity reached status transport"); return Data()
                }
            }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["deleted", "cancelled", "foreignReply"])
    func lateStatusCannotEscapeChangedAuthority(fault: String) async throws {
        let (h, owner, _) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let selected = try #require(try await owner.discoverAppReceivedCandidates().first)
        let task = Task { @MainActor in
            try await owner.checkAppReceivedStatus(selected) { _, _, validate in
                try validate()
                if fault == "deleted" {
                    let context = h.context()
                    let queue = try #require(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
                    context.delete(queue); try context.save()
                } else if fault == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
                if fault == "foreignReply" {
                    return Data("{\"status\":\"found\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\"}".utf8)
                }
                return Data("{\"status\":\"found\"}".utf8)
            }
        }
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
