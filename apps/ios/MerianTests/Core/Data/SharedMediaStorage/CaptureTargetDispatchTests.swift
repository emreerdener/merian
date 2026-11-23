import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@Suite("Capture target dispatch isolation", .serialized)
@MainActor
struct CaptureTargetDispatchTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    private func source(_ store: Store) -> SharedMediaCaptureDraftSourceInput {
        .init(id: UUID(), scanID: UUID(), submissionGeneration: UUID(), mediaID: UUID(),
            itemIndex: 0, role: .sourceAudio, contentType: "audio/wav", byteCount: Int64(store.bytes.count),
            sha256: SharedMediaAcquisitionEncoding.digest(store.bytes),
            context: .init(origin: .microphone, cameraVerticalCenter: nil))
    }
    private func accept(_ input: SharedMediaCaptureDraftSourceInput, store: Store,
                        owner: SharedMediaNativeOriginalOwner) async throws -> CaptureInitialEvidencePlan {
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: input.scanID,
            generation: input.submissionGeneration, items: [.audio(.init(source: .init(mediaID: input.mediaID,
                contentType: input.contentType, byteCount: Int(input.byteCount), sha256: input.sha256), preparedMediaID: UUID()))])
        _ = try await owner.acceptAppCaptureDraft(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan)) { _ in
            Issue.record("Acceptance attempted to read a retained source")
            throw SharedMediaStorageFailure.conflict
        }
        return plan
    }

    private func configure(_ fixture: ObservationSourceTransportTests.Fixture, plan: CaptureInitialEvidencePlan,
                           calls: OSAllocatedUnfairLock<Int>, beforeReply: (@MainActor @Sendable () throws -> Void)? = nil) {
        fixture.dispatcher.overridingAuthUserID = plan.ownerID
        fixture.mock.register(path: "/upload-capture-stage") { request in
            calls.withLock { $0 += 1 }
            if let beforeReply {
                let done = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    defer { done.signal() }
                    do { try beforeReply() } catch { Issue.record(error) }
                }
                guard done.wait(timeout: .now() + 15) == .success else { throw URLError(.timedOut) }
            }
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let size = body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let metadata = try #require(JSONSerialization.jsonObject(with: body.subdata(in: 4..<(4 + size))) as? [String: Any])
            let reply = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
                "media_id": #require(metadata["media_id"] as? String), "request_sha256": String(repeating: "a", count: 64), "ready": true])
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])), reply)
        }
    }

    @Test func acceptedTargetsProceedWhileOtherDraftsStayHeldAfterColdOpen() async throws {
        let store = try await Store(), owner = try await store.open()
        let first = source(store), pending = source(store), last = source(store)
        _ = try await owner.materializeAppCaptureSource(first, bytes: store.bytes)
        let firstPlan = try await accept(first, store: store, owner: owner)
        let held = try await owner.materializeAppCaptureSource(pending, bytes: store.bytes)
        _ = try await owner.materializeAppCaptureSource(last, bytes: store.bytes)
        _ = try await accept(last, store: store, owner: owner)
        #expect(!owner.isReadyForCaptureDispatch && owner.isReadyForCaptureDraft)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(!cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        configure(fixture, plan: firstPlan, calls: calls)
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        let completed = try await cold.stageAppCaptureSubmission(scanID: firstPlan.scanID, generation: firstPlan.generation, transport: transport)
        #expect(completed.artifacts.allSatisfy { $0.remoteStage != nil })
        #expect(calls.withLock { $0 } == 1)
        #expect(!cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        for (scan, generation) in [(firstPlan.scanID, UUID()), (UUID(), firstPlan.generation)] {
            await #expect(throws: (any Error).self) {
                _ = try await cold.stageAppCaptureSubmission(scanID: scan, generation: generation, transport: transport)
            }
        }
        await #expect(throws: (any Error).self) {
            _ = try await cold.stageAppCaptureSubmission(scanID: pending.scanID, generation: pending.submissionGeneration, transport: transport)
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(try store.rows().map(SharedMediaCaptureArtifactLedger.receipt).first { $0.request.id == pending.id } == held)
        #expect(try await cold.readAppCaptureSource(pending) == store.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["pendingInode", "targetQueue", "unknownLiability"])
    func damagedTargetOrGlobalLiabilityBlocksBeforeTransport(_ damage: String) async throws {
        let store = try await Store(), owner = try await store.open(), first = source(store), pending = source(store)
        _ = try await owner.materializeAppCaptureSource(first, bytes: store.bytes)
        let plan = try await accept(first, store: store, owner: owner)
        _ = try await owner.materializeAppCaptureSource(pending, bytes: store.bytes)
        try await owner.resumeAppCaptureRoot()
        try damageStore(damage, store: store, pending: pending)
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        configure(fixture, plan: plan, calls: calls)
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation,
                transport: .init(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher))
        }
        #expect(calls.withLock { $0 } == 0)
        #expect(try store.rows().allSatisfy { $0.acceptanceData == nil })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["pendingInode", "targetQueue", "unknownLiability", "revision"])
    func changesWhileTransportAwaitsCannotCommitReadiness(_ damage: String) async throws {
        let store = try await Store(), owner = try await store.open(), first = source(store), pending = source(store)
        _ = try await owner.materializeAppCaptureSource(first, bytes: store.bytes)
        let plan = try await accept(first, store: store, owner: owner)
        _ = try await owner.materializeAppCaptureSource(pending, bytes: store.bytes)
        try await owner.resumeAppCaptureRoot()
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        configure(fixture, plan: plan, calls: calls, beforeReply: { try damageStore(damage, store: store, pending: pending) })
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation,
                transport: .init(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher))
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(try store.rows().allSatisfy { $0.acceptanceData == nil })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func damageStore(_ damage: String, store: Store, pending: SharedMediaCaptureDraftSourceInput) throws {
        let write = ModelContext(store.container); write.autosaveEnabled = false
        switch damage {
        case "pendingInode":
            let url = store.directory.appendingPathComponent(pending.id.uuidString.lowercased())
            try FileManager.default.removeItem(at: url)
            try store.bytes.write(to: url)
        case "targetQueue":
            write.delete(try #require(try write.fetch(FetchDescriptor<OfflineQueuedScan>()).first))
        case "unknownLiability":
            let inventory = try #require(try write.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            write.insert(SharedMediaAllocationRecord(id: UUID(), inventoryID: inventory.id, accountID: store.base.ownerID,
                packageID: UUID(), namespaceRaw: "unknown-test-liability", fileToken: UUID().uuidString.lowercased(),
                poolRaw: "durable", stateRaw: "reserved", materializedBytes: 0, reservedBytes: 1, physicalIdentity: nil))
        case "revision":
            let inventory = try #require(try write.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            inventory.revision += 1
        default: throw SharedMediaStorageFailure.invalid
        }
        try write.save()
    }
}
