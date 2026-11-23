import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture result custody", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaCaptureResultWriterTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    func prepare(_ store: Store, owner: SharedMediaNativeOriginalOwner) async throws -> CaptureInitialEvidencePlan {
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: (0..<2).map { _ in
                .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: store.bytes.count,
                    sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)), preparedMediaID: UUID()))
            } + [.description("Synthetic retained field note")])
        try await owner.resumeAppCaptureRoot()
        let bytes = store.bytes
        _ = try await owner.acceptAppCaptureDraft(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan)) { _ in bytes }
        return plan
    }

    func stage(_ plan: CaptureInitialEvidencePlan, owner: SharedMediaNativeOriginalOwner) async throws {
        let fixture = try ObservationSourceTransportTests.Fixture(); defer { fixture.close() }
        fixture.dispatcher.overridingAuthUserID = plan.ownerID
        fixture.mock.register(path: "/upload-capture-stage") { request in
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
        _ = try await owner.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation,
            transport: .init(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher))
    }

    func response(_ plan: CaptureInitialEvidencePlan, generation: UUID? = nil, name: String = "Monarch") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["success": true, "data": [
            "scan_id": plan.scanID.uuidString.lowercased(), "is_biological_subject": true, "is_live_capture": false,
            "ecology_type": "wild", "is_invasive": false, "scientific_name": "Danaus plexippus", "common_name": name,
            "confidence_score": 0.75, "insight_data": ["hazard_type": "none", "ai_reasoning": "Synthetic proof fixture."]
        ], "initial_evidence": ["schema_version": 1, "owner_id": plan.ownerID.uuidString.lowercased(),
            "scan_id": plan.scanID.uuidString.lowercased(), "generation": (generation ?? plan.generation).uuidString.lowercased(),
            "evidence_digest": String(repeating: "c", count: 64)]], options: [.sortedKeys])
    }

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func atomicCommitRecoversLostReplyAndPreservesLaterEdits(_ point: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        try await stage(plan, owner: owner)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        let bytes = try response(plan)
        var reached = false
        try owner.configureCaptureSubmissionWritingForTesting { boundary in
            if boundary == point { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: bytes, account: account)
        }
        #expect(reached)
        let inspect = ModelContext(store.container); inspect.autosaveEnabled = false
        #expect(try inspect.fetchCount(FetchDescriptor<LocalScanRecord>()) == (point == .afterSave ? 1 : 0))
        let originalJob = try #require(try inspect.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        #expect((originalJob.status == .complete) == (point == .afterSave))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open(); try await cold.resumeAppCaptureRoot()
        #expect(try await cold.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: bytes, account: account) == (point == .afterSave ? .retained : .inserted))
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(try ObservationHistoryEnrollmentService.ordinaryCompletionAdmission(observation: plan.scanID,
            owner: plan.ownerID, container: store.container) != nil)
        #expect(try SharedMediaCaptureCompletionReadback.retained(for: record, ownerID: plan.ownerID, context: context).scanID == plan.scanID)
        #expect(!SharedMediaConsumerAuthority.permitsLegacyScanRemoval(raw: record.mediaAuthorityRaw, consumerID: nil))
        record.userConfirmedIdentification = true; record.fieldNotes = "A later edited note"
        record.selectedAnalysisID = UUID().uuidString.lowercased()
        record.scientificName = "Selected later analysis"; record.speciesId = UUID().uuidString
        // An enrollment job shares the subject without replacing ingestion proof.
        _ = try ObservationHistoryEnrollmentIntent.stage(observationID: plan.scanID, ownerID: plan.ownerID, context: context)
        try context.save()
        let job = try #require(try context.fetchOfflineJob(id: originalJob.id)), metadata = job.metadataJSON
        #expect(try await cold.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: bytes, account: account) == .retained)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let unchanged = try #require(try read.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(unchanged.userConfirmedIdentification && unchanged.fieldNotes == "A later edited note"
            && unchanged.scientificName == "Selected later analysis" && unchanged.selectedAnalysisID == record.selectedAnalysisID)
        #expect(try read.fetchOfflineJob(id: job.id)?.metadataJSON == metadata)
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try store.rows().allSatisfy { $0.retirementData == nil })
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func unstagedWrongSubmissionAndStaleAttemptCannotComplete() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        var current = true
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { current }, release: {})
        defer { account.finish() }
        let bytes = try response(plan)
        await #expect(throws: (any Error).self) {
            try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: bytes, account: account)
        }
        try await owner.resumeAppCaptureRoot(); try await stage(plan, owner: owner)
        for mode in ["attempt", "submission", "account"] {
            if mode == "account" { current = false }
            await #expect(throws: (any Error).self) {
                try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                    attemptGeneration: mode == "attempt" ? UUID() : plan.generation,
                    resultData: response(plan, generation: mode == "submission" ? UUID() : nil), account: account)
            }
            current = true; try await owner.resumeAppCaptureRoot()
        }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try read.fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { $0.status != .complete })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    func enrollmentFixture(_ plan: CaptureInitialEvidencePlan) throws -> (snapshot: [String: Any], response: Data) {
        let pageText = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v8.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(pageText.utf8)) as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        let originalText = try #require(items.first?["snapshot"] as? String)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data(originalText.utf8)) as? [String: Any])
        let scan = plan.scanID.uuidString.lowercased(), generation = plan.generation.uuidString.lowercased()
        var fields = ["merian.initial-evidence", "1", scan, generation, "8", String(plan.items.count)]
        func artifact(_ value: CaptureInitialEvidencePlan.Artifact) -> [String: Any] {
            fields += [value.mediaID.uuidString.lowercased(), value.contentType, String(value.byteCount), value.sha256]
            return ["media_id": value.mediaID.uuidString.lowercased(), "content_type": value.contentType,
                    "byte_count": value.byteCount, "sha256": value.sha256]
        }
        let nodes: [[String: Any]] = try plan.items.map { node in
            switch node {
            case .audio(let audio):
                fields.append("audio")
                let source = artifact(audio.source)
                let prepared = artifact(CaptureInitialEvidencePlan.Artifact(mediaID: audio.preparedMediaID,
                    contentType: "audio/wav", byteCount: 96, sha256: String(repeating: "d", count: 64)))
                return ["kind": "audio", "source": source, "prepared": prepared]
            case .description(let text): fields += ["description", text]; return ["kind": "description", "text": text]
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        let digest = SharedMediaAcquisitionEncoding.digest(Data(fields.map { "\($0.utf8.count):\($0)," }.joined().utf8))
        let proof: [String: Any] = ["schema_version": 1, "owner_id": plan.ownerID.uuidString.lowercased(),
            "scan_id": scan, "generation": generation, "evidence_digest": digest]
        var result = try #require(snapshot["result"] as? [String: Any]); result["scan_id"] = scan
        snapshot["observation_id"] = scan; snapshot["result"] = result
        snapshot["request_digest"] = digest; snapshot["initial_evidence"] = proof
        snapshot["evidence_manifest"] = ["schema_version": 8, "items": nodes]
        return (snapshot, try JSONSerialization.data(withJSONObject: ["success": true, "data": result, "initial_evidence": proof], options: [.sortedKeys]))
    }

    @Test(arguments: ["success", "queueDrift", "deletion", "selectionBefore", "malformedSelection", "selectionDuring", "selectionReceipt", "selectionRejected"])
    func sealedHistoryEnrollmentRetainsCaptureCustody(_ mode: String) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        try await stage(plan, owner: owner)
        let fixture = try enrollmentFixture(plan)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        _ = try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: fixture.response, account: account)
        let scanID = plan.scanID.uuidString.lowercased(), analysis = try #require(fixture.snapshot["analysis_id"] as? String)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = plan.ownerID.uuidString.lowercased(); state["observation_id"] = scanID
        state["selected_analysis_id"] = analysis
        var item = try #require(state["analysis"] as? [String: Any])
        item["snapshot"] = try #require(String(bytes: JSONSerialization.data(withJSONObject: fixture.snapshot, options: [.sortedKeys]), encoding: .utf8))
        state["analysis"] = item
        let stateData = try JSONSerialization.data(withJSONObject: state)
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "owner_id": plan.ownerID.uuidString.lowercased(), "observation_id": scanID, "baseline_analysis_id": analysis])
        if ["selectionBefore", "malformedSelection", "selectionReceipt", "selectionRejected"].contains(mode) {
            try selection(mode, plan: plan, container: store.container)
        }
        var calls = 0
        var cloud = ObservationHistoryCloudClient(begin: { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) },
            isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in Issue.record("Capture entered legacy enrollment"); throw ObservationHistoryError.unavailable }
        cloud.enrollInitial = { _ in calls += 1; return receipt }
        cloud.fetchState = { _ in
            let context = ModelContext(store.container); context.autosaveEnabled = false
            if mode == "queueDrift" {
                let queue = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
                queue.mediaAuthorityRaw = "legacy"
            }
            if mode == "selectionDuring" { try selection(mode, plan: plan, container: store.container) }
            if mode == "deletion" { context.insert(PendingCloudDeletionTask(scanId: scanID)) }
            if context.hasChanges { try context.save() }
            return stateData
        }
        let service = ObservationHistoryEnrollmentService(cloud: cloud)
        if ["success", "selectionReceipt", "selectionRejected"].contains(mode) {
            #expect(try await service.enroll(observationID: scanID, expectedOwnerID: plan.ownerID,
                container: store.container) == UUID(uuidString: analysis))
            let context = ModelContext(store.container); context.autosaveEnabled = false
            #expect(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first?.snapshotVersion == 8)
            #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority)
            #expect(try !ObservationHistoryEnrollmentIntent.holds(scanID, context: context))
            let selectedBefore = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID)
            var continuationCloud = cloud
            continuationCloud.begin = { _ in Issue.record("Acknowledged continuation acquired network work"); throw ObservationHistoryError.unavailable }
            // A new owner/fresh contexts must recover the durable association,
            // with no retained in-memory enrollment task or network request.
            for _ in 0..<2 {
                #expect(try await ObservationHistoryEnrollmentOwner().continueInitialHistory(observation: plan.scanID,
                    owner: plan.ownerID, generation: 1, container: store.container, cloud: continuationCloud,
                    isCurrent: { true }) == UUID(uuidString: analysis))
            }
            #expect(try ModelContext(store.container).fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == selectedBefore)
            // Duplicate initial delivery after enrollment cannot select the old result again.
            #expect(try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: fixture.response, account: account) == .retained)
            if mode == "success" {
                try await verifyAcknowledgedContinuation(plan: plan, analysis: analysis, container: store.container, cloud: continuationCloud)
            }
        } else {
            await #expect(throws: (any Error).self) {
                try await service.enroll(observationID: scanID, expectedOwnerID: plan.ownerID, container: store.container)
            }
            let context = ModelContext(store.container)
            #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
            #expect(try ObservationHistoryEnrollmentIntent.holds(scanID, context: context) == !["selectionBefore", "malformedSelection"].contains(mode))
        }
        #expect(calls == (["selectionBefore", "malformedSelection"].contains(mode) ? 0 : 1))
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
