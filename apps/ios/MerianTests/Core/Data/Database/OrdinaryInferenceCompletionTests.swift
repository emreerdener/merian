import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Ordinary completion proof", .sharedProcessState(.offlineQueueManager))
struct OrdinaryInferenceCompletionTests {
    @Test(arguments: ["success", "changedResult", "changedGeneration", "saveFailure"])
    func sealedEnrollmentUsesOriginalResultAndNeverFallsBack(_ mode: String) async throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v8.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        let originalText = try #require(items.first?["snapshot"] as? String)
        let original = try #require(JSONSerialization.jsonObject(with: Data(originalText.utf8)) as? [String: Any])
        let fixture = try await Fixture(initialSnapshot: original)
        defer { fixture.finish() }
        try #require(await fixture.persist(background: false))
        let context = ModelContext(fixture.container)
        let job = try #require(try context.fetchOfflineJob(id: fixture.jobID))
        job.status = .complete
        for queue in try context.fetch(FetchDescriptor<OfflineQueuedScan>()) { context.delete(queue) }
        try context.save()
        var snapshot = original
        if mode == "changedResult" {
            var result = try #require(snapshot["result"] as? [String: Any])
            result["scientific_name"] = "Different original result"
            snapshot["result"] = result
        }
        if mode == "changedGeneration" {
            var proof = try #require(snapshot["initial_evidence"] as? [String: Any])
            proof["generation"] = UUID().uuidString.lowercased()
            snapshot["initial_evidence"] = proof
        }
        let analysis = try #require(snapshot["analysis_id"] as? String)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = fixture.owner.uuidString.lowercased()
        state["observation_id"] = fixture.id; state["selected_analysis_id"] = analysis
        var item = try #require(state["analysis"] as? [String: Any])
        item["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), as: UTF8.self)
        state["analysis"] = item
        let stateData = try JSONSerialization.data(withJSONObject: state)
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "owner_id": fixture.owner.uuidString.lowercased(), "observation_id": fixture.id,
            "baseline_analysis_id": analysis])
        var legacyCalls = 0, initialCalls = 0, saves = 0
        var cloud = ObservationHistoryCloudClient(begin: { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) },
            isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in legacyCalls += 1; throw ObservationHistoryError.unavailable }
        cloud.enrollInitial = { _ in initialCalls += 1; return receipt }
        cloud.fetchState = { _ in stateData }
        let service = ObservationHistoryEnrollmentService(cloud: cloud, save: { context in
            saves += 1
            if mode == "saveFailure", saves == 2 { throw OrdinaryInferenceCompletion.Invalid.evidence }
            try context.save()
        })
        if mode == "success" {
            #expect(try await service.enroll(observationID: fixture.id, expectedOwnerID: fixture.owner,
                container: fixture.container) == UUID(uuidString: analysis))
            let fresh = ModelContext(fixture.container)
            #expect(try fresh.fetch(FetchDescriptor<LocalAnalysisRecord>()).first?.snapshotVersion == 8)
            #expect(try !ObservationHistoryEnrollmentIntent.holds(fixture.id, context: fresh))
        } else {
            await #expect(throws: (any Error).self) {
                try await service.enroll(observationID: fixture.id, expectedOwnerID: fixture.owner, container: fixture.container)
            }
            let fresh = ModelContext(fixture.container)
            #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
            #expect(try ObservationHistoryEnrollmentIntent.holds(fixture.id, context: fresh))
        }
        #expect(initialCalls == 1 && legacyCalls == 0)
    }

    @Test(arguments: [false, true])
    func sealedReplayUsesStableSubmissionAcrossAttempts(background: Bool) async throws {
        var fixture = try await Fixture(withInitialEvidence: true)
        defer { fixture.finish() }
        try #require(await fixture.persist(background: background))
        let oldCompletion = fixture.completion, oldOwnership = fixture.ownership
        try fixture.rotateAttempt()
        let before = try fixture.metadata()
        let actor = BackgroundDatabaseActor(modelContainer: fixture.container)
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: fixture.id)
        let stale = await actor.persistOfflineScanResultAssumingPersistenceLock(mappedData: fixture.mapped,
            originalImagePaths: [], scanId: fixture.id, originalTimestamp: Date(), observationContextsJSON: nil,
            audioFilePaths: nil, videoFilePaths: nil, capturedMediaJSON: "[]",
            originalCompletion: oldCompletion, originalOwnership: oldOwnership)
        await ScanInferencePersistenceCoordinator.shared.release(scanId: fixture.id)
        #expect(!stale.wasCleaned)
        try #require(await fixture.persist(background: background))
        #expect(try fixture.metadata() == before)
        let context = ModelContext(fixture.container)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(try OrdinaryInferenceCompletion.retainedInitial(for: scan, owner: fixture.owner, context: context) == fixture.initialEvidence)
    }

    @Test(arguments: [false, true])
    func sealedCompletionSurvivesBothWritersAndRestart(backgroundFirst: Bool) async throws {
        let fixture = try await Fixture(withInitialEvidence: true)
        defer { fixture.finish() }
        try #require(await fixture.persist(background: backgroundFirst))
        let first = try fixture.metadata()
        try #require(await fixture.persist(background: !backgroundFirst))
        #expect(try fixture.metadata() == first)
        let context = ModelContext(fixture.container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(try OrdinaryInferenceCompletion.retainedInitial(for: scan, owner: fixture.owner, context: context) == fixture.initialEvidence)
        let job = try #require(try context.fetchOfflineJob(id: fixture.jobID))
        var object = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
        var proof = try #require(object[OrdinaryInitialEvidenceProof.completionKey] as? [String: Any])
        proof["generation"] = UUID().uuidString
        object[OrdinaryInitialEvidenceProof.completionKey] = proof
        job.metadataJSON = OfflineScanJobMetadataContract.json(from: object)
        try context.save()
        #expect(throws: (any Error).self) {
            try OrdinaryInferenceCompletion.retainedInitial(for: scan, owner: fixture.owner, context: context)
        }
        #expect(await !fixture.persist(background: !backgroundFirst))
    }

    @Test(arguments: ["absentExpectation", "changedExpectation", "missingFunding", "wrongGeneration", "missingJob"])
    func sealedCompletionCannotFallBackToLegacyPersistence(_ mode: String) async throws {
        let fixture = try await Fixture(withInitialEvidence: true)
        defer { fixture.finish() }
        let context = ModelContext(fixture.container)
        let job = try #require(try context.fetchOfflineJob(id: fixture.jobID))
        var object = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
        switch mode {
        case "absentExpectation": object.removeValue(forKey: OrdinaryInitialEvidenceProof.expectationKey)
        case "changedExpectation":
            var expected = try #require(object[OrdinaryInitialEvidenceProof.expectationKey] as? [String: Any])
            expected["generation"] = UUID().uuidString
            object[OrdinaryInitialEvidenceProof.expectationKey] = expected
        case "missingFunding": object = [OrdinaryInitialEvidenceProof.expectationKey: try fixture.initialEvidence!.submission.object()]
        case "wrongGeneration":
            job.metadataJSON = InferenceGenerationMetadataContract.setting(UUID(), in: job.metadataJSON)
            object = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
        case "missingJob": context.delete(job)
        default: Issue.record("Unexpected mode")
        }
        if mode != "missingJob" { job.metadataJSON = OfflineScanJobMetadataContract.json(from: object) }
        try context.save()
        #expect(await !fixture.persist(background: false))
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
    }

    @Test func replayCannotResurrectPristineEligibilityAfterReview() async throws {
        let fixture = try await Fixture()
        defer { fixture.finish() }
        try #require(await fixture.persist(background: true))
        let context = ModelContext(fixture.container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.userConfirmedIdentification = true
        scan.fieldNotes = "Keep the owner's subsequent edit."
        try context.save()
        let before = try fixture.metadata()
        try #require(await fixture.persist(background: false))
        let fresh = ModelContext(fixture.container)
        let replayed = try #require(fresh.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(replayed.userConfirmedIdentification)
        #expect(replayed.fieldNotes == scan.fieldNotes)
        #expect(try fixture.metadata() == before)
        let fetched = try fresh.fetchOfflineJob(id: fixture.jobID)
        let job = try #require(fetched)
        job.status = .complete
        for queue in try fresh.fetch(FetchDescriptor<OfflineQueuedScan>()) { fresh.delete(queue) }
        try fresh.save()
        var enrollments = 0
        var cloud = ObservationHistoryCloudClient(begin: { owner in
            .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in enrollments += 1; throw ObservationHistoryError.unavailable }
        await #expect(throws: (any Error).self) {
            try await ObservationHistoryEnrollmentService(cloud: cloud).enroll(
                observationID: fixture.id, expectedOwnerID: fixture.owner, container: fixture.container)
        }
        #expect(enrollments == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
    }

    @Test(arguments: [false, true])
    func firstInsertAndOppositeWriterReplayPreserveProof(backgroundFirst: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.finish() }
        #expect(await fixture.persist(background: backgroundFirst))
        let first = try fixture.metadata()
        #expect(first.contains(OrdinaryInferenceCompletion.metadataKey))
        #expect(await fixture.persist(background: !backgroundFirst))
        #expect(try fixture.metadata() == first)
        let context = ModelContext(fixture.container)
        let fetchedJob = try context.fetchOfflineJob(id: fixture.jobID)
        let job = try #require(fetchedJob)
        job.status = .complete
        try context.save()
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let retained = try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context)
        let proof = try #require(retained)
        #expect(proof.generation == fixture.generation)
        scan.fieldNotes = "Later notes are not result evidence."
        scan.wikipediaOverview = "Later dictionary enrichment."
        #expect(try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context) == proof)
        #expect(throws: (any Error).self) {
            try OrdinaryInferenceCompletion.retained(for: scan, owner: UUID(), context: context)
        }
        scan.aiReasoning = "Edited result"
        #expect(throws: (any Error).self) {
            try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context)
        }
        scan.aiReasoning = fixture.mapped.aiReasoning
        scan.userConfirmedIdentification = true
        #expect(throws: (any Error).self) {
            try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context)
        }
    }

    @Test(arguments: ["missingFunding", "wrongOwner", "released", "malformed", "finishedScope", "wrongGeneration", "existingRow"])
    func damagedOrNonoriginalInputsCannotMintProof(mode: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.finish() }
        let context = ModelContext(fixture.container)
        let fetchedJob = try context.fetchOfflineJob(id: fixture.jobID)
        let job = try #require(fetchedJob)
        switch mode {
        case "missingFunding": job.metadataJSON = InferenceGenerationMetadataContract.json(for: fixture.generation)
        case "wrongOwner":
            job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(
                .init(accountId: UUID(), scanId: fixture.id, source: .paidPro), in: job.metadataJSON)
        case "released": job.metadataJSON = OfflineScanJobMetadataContract.markingFundingReleased(in: job.metadataJSON)
        case "malformed": job.metadataJSON = "{\"inference_generation\":\"\(fixture.generation)\",\"broken\":"
        case "finishedScope": fixture.scope.finish()
        case "wrongGeneration": job.metadataJSON = InferenceGenerationMetadataContract.setting(UUID(), in: job.metadataJSON)
        case "existingRow":
            context.insert(LocalScanRecordFactory.makeRecord(from: fixture.mapped, recordId: fixture.id,
                speciesId: UUID().uuidString, timestamp: Date(), captureDate: Date(),
                capturedMediaJSON: "[]", coverImagePath: nil, isLiveCapture: false, fieldNotes: nil))
        default: Issue.record("Unknown mode")
        }
        try context.save()
        let saved = await fixture.persist(background: false)
        if ["finishedScope", "wrongGeneration", "malformed"].contains(mode) { #expect(!saved) }
        #expect(try !fixture.metadata().contains(OrdinaryInferenceCompletion.metadataKey))
    }

    @Test(arguments: ["unknownKey", "wrongVersion", "oversized", "duplicateMetadata"])
    func retainedProofCorruptionCannotBecomeAbsence(mode: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.finish() }
        try #require(await fixture.persist(background: true))
        let context = ModelContext(fixture.container)
        let fetchedJob = try context.fetchOfflineJob(id: fixture.jobID)
        let job = try #require(fetchedJob)
        var metadata = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
        var proof = try #require(metadata[OrdinaryInferenceCompletion.metadataKey] as? [String: Any])
        switch mode {
        case "unknownKey": proof["future"] = 1
        case "wrongVersion": proof["version"] = 2
        case "oversized": proof["resultSHA256"] = String(repeating: "a", count: OrdinaryInferenceCompletion.maximumBytes + 1)
        default: break
        }
        metadata[OrdinaryInferenceCompletion.metadataKey] = proof
        job.metadataJSON = OfflineScanJobMetadataContract.json(from: metadata)
        if mode == "duplicateMetadata" {
            let raw = try #require(job.metadataJSON)
            job.metadataJSON = "{\"duplicate\":1,\"duplicate\":2," + raw.dropFirst()
        }
        job.status = .complete
        try context.save()
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(throws: (any Error).self) {
            try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context)
        }
    }

    @Test(arguments: ["success", "candidate", "reordered", "noProof", "staleProjection"])
    func ordinaryEnrollmentPreservesMappedDisplayAndRecoversOriginalIntent(_ mode: String) async throws {
        let fixture = try await Fixture(withCandidates: true)
        defer { fixture.finish() }
        try #require(await fixture.persist(background: false))
        let context = ModelContext(fixture.container)
        let job = try #require(try context.fetchOfflineJob(id: fixture.jobID))
        job.status = .complete
        for queued in try context.fetch(FetchDescriptor<OfflineQueuedScan>()) { context.delete(queued) }
        if mode == "noProof" {
            var metadata = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
            metadata.removeValue(forKey: OrdinaryInferenceCompletion.metadataKey)
            job.metadataJSON = OfflineScanJobMetadataContract.json(from: metadata)
        }
        try context.save()
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let baseline = ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: UUID(uuidString: fixture.id)!)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = fixture.owner.uuidString.lowercased(); state["observation_id"] = fixture.id
        var item = state["analysis"] as! [String: Any]
        var envelope = try JSONSerialization.jsonObject(with: Data((item["snapshot"] as! String).utf8)) as! [String: Any]
        envelope["observation_id"] = fixture.id
        var saved = envelope["result"] as! [String: Any]
        saved["scan_id"] = fixture.id; saved["species_id"] = UUID().uuidString.lowercased()
        saved["ai_confidence_score"] = scan.confidenceScore
        saved["is_biological_subject"] = scan.isBiological
        saved["ai_reasoning"] = (scan.aiReasoning as Any?) ?? NSNull()
        saved["inference_tier"] = (scan.inferenceTier as Any?) ?? NSNull()
        saved["primary_identification"] = NSNull(); saved["identification_provenance"] = NSNull(); saved["pet_identification"] = NSNull()
        var wireCandidates: [[String: Any]] = [["scientific_name": "Synthetic alternative", "common_name": "First, Second",
            "confidence_score": mode == "candidate" ? 0.6 : 0.4, "distinguishing_feature": "Synthetic feature"],
            ["scientific_name": "Another alternative", "common_name": NSNull(), "confidence_score": 0.2, "distinguishing_feature": NSNull()]]
        if mode == "reordered" { wireCandidates.reverse() }
        saved["candidates"] = wireCandidates
        envelope["result"] = saved
        item["snapshot"] = String(bytes: try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]), encoding: .utf8)!
        state["analysis"] = item
        let stateData = try JSONSerialization.data(withJSONObject: state)
        let analysis = try #require(state["selected_analysis_id"] as? String)
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "owner_id": fixture.owner.uuidString.lowercased(),
            "observation_id": fixture.id, "baseline_analysis_id": analysis] as [String: Any])
        var calls = 0
        var cloud = ObservationHistoryCloudClient(begin: { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) },
            isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in calls += 1; return receipt }
        cloud.fetchState = { _ in
            if mode == "staleProjection" {
                let fresh = ModelContext(fixture.container)
                let row = try #require(fresh.fetch(FetchDescriptor<LocalScanRecord>()).first)
                row.aiReasoning = "Later result edit"; try fresh.save()
            }
            return stateData
        }
        let access = SavedIdentificationReanalysisAccess.prepared(cloud: cloud, enrollment: .init(), currentOwner: { fixture.owner },
            generation: { 1 }, sessionIsCurrent: { _ in true }, containerIsCurrent: { $0 === fixture.container }, dispatch: { _ in })
        let request = try access.prepare(fixture.id, baseline, fixture.container)
        if mode != "success" {
            await #expect(throws: (any Error).self) { try await request.resolve() }
            #expect(calls == 1)
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
            #expect(try ObservationHistoryEnrollmentIntent.holds(fixture.id, context: ModelContext(fixture.container)))
            return
        }
        let proof = try #require(try OrdinaryInferenceCompletion.retained(for: scan, owner: fixture.owner, context: context))
        let action = try await request.resolve()
        #expect(try action.resolve().analysisID == UUID(uuidString: analysis))
        let fresh = ModelContext(fixture.container)
        let cached = try #require(fresh.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first?.displaySnapshotData)
        let result = try ObservationHistoryState.decode(stateData, request: .init(observation_id: fixture.id, analysis_id: nil), ownerID: fixture.owner).result
        let restored = try ObservationHistoryDisplayProjection.restore(cached, matching: result)
        #expect(restored.speciesId == scan.speciesId && restored.candidatesData == scan.candidatesData)
        #expect(calls == 1)
        #expect(try !ObservationHistoryEnrollmentIntent.holds(fixture.id, context: fresh))
        #expect(try SavedIdentificationDisplayBaseline.captureOrdinary(restored, matching: result, proof: proof, owner: UUID()) == nil)
        let wrongScan = OrdinaryInferenceCompletion.Proof(version: proof.version, ownerID: proof.ownerID, scanID: UUID(),
            generation: proof.generation, resultSHA256: proof.resultSHA256, projection: proof.projection,
            speciesID: proof.speciesID, pristineReviewSHA256: proof.pristineReviewSHA256)
        #expect(try SavedIdentificationDisplayBaseline.captureOrdinary(restored, matching: result, proof: wrongScan, owner: fixture.owner) == nil)
        for changeIdentity in [false, true] {
            let changedResult = ObservationHistoryPage.Result(version: result.version, photos: result.photos, audio: result.audio,
                video: result.video, analysisID: changeIdentity ? UUID() : result.analysisID, completedAt: result.completedAt,
                importedAt: result.importedAt, bytes: changeIdentity ? result.bytes : result.bytes + Data(" ".utf8))
            #expect(throws: (any Error).self) { try ObservationHistoryDisplayProjection.restore(cached, matching: changedResult) }
        }
        // Restore is bound to the immutable imported bytes, not a forever-pristine job.
        fresh.delete(try #require(try fresh.fetchOfflineJob(id: fixture.jobID))); try fresh.save()
        #expect(try ObservationHistoryDisplayProjection.restore(cached, matching: result) == restored)
        var changed = try JSONSerialization.jsonObject(with: cached) as! [String: Any]
        changed["source_result_sha256"] = String(repeating: "0", count: 64)
        #expect(throws: (any Error).self) {
            try ObservationHistoryDisplayProjection.restore(JSONSerialization.data(withJSONObject: changed), matching: result)
        }
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let id: String
        let owner: UUID
        var generation: UUID
        let scope: InferenceCompletionAccountScope
        let mapped: SpeciesData
        var completion: OrdinaryInferenceCompletion
        let responseData: Data
        let initialEvidence: OrdinaryInitialEvidenceProof?
        var jobID: String { OfflineQueueManager.scanIngestionJobId(scanId: id) }
        var ownership: BackgroundAccountWorkOwnership { .init(ownerUserID: owner, generation: generation, phase: .inference) }

        init(withCandidates: Bool = false, withInitialEvidence: Bool = false, initialSnapshot: [String: Any]? = nil) async throws {
            container = try DatabaseActorTestSupport.makeIsolatedContainer()
            if let initialSnapshot, let proof = initialSnapshot["initial_evidence"] as? [String: Any] {
                id = try #require(initialSnapshot["observation_id"] as? String)
                owner = try ObservationHistoryPage.uuid(proof["owner_id"])
            } else { id = UUID().uuidString.lowercased(); owner = UUID() }
            generation = UUID()
            scope = .init(ownerID: owner, isCurrent: { true }, release: {})
            var data = Data("""
            {"success":true,"data":{"scan_id":"\(id)","is_biological_subject":true,"is_live_capture":false,
            "ecology_type":"wild","is_invasive":false,"scientific_name":"Danaus plexippus","common_name":"Monarch",
            \(withCandidates ? "\"candidates\":[{\"scientific_name\":\"Synthetic alternative\",\"common_name\":\"First, Second\",\"confidence_score\":0.4,\"distinguishing_feature\":\"Synthetic feature\"},{\"scientific_name\":\"Another alternative\",\"common_name\":null,\"confidence_score\":0.2,\"distinguishing_feature\":null}]," : "")
            "confidence_score":0.75,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic proof fixture."}}}
            """.utf8)
            if let initialSnapshot {
                data = try JSONSerialization.data(withJSONObject: ["success": true,
                    "data": initialSnapshot["result"]!, "initial_evidence": initialSnapshot["initial_evidence"]!], options: [.sortedKeys])
            } else if withInitialEvidence {
                var envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                envelope["initial_evidence"] = ["schema_version": 1, "owner_id": owner.uuidString.lowercased(),
                    "scan_id": id, "generation": UUID().uuidString.lowercased(), "evidence_digest": String(repeating: "a", count: 64)]
                data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            }
            let prepared = try await InferenceResponsePreparationService.live.prepare(resultData: data, telemetry: nil, audioFilePaths: nil, videoFilePaths: nil, expectedScanId: id)
            responseData = data
            mapped = prepared.mappedData
            initialEvidence = prepared.initialEvidence
            completion = try OrdinaryInferenceCompletion.prepare(resultData: data, mappedData: mapped,
                scanID: id, generation: generation, account: scope, initialEvidence: initialEvidence)
            let context = ModelContext(container)
            context.insert(OfflineQueuedScan(id: id, capturedMediaJSON: "[]", scanState: .inferencing))
            let job = OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: id), kind: .scanIngestion,
                subjectId: id, status: .running)
            job.metadataJSON = OfflineScanJobMetadataContract.json(generation: generation,
                funding: .init(accountId: owner, scanId: id, source: .paidPro))
            job.metadataJSON = OfflineScanJobMetadataContract.settingBackgroundAccountWork(
                .init(ownerUserID: owner, generation: generation, phase: .inference), in: job.metadataJSON)
            if let initialEvidence {
                var object = OfflineScanJobMetadataContract.object(from: job.metadataJSON)
                object[OrdinaryInitialEvidenceProof.expectationKey] = try initialEvidence.submission.object()
                job.metadataJSON = OfflineScanJobMetadataContract.json(from: object)
            }
            context.insert(job); try context.save()
            OfflineQueueManager.shared.foregroundInferenceGenerations[id] = generation
            OfflineQueueManager.shared.startedForegroundInferenceGenerations[id] = generation
        }

        func persist(background: Bool) async -> Bool {
            let actor = BackgroundDatabaseActor(modelContainer: container)
            if background {
                await ScanInferencePersistenceCoordinator.shared.acquire(scanId: id)
                let result = await actor.persistOfflineScanResultAssumingPersistenceLock(mappedData: mapped,
                    originalImagePaths: [], scanId: id, originalTimestamp: Date(), observationContextsJSON: nil,
                    audioFilePaths: nil, videoFilePaths: nil, capturedMediaJSON: "[]",
                    originalCompletion: completion, originalOwnership: ownership)
                await ScanInferencePersistenceCoordinator.shared.release(scanId: id)
                return result.wasCleaned
            }
            return await actor.saveNonVisualRecord(mappedData: mapped,
                persistenceFence: .init(scanId: id, generation: generation), originalCompletion: completion).wasSaved
        }

        mutating func rotateAttempt() throws {
            generation = UUID()
            completion = try OrdinaryInferenceCompletion.prepare(resultData: responseData, mappedData: mapped,
                scanID: id, generation: generation, account: scope, initialEvidence: initialEvidence)
            let context = ModelContext(container)
            let job = try #require(try context.fetchOfflineJob(id: jobID))
            job.metadataJSON = InferenceGenerationMetadataContract.setting(generation, in: job.metadataJSON)
            job.metadataJSON = OfflineScanJobMetadataContract.settingBackgroundAccountWork(ownership, in: job.metadataJSON)
            try context.save()
            OfflineQueueManager.shared.foregroundInferenceGenerations[id] = generation
            OfflineQueueManager.shared.startedForegroundInferenceGenerations[id] = generation
        }

        func metadata() throws -> String {
            let job = try ModelContext(container).fetchOfflineJob(id: jobID)
            return try #require(job?.metadataJSON)
        }

        func finish() {
            scope.finish()
            OfflineQueueManager.shared.foregroundInferenceGenerations[id] = nil
            OfflineQueueManager.shared.startedForegroundInferenceGenerations[id] = nil
        }
    }
}
