import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture draft original binding", .serialized)
@MainActor
struct CaptureDraftSourceBindingTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    func source(_ store: Store, ordinal: Int = 0) -> SharedMediaCaptureDraftSourceInput {
        .init(id: UUID(), scanID: store.input.scanID, submissionGeneration: store.input.submissionGeneration,
            mediaID: UUID(), itemIndex: ordinal, role: .sourceAudio, contentType: "audio/wav",
            byteCount: Int64(store.bytes.count), sha256: SharedMediaAcquisitionEncoding.digest(store.bytes),
            context: .init(origin: .microphone, cameraVerticalCenter: nil))
    }

    func plan(_ store: Store, sources: [SharedMediaCaptureDraftSourceInput]) throws -> CaptureInitialEvidencePlan {
        try .init(ownerID: store.base.ownerID, scanID: store.input.scanID, generation: store.input.submissionGeneration,
            items: sources.map { .audio(.init(source: .init(mediaID: $0.mediaID, contentType: $0.contentType,
                byteCount: Int($0.byteCount), sha256: $0.sha256), preparedMediaID: UUID())) })
    }

    private func stageAndVerifyWire(_ plan: CaptureInitialEvidencePlan, owner: SharedMediaNativeOriginalOwner,
                                    bytes: Data) async throws {
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        fixture.dispatcher.overridingAuthUserID = plan.ownerID
        let expectedPlan = try plan.encoded()
        fixture.mock.register(path: "/upload-capture-stage") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let size = body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let metadata = try #require(JSONSerialization.jsonObject(with: body.subdata(in: 4..<(4 + size))) as? [String: Any])
            #expect(Set(metadata.keys) == ["schema_version", "plan", "media_id"])
            #expect(metadata["schema_version"] as? Int == 1)
            let wirePlan = try #require(metadata["plan"] as? [String: Any])
            #expect(try JSONSerialization.data(withJSONObject: wirePlan, options: [.sortedKeys, .withoutEscapingSlashes]) == expectedPlan)
            #expect(body.suffix(from: 4 + size) == bytes)
            let reply = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
                "media_id": #require(metadata["media_id"] as? String), "request_sha256": String(repeating: "a", count: 64), "ready": true])
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])), reply)
        }
        let result = try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation,
            transport: .init(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher))
        #expect(result.artifacts.allSatisfy { $0.remoteStage != nil })
    }

    @Test func coldSourcesBindInFinalOrderWithoutCopyingOrRereading() async throws {
        let store = try await Store(), owner = try await store.open()
        let first = source(store), second = source(store, ordinal: 1)
        let original = try await owner.materializeAppCaptureSource(first, bytes: store.bytes)
        let other = try await owner.materializeAppCaptureSource(second, bytes: store.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDraft && !cold.isReadyForAppDispatch)
        #expect(try await cold.readAppCaptureSource(first) == store.bytes)
        let final = try plan(store, sources: [second, first])
        _ = try await cold.acceptAppCaptureDraft(plan: final,
            context: SharedMediaCaptureSubmissionContextTests.context(final)) { _ in
            Issue.record("Final acceptance reread an already retained original")
            throw SharedMediaStorageFailure.conflict
        }
        let rows = try store.rows().map(SharedMediaCaptureArtifactLedger.receipt)
        #expect(rows.count == 2)
        #expect(rows.first { $0.request.id == first.id } == original)
        #expect(rows.first { $0.request.id == second.id } == other)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        try await stageAndVerifyWire(final, owner: cold, bytes: store.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureArtifactWriteBoundary.allCases)
    func interruptedSourceNeverAuthorizesDispatch(_ boundary: SharedMediaCaptureArtifactWriteBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), input = source(store)
        var reached = false
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == boundary { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes) }
        #expect(reached)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        if boundary == .afterPartialCreation {
            await #expect(throws: (any Error).self) { try await cold.resumeAppCaptureRoot() }
        } else {
            try await cold.resumeAppCaptureRoot()
            #expect(!cold.isReadyForCaptureDispatch)
            if boundary != .beforeReservationSave { #expect(!cold.isReadyForAppDispatch) }
            let recovered = try await cold.materializeAppCaptureSource(input, bytes: store.bytes)
            #expect(recovered.phase == .ready)
            #expect(try store.rows().count == 1)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func lostParentBindingReplyReusesOriginalOwnership(_ boundary: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), input = source(store)
        let original = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let final = try plan(store, sources: [input])
        let context = try SharedMediaCaptureSubmissionContextTests.context(final)
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == boundary { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAppCaptureDraft(plan: final, context: context) { _ in
                Issue.record("Retained source was read during interrupted binding")
                throw SharedMediaStorageFailure.conflict
            }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        _ = try await cold.acceptAppCaptureDraft(plan: final, context: context) { _ in
            Issue.record("Retained source was read during binding recovery")
            throw SharedMediaStorageFailure.conflict
        }
        #expect(try store.rows().map(SharedMediaCaptureArtifactLedger.receipt) == [original])
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "changed", "extra"])
    func finalPlanCannotOmitOrSubstituteHeldSources(_ mutation: String) async throws {
        let store = try await Store(), owner = try await store.open(), first = source(store)
        _ = try await owner.materializeAppCaptureSource(first, bytes: store.bytes)
        let second = source(store, ordinal: 1)
        var finalSources = [first]
        switch mutation {
        case "missing": finalSources.append(second)
        case "extra": _ = try await owner.materializeAppCaptureSource(second, bytes: store.bytes)
        case "changed":
            finalSources = [.init(id: first.id, scanID: first.scanID, submissionGeneration: first.submissionGeneration,
                mediaID: first.mediaID, itemIndex: first.itemIndex, role: first.role, contentType: first.contentType,
                byteCount: first.byteCount, sha256: String(repeating: "a", count: 64), context: first.context)]
        default: Issue.record("Unknown mutation")
        }
        let final = try plan(store, sources: finalSources)
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAppCaptureDraft(plan: final,
                context: SharedMediaCaptureSubmissionContextTests.context(final)) { _ in
                Issue.record("Invalid membership reached external artifact reader")
                throw SharedMediaStorageFailure.conflict
            }
        }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try store.rows().contains { $0.id == first.id })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
