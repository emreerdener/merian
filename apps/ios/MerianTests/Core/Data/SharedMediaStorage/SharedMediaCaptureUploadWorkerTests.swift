import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@MainActor
@Suite("Capture durable private upload", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaCaptureUploadWorkerTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    private func prepare(_ store: Store, owner: SharedMediaNativeOriginalOwner) async throws -> CaptureInitialEvidencePlan {
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: (0..<2).map { _ in
                .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: store.bytes.count,
                    sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)), preparedMediaID: UUID()))
            })
        let parent = try await owner.reserveAppCaptureSubmission(plan, context: SharedMediaCaptureSubmissionContextTests.context(plan))
        for member in parent.submission.members {
            _ = try await owner.materializeAppCaptureArtifact(parent.submission.artifact(mediaID: member.mediaID), bytes: store.bytes)
        }
        _ = try await owner.acceptAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        try await owner.resumeAppCaptureRoot()
        #expect(owner.isReadyForCaptureDispatch && !owner.isReadyForAppDispatch)
        await #expect(throws: (any Error).self) { try await owner.inspectApp() }
        return plan
    }

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func interruptedReceiptSaveResumesOnlyMissingAcknowledgements(_ point: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let plan = try await prepare(store, owner: owner)
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        fixture.dispatcher.overridingAuthUserID = plan.ownerID
        let sourceBytes = store.bytes
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        fixture.mock.register(path: "/upload-capture-stage") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let size = body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let metadata = try #require(JSONSerialization.jsonObject(with: body.subdata(in: 4..<(4 + size))) as? [String: Any])
            let media = try #require(metadata["media_id"] as? String)
            calls.withLock { $0.append(media) }
            #expect(body.suffix(sourceBytes.count) == sourceBytes)
            let reply = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
                "media_id": media, "request_sha256": String(repeating: "a", count: 64), "ready": true])
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])), reply)
        }
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        var reached = false
        try owner.configureCaptureSubmissionWritingForTesting { boundary in
            if boundary == point { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation, transport: transport)
        }
        #expect(reached && calls.withLock { $0.count } == 1)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let partial = try #require(try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: context))
        #expect(partial.artifacts.filter { $0.remoteStage != nil }.count == (point == .afterSave ? 1 : 0))
        #expect(throws: (any Error).self) { try SharedMediaCaptureUploadReadiness.require(partial) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        #expect(!cold.isReadyForCaptureDispatch)
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        let complete = try await cold.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation, transport: transport)
        #expect(try SharedMediaCaptureUploadReadiness.require(complete) == String(repeating: "a", count: 64))
        #expect(calls.withLock { $0.count } == (point == .afterSave ? 2 : 3))
        #expect(try await cold.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation, transport: transport) == complete)
        #expect(calls.withLock { $0.count } == (point == .afterSave ? 2 : 3))
        #expect(!cold.isReadyForAppDispatch)
        #expect(try store.rows().allSatisfy { $0.retirementData == nil })
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["checksum", "lost"])
    func divergentOrUnknownSecondUploadCannotAuthorizeIdentify(_ kind: String) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        fixture.dispatcher.overridingAuthUserID = plan.ownerID
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.mock.register(path: "/upload-capture-stage") { request in
            let count = calls.withLock { $0 += 1; return $0 }
            if count == 2 && kind == "lost" { throw URLError(.networkConnectionLost) }
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let size = body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let metadata = try #require(JSONSerialization.jsonObject(with: body.subdata(in: 4..<(4 + size))) as? [String: Any])
            let reply = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
                "media_id": #require(metadata["media_id"] as? String),
                "request_sha256": String(repeating: count == 2 ? "b" : "a", count: 64), "ready": true])
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])), reply)
        }
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        await #expect(throws: (any Error).self) {
            try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation, transport: transport)
        }
        #expect(calls.withLock { $0 } == 2)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let partial = try #require(try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: context))
        #expect(partial.artifacts.filter { $0.remoteStage != nil }.count == 1)
        #expect(throws: (any Error).self) { try SharedMediaCaptureUploadReadiness.require(partial) }
        #expect(try store.rows().allSatisfy { $0.retirementData == nil })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missingQueue", "missingFunding", "replacedFunding", "cancelled"])
    func damagedQueueCannotQualifyAfterColdOpen(_ damage: String) async throws {
        let store = try await Store(), owner = try await store.open()
        _ = try await prepare(store, owner: owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let write = ModelContext(store.container); write.autosaveEnabled = false
        if damage == "missingQueue" {
            let rows = try write.fetch(FetchDescriptor<OfflineQueuedScan>())
            write.delete(try #require(rows.first))
        } else {
            let rows = try write.fetch(FetchDescriptor<OfflineJobRecord>())
            let job = try #require(rows.first)
            if damage == "missingFunding" { job.metadataJSON = "{}" } else if damage == "replacedFunding" {
                let funding = try #require(OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: job.metadataJSON))
                let replacement = ScanFundingReservation(accountId: funding.accountId, scanId: funding.scanId,
                    source: funding.source, blockerScanIds: funding.blockerScanIds, createdAt: funding.createdAt.addingTimeInterval(1))
                job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(replacement, in: job.metadataJSON)
            } else { job.status = .cancelled }
        }
        try write.save()
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { try await cold.resumeAppCaptureRoot() }
        #expect(!cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        #expect(try store.rows().allSatisfy { $0.retirementData == nil })
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func reservedDraftCannotQualifyAsAcceptedWork() async throws {
        let store = try await Store(), owner = try await store.open()
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: [.audio(.init(source: .init(mediaID: UUID(),
                contentType: "audio/wav", byteCount: store.bytes.count, sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)),
                preparedMediaID: UUID()))])
        _ = try await owner.reserveAppCaptureSubmission(plan, context: SharedMediaCaptureSubmissionContextTests.context(plan))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDraft && !cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}
