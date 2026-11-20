import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryEnrollmentTests {
    let support = ObservationHistoryStateSyncTests()
    typealias Failure = ObservationHistoryEnrollmentService.AdmissionError

    func receipt() throws -> Data {
        Data(try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-v1.json").utf8)
    }

    func container() throws -> ModelContainer {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        try support.update(container) { scan, _ in
            scan.analysisOwnerAccountID = nil
            scan.selectedAnalysisID = nil
            scan.observationStateRevision = nil
        }
        return container
    }

    func service(state: Data? = nil, duringEnroll: @escaping () throws -> Void = {},
                 duringRead: @escaping () throws -> Void = {}, current: @escaping () -> Bool = { true },
                 finish: @escaping () -> Void = {}) -> ObservationHistoryEnrollmentService {
        var cloud = support.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: current, finish: finish)
        cloud.enroll = { observation in
            #expect(observation == UUID(uuidString: support.support.observation))
            try duringEnroll()
            return try receipt()
        }
        cloud.fetchState = { request in
            #expect(request.analysis_id == nil && request.observation_id == support.support.observation)
            try duringRead()
            return try state ?? support.fixture(revision: 1)
        }
        return .init(cloud: cloud)
    }

    func run(_ service: ObservationHistoryEnrollmentService, _ container: ModelContainer) async throws -> UUID {
        try await service.enroll(observationID: support.support.observation,
            expectedOwnerID: support.support.owner, container: container)
    }

    func expectUnenrolled(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        if let scan = try context.fetch(FetchDescriptor<LocalScanRecord>()).first {
            #expect(scan.analysisOwnerAccountID == nil && scan.selectedAnalysisID == nil && scan.observationStateRevision == nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 0)
    }

    func recoveredResponse(_ container: ModelContainer) throws -> Data {
        let child = try #require(ModelContext(container).fetch(FetchDescriptor<LocalAnalysisRecord>()).first { $0.snapshotVersion == 3 })
        var response = try JSONSerialization.jsonObject(with: receipt()) as! [String: Any]
        response["snapshot"] = (try #require(String(data: child.resultSnapshotData, encoding: .utf8))) as String
        response["snapshot_sha256"] = ObservationHistoryEnrollmentIntent.baselineDigest(child.resultSnapshotData)
        return try support.support.bytes(response)
    }

    func legacyImportedContainer() async throws -> ModelContainer {
        let store = try container()
        _ = try await run(service(), store)
        let context = ModelContext(store)
        let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(support.support.observation)))
        context.delete(job); try context.save()
        return store
    }

    func advancedPair(media: String = "photo") throws -> [String: Any] {
        var original = try ObservationHistoryStateTests().fixture()
        var selected = try JSONSerialization.jsonObject(with: ObservationHistorySelectionSyncTests().nativeResponse(revision: 8)) as! [String: Any]
        if media != "photo" {
            let data = Data(try DatabaseActorTestSupport.loadRepositorySource(at:
                "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-selection-media-v1.json").utf8)
            let vectors = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            let vector = try #require(vectors.first { $0["media"] as? String == media })
            let pair = try #require(vector["pair"] as? [String: Any])
            selected = try #require(pair["selected_state"] as? [String: Any])
        }
        original["state_revision"] = 8; original["selected_analysis_id"] = selected["selected_analysis_id"]
        let snapshot = (original["analysis"] as! [String: Any])["snapshot"] as! String
        return ["schema_version": 1, "baseline_sha256": ObservationHistoryEnrollmentIntent.baselineDigest(Data(snapshot.utf8)),
                "baseline_state": original, "selected_state": selected]
    }

    @Test(arguments: ["photo", "audio", "video"])
    func pairedEnrollmentImportsOriginalAndCurrentWithoutSelectingOriginal(_ media: String) async throws {
        let store = try container(), pair = try advancedPair(media: media)
        try support.update(store) { scan, _ in
            scan.confirmedSpeciesIdentityData = nil; scan.aiIdentificationReviewData = nil
            scan.coverImagePath = "synthetic-local-photo.jpg"; scan.capturedMediaJSON = "[]"
        }
        let old = try #require(ModelContext(store).fetch(FetchDescriptor<LocalScanRecord>()).first)
        let saved = AnalysisDisplaySnapshot(analysisID: UUID(uuidString: support.analysisID)!, record: old)
        var service = service(state: try support.support.bytes(try #require(pair["selected_state"] as? [String: Any])))
        service.cloud.reconcileEnrollment = { _ in try support.support.bytes(pair) }
        service.cloud.select = { _ in Issue.record("First import requested selection"); throw ObservationHistoryError.unavailable }
        #expect(try await run(service, store) == UUID(uuidString: support.analysisID))
        let context = ModelContext(store), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let rows = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        let selected = try #require(pair["selected_state"] as? [String: Any])
        let selectedID = try #require(selected["selected_analysis_id"] as? String)
        #expect(rows.count == 2 && scan.selectedAnalysisID == selectedID && scan.observationStateRevision == 8)
        let original = try #require(rows.first { $0.id == support.analysisID })
        #expect(try SavedIdentificationDisplayBaseline.restore(#require(original.state?.displaySnapshotData), analysisID: UUID(uuidString: support.analysisID)!) == saved)
        let current = try #require(rows.first { $0.id == scan.selectedAnalysisID })
        let display = try AnalysisDisplaySnapshot.restore(#require(current.state?.displaySnapshotData), analysisID: UUID(uuidString: current.id)!)
        #expect(AnalysisDisplaySnapshot(analysisID: display.analysisID, record: scan) == display)
        #expect(scan.fieldNotes == "Preserved private note" && scan.customTags == ["Preserved tag"])
        #expect(scan.coverImagePath == "synthetic-local-photo.jpg" && scan.capturedMediaJSON == "[]")
        #expect(try !ObservationHistoryEnrollmentIntent.holds(support.support.observation, context: context))
    }

    @Test(arguments: ["edit", "undo", "deletion", "account", "pair-revision", "projection"])
    func pairedEnrollmentCannotCrossLocalOrServerFences(_ fault: String) async throws {
        let store = try container()
        var pair = try advancedPair(), current = true
        var service = service(state: try support.support.bytes(try #require(pair["selected_state"] as? [String: Any])), current: { current })
        service.cloud.reconcileEnrollment = { _ in
            if fault == "account" { current = false }
            try support.update(store) { scan, context in
                if fault == "edit" { scan.commonName = "Later local edit" }
                if fault == "undo" { scan.userIdentificationOverride = "Unacknowledged correction" }
                if fault == "deletion" { context.insert(PendingCloudDeletionTask(scanId: scan.id)) }
            }
            if fault == "pair-revision" {
                var selected = pair["selected_state"] as! [String: Any]; selected["state_revision"] = 9; pair["selected_state"] = selected
            }
            if fault == "projection" {
                var selected = pair["selected_state"] as! [String: Any], item = selected["analysis"] as! [String: Any]
                let original = (pair["baseline_state"] as! [String: Any])["analysis"] as! [String: Any]
                var snapshot = try JSONSerialization.jsonObject(with: Data((original["snapshot"] as! String).utf8)) as! [String: Any]
                snapshot["analysis_id"] = selected["selected_analysis_id"]
                item["snapshot"] = String(decoding: try support.support.bytes(snapshot), as: UTF8.self)
                selected["analysis"] = item; pair["selected_state"] = selected
            }
            return try support.support.bytes(pair)
        }
        await #expect(throws: (any Error).self) { try await run(service, store) }
        try expectUnenrolled(store)
        #expect(try ObservationHistoryEnrollmentIntent.holds(support.support.observation, context: ModelContext(store)))
    }

    @Test func sharedSelectionPairRejectsMalformedMixedAndOversizeState() throws {
        let data = Data(try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-selection-v1.json").utf8)
        let observation = try #require(UUID(uuidString: support.support.observation))
        let receipt = try ObservationHistoryEnrollment.decode(receipt(), observationID: observation, ownerID: support.support.owner)
        let parsed = try ObservationHistoryEnrollmentSelection.decode(data, observation: observation, owner: support.support.owner, receipt: receipt)
        #expect(parsed.baseline.result.version == 3 && parsed.selected.result.version == 1 && parsed.baseline.revision == parsed.selected.revision)
        let mediaData = Data(try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-selection-media-v1.json").utf8)
        let media = try JSONSerialization.jsonObject(with: mediaData) as! [[String: Any]]
        for vector in media {
            let pair = try ObservationHistoryEnrollmentSelection.decode(support.support.bytes(try #require(vector["pair"] as? [String: Any])), observation: observation, owner: support.support.owner, receipt: receipt)
            let version = try #require(vector["version"] as? Int)
            #expect(pair.baseline.result.version == 3 && pair.selected.result.version == version)
        }
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for patch: [String: Any] in [["baseline_state": "invalid"], ["selected_state": NSNull()], ["baseline_sha256": "bad"], ["schema_version": true], ["intent_id": observation.uuidString]] {
            #expect(throws: (any Error).self) {
                try ObservationHistoryEnrollmentSelection.decode(support.support.bytes(value.merging(patch) { _, new in new }), observation: observation, owner: support.support.owner, receipt: receipt)
            }
        }
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollmentSelection.decode(Data(repeating: 32, count: 4_194_305), observation: observation, owner: support.support.owner, receipt: receipt)
        }
    }

    @Test(arguments: [false, true])
    func pairedImportUncertainSaveRetainsOriginalIntentOrExactSelectedOutcome(_ afterSave: Bool) async throws {
        let store = try container(), pair = try advancedPair()
        let observation = try #require(UUID(uuidString: support.support.observation))
        var service = service(state: try support.support.bytes(try #require(pair["selected_state"] as? [String: Any]))), saves = 0
        var intentID: UUID?
        service.cloud.reconcileEnrollment = { _ in
            intentID = try ObservationHistoryEnrollmentIntent.existing(observationID: observation, ownerID: support.support.owner, context: ModelContext(store))?.intentID
            return try support.support.bytes(pair)
        }
        service.save = { context in
            saves += 1
            if saves == 2 && !afterSave { throw ObservationHistoryError.unavailable }
            try context.save()
            if saves == 2 { throw ObservationHistoryError.unavailable }
        }
        await #expect(throws: (any Error).self) { try await run(service, store) }
        if afterSave {
            try support.update(store) { scan, _ in scan.selectedAnalysisID = UUID().uuidString.lowercased(); scan.fieldNotes = "Later preserved notes" }
            var cloud = service.cloud
            cloud.enroll = { _ in Issue.record("Uncertain import reenrolled"); throw ObservationHistoryError.unavailable }
            cloud.reconcileEnrollment = { _ in Issue.record("Uncertain import reprojected B"); throw ObservationHistoryError.unavailable }
            cloud.recoverBaseline = { _ in try recoveredResponse(store) }
            let before = try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store)
            #expect(try await ObservationHistoryEnrollmentOwner().continueInitialHistory(observation: observation, owner: support.support.owner, generation: 1, container: store, cloud: cloud, isCurrent: { true }) == before.analysisID)
            #expect(try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store) == before)
        } else {
            try expectUnenrolled(store)
            #expect(try ObservationHistoryEnrollmentIntent.existing(observationID: observation, ownerID: support.support.owner, context: ModelContext(store))?.intentID == intentID)
            service.save = { try $0.save() }
            _ = try await run(service, store)
        }
        let baseline = try #require(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: support.support.owner, context: ModelContext(store)))
        #expect(baseline.intentID == intentID && baseline.version == 1)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
    }

    @Test func strictRecoveryContractPreservesSharedBytesAndRejectsForgedAssociation() throws {
        let data = Data(try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/baseline-recovery-v1.json").utf8)
        let observation = try #require(UUID(uuidString: support.support.observation))
        let recovered = try ObservationHistoryBaselineRecovery.decode(data, observationID: observation, ownerID: support.support.owner)
        #expect(recovered.result.version == 3 && recovered.result.analysisID == UUID(uuidString: support.analysisID))
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(recovered.result.bytes == Data((value["snapshot"] as! String).utf8))
        for patch: [String: Any] in [["schema_version": true], ["owner_id": observation.uuidString.lowercased()],
            ["baseline_analysis_id": support.support.owner.uuidString.lowercased()], ["snapshot_sha256": String(repeating: "0", count: 64)],
            ["snapshot": (value["snapshot"] as! String) + " "], ["intent_id": observation.uuidString], ["selected_analysis_id": support.analysisID]] {
            #expect(throws: (any Error).self) {
                try ObservationHistoryBaselineRecovery.decode(support.support.bytes(value.merging(patch) { _, new in new }),
                    observationID: observation, ownerID: support.support.owner)
            }
        }
    }

    @Test func recoveredBaselinePreservesLaterSelectionAndReplaysWithoutWrite() async throws {
        let store = try await legacyImportedContainer(), observation = try #require(UUID(uuidString: support.support.observation))
        try support.update(store) { scan, _ in scan.selectedAnalysisID = UUID().uuidString.lowercased(); scan.fieldNotes = "Later notes" }
        let expected = try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store)
        let data = try recoveredResponse(store)
        var cloud = service().cloud, calls = 0
        cloud.enroll = { _ in Issue.record("Association recovery attempted enrollment"); throw ObservationHistoryError.unavailable }
        cloud.recoverBaseline = { _ in calls += 1; return data }
        let owner = ObservationHistoryEnrollmentOwner()
        #expect(try await owner.continueInitialHistory(observation: observation, owner: support.support.owner, generation: 1,
            container: store, cloud: cloud, isCurrent: { true }) == expected.analysisID)
        let association = try #require(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation,
            ownerID: support.support.owner, context: ModelContext(store)))
        #expect(association.version == 2 && association.intentID == nil && association.provenance == .serverRecovery)
        let native = try NativeHistoryAssociation(association)
        #expect(native.intentID == nil && native.provenance == .serverRecovery)
        #expect(try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store) == expected)
        var saves = 0
        var recovery = ObservationHistoryEnrollmentService(cloud: cloud)
        recovery.save = { _ in saves += 1; Issue.record("Exact association replay wrote state") }
        #expect(try await recovery.recoverBaseline(observation: observation, owner: support.support.owner, container: store, expected: expected) == expected.analysisID)
        #expect(saves == 0 && calls == 2 && !owner.contains(observation))
    }

    @Test(arguments: [false, true])
    func recoverySaveFailureReconcilesOnlyDurableAssociation(_ afterSave: Bool) async throws {
        let store = try await legacyImportedContainer(), observation = try #require(UUID(uuidString: support.support.observation))
        let expected = try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store)
        let data = try recoveredResponse(store)
        var cloud = service().cloud
        cloud.enroll = { _ in Issue.record("Recovery attempted enrollment"); throw ObservationHistoryError.unavailable }
        cloud.recoverBaseline = { _ in data }
        var recovery = ObservationHistoryEnrollmentService(cloud: cloud)
        recovery.save = { context in
            if afterSave { try context.save() }
            throw ObservationHistoryError.unavailable
        }
        await #expect(throws: (any Error).self) {
            try await recovery.recoverBaseline(observation: observation, owner: support.support.owner, container: store, expected: expected)
        }
        let stored = try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: support.support.owner, context: ModelContext(store))
        #expect((stored != nil) == afterSave)
        var saves = 0
        recovery.save = { context in saves += 1; try context.save() }
        #expect(try await recovery.recoverBaseline(observation: observation, owner: support.support.owner, container: store, expected: expected) == expected.analysisID)
        #expect(saves == (afterSave ? 0 : 1))
        #expect(try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store) == expected)
    }

    @Test(arguments: ["account", "deletion", "display", "active-intent", "different-bytes"])
    func recoveryAssociationCannotCrossSuspendedFence(_ fault: String) async throws {
        let store = try await legacyImportedContainer(), observation = try #require(UUID(uuidString: support.support.observation))
        let expected = try ObservationHistoryEnrollmentService.baselineRecoveryAdmission(observation: observation, owner: support.support.owner, container: store)
        var current = true
        var cloud = service(current: { current }).cloud
        let data = try recoveredResponse(store)
        cloud.enroll = { _ in Issue.record("Recovery enrolled"); throw ObservationHistoryError.unavailable }
        cloud.recoverBaseline = { _ in
            if fault == "account" { current = false }
            if fault == "different-bytes" {
                var value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let text = (value["snapshot"] as! String) + " "
                value["snapshot"] = text; value["snapshot_sha256"] = ObservationHistoryEnrollmentIntent.baselineDigest(Data(text.utf8))
                return try support.support.bytes(value)
            }
            try support.update(store) { scan, context in
                if fault == "deletion" { context.insert(PendingCloudDeletionTask(scanId: scan.id)) }
                if fault == "display" { scan.commonName = "Later selected result" }
                if fault == "active-intent" { _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: support.support.owner, context: context) }
            }
            return data
        }
        await #expect(throws: (any Error).self) {
            try await ObservationHistoryEnrollmentService(cloud: cloud).recoverBaseline(observation: observation,
                owner: support.support.owner, container: store, expected: expected)
        }
        #expect(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: support.support.owner, context: ModelContext(store)) == nil)
    }

    @Test func strictSharedReceiptIsNotSelectionAuthority() throws {
        let id = UUID(uuidString: support.support.observation)!, owner = support.support.owner
        #expect(try ObservationHistoryEnrollment.decode(receipt(), observationID: id, ownerID: owner).baselineAnalysisID == UUID(uuidString: support.analysisID))
        let value = try JSONSerialization.jsonObject(with: receipt()) as! [String: Any]
        let patches: [[String: Any]] = [["owner_id": id.uuidString.lowercased()], ["observation_id": owner.uuidString.lowercased()],
            ["baseline_analysis_id": owner.uuidString.lowercased()], ["baseline_analysis_id": id.uuidString.lowercased()],
            ["schema_version": true], ["schema_version": 2], ["selected_analysis_id": support.analysisID],
            ["baseline_analysis_id": NSNull()], ["state_revision": 1]]
        for patch in patches {
            #expect(throws: (any Error).self) {
                try ObservationHistoryEnrollment.decode(support.support.bytes(value.merging(patch) { _, new in new }), observationID: id, ownerID: owner)
            }
        }
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollment.decode(Data(repeating: 32, count: 4097), observationID: id, ownerID: owner)
        }
    }

    @Test func enrollmentAtomicallyPreservesSavedProjectionAndItsOwnAuthority() async throws {
        for confirmed in [false, true] {
            let container = try container()
            let response = try confirmed ? ObservationHistorySelectionSyncTests().confirmedResponse(revision: 10) : support.fixture(revision: 10, rejected: true)
            let state = try ObservationHistoryState.decode(response,
                request: .init(observation_id: support.support.observation, analysis_id: nil), ownerID: support.support.owner)
            try support.update(container) { scan, _ in
                scan.aiIdentificationReviewData = try LocalAIIdentificationReview(authority: state.review.aiReview).storedData()
                if let review = state.review.speciesReview { scan.confirmedSpeciesIdentityData = try review.storedData() }
                scan.confirmedSpeciesId = state.review.confirmedSpeciesID
                scan.userIdentificationOverride = state.review.override
                scan.userConfirmedIdentification = state.review.confirmed ?? false
                scan.userReviewStateRaw = state.review.state?.rawValue
                scan.capturedMediaJSON = "[]"
                scan.coverImagePath = "synthetic-local-photo.jpg"
            }
            let before = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
            let display = AnalysisDisplaySnapshot(analysisID: state.selectedAnalysisID, record: before)
            let review = before.aiIdentificationReviewData, identity = before.confirmedSpeciesIdentityData
            #expect(try await run(service(state: response), container) == state.selectedAnalysisID)
            let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            #expect(scan.analysisOwnerAccountID == support.support.owner.uuidString.lowercased())
            #expect(scan.selectedAnalysisID == support.analysisID && scan.observationStateRevision == 10)
            #expect(AnalysisDisplaySnapshot(analysisID: state.selectedAnalysisID, record: scan) == display)
            #expect(scan.aiIdentificationReviewData == review && scan.confirmedSpeciesIdentityData == identity)
            #expect(scan.fieldNotes == "Preserved private note" && scan.customTags == ["Preserved tag"])
            #expect(scan.coverImagePath == "synthetic-local-photo.jpg" && scan.capturedMediaJSON == "[]")
            let child = try #require(scan.analysisRecords?.first)
            #expect(child.completedAt == nil && child.resultSnapshotData == state.result.bytes)
            #expect(child.state?.reviewSnapshotData == state.review.data)
            #expect(try SavedIdentificationDisplayBaseline.restore(#require(child.state?.displaySnapshotData), analysisID: state.selectedAnalysisID) == display)
            await #expect(throws: ObservationHistoryError.unavailable) { try await run(service(), container) }
            #expect(try support.support.count(container) == 1)
        }
    }

    @Test(arguments: [false, true])
    func baselineAssociationCommitsWithImportAndSurvivesLaterSelection(_ afterSave: Bool) async throws {
        let container = try container(), owner = support.support.owner
        let observation = try #require(UUID(uuidString: support.support.observation))
        var service = service(), saves = 0
        service.save = { context in
            saves += 1
            if saves == 2 && !afterSave { throw ObservationHistoryError.unavailable }
            try context.save()
            if saves == 2 { throw ObservationHistoryError.unavailable }
        }
        await #expect(throws: ObservationHistoryError.unavailable) { try await run(service, container) }
        if !afterSave {
            try expectUnenrolled(container)
            #expect(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: ModelContext(container)) == nil)
            #expect(try await run(self.service(), container) == UUID(uuidString: support.analysisID))
        }
        let context = ModelContext(container)
        let association = try #require(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: context))
        #expect(association.baselineAnalysisID == UUID(uuidString: support.analysisID))
        #expect(association.ownerID == owner && association.observationID == observation)
        #expect(try !ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: context))
        let child = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(association.snapshotSHA256 == ObservationHistoryEnrollmentIntent.baselineDigest(child.resultSnapshotData))
        let later = UUID().uuidString.lowercased()
        try support.update(container) { scan, _ in scan.selectedAnalysisID = later; scan.fieldNotes = "Later notes" }
        #expect(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: ModelContext(container)) == association)
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: UUID(), context: ModelContext(container))
        }
        let deleting = ModelContext(container)
        try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(observation.uuidString, context: deleting)
        try deleting.save()
        let deleted = ModelContext(container)
        #expect(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: deleted) == nil)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: deleted))
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: deleted)
        }
    }

    @Test func malformedBaselineAssociationCannotSupplyIdentityOrBeOverwritten() async throws {
        let container = try container(), owner = support.support.owner
        let observation = try #require(UUID(uuidString: support.support.observation))
        #expect(try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: ModelContext(container)) == nil)
        _ = try await run(service(), container)
        let context = ModelContext(container)
        let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(observation.uuidString)))
        let original = try #require(job.metadataJSON)
        for text in ["{}", original.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")] {
            job.metadataJSON = text; try context.save()
            #expect(throws: (any Error).self) {
                try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: ModelContext(container))
            }
            #expect(throws: (any Error).self) {
                try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: ModelContext(container))
            }
        }
    }

    @Test func lostEnrollmentResponseOrStateReadLeavesRetryableLocalState() async throws {
        for loseReceipt in [true, false] {
            let container = try container()
            let unavailable = { throw ObservationHistoryError.unavailable }
            let failed = service(duringEnroll: loseReceipt ? unavailable : {}, duringRead: loseReceipt ? {} : unavailable)
            await #expect(throws: ObservationHistoryError.unavailable) { try await run(failed, container) }
            try expectUnenrolled(container)
            let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(support.support.observation)))
            #expect(job.kind == .future && job.status == .needsAttention && job.nextRunAt == nil && job.metadataJSON != nil)
            #expect(try await run(service(), container) == UUID(uuidString: support.analysisID))
            #expect(try support.support.count(container) == 1)
        }
    }

    @Test func receiptReplayAfterAnotherSelectionNeverRestoresBaseline() async throws {
        let container = try container()
        let response = try ObservationHistorySelectionSyncTests().nativeResponse(revision: 2)
        await #expect(throws: Failure.reconciliationRequired) { try await run(service(state: response), container) }
        try expectUnenrolled(container)
    }

    @Test func differingReviewEvidenceOrOversizedDisplayRequiresReconciliation() async throws {
        for mutation in 0..<3 {
            let container = try container()
            if mutation == 0 { try support.update(container) { scan, _ in scan.confidenceScore = 0.2 } }
            if mutation == 1 { try support.update(container) { scan, _ in scan.wikipediaOverview = String(repeating: "x", count: LocalAnalysisRecord.maximumSnapshotBytes) } }
            let response = try support.fixture(revision: 1, rejected: mutation == 2)
            await #expect(throws: Failure.reconciliationRequired) { try await run(service(state: response), container) }
            try expectUnenrolled(container)
        }
    }

    @Test func localEditsAndDeletionAcrossBothNetworkBoundariesWin() async throws {
        for duringEnrollment in [false, true] {
            for deletion in [false, true] {
                let container = try container()
                let mutate = {
                    try support.update(container) { scan, context in
                        if deletion { try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: support.support.owner, origin: .explicitUserDeletion) }
                        else { scan.commonName = "Newer local identification" }
                    }
                }
                let service = service(duringEnroll: duringEnrollment ? mutate : {}, duringRead: duringEnrollment ? {} : mutate)
                await #expect(throws: (any Error).self) { try await run(service, container) }
                try expectUnenrolled(container)
            }
        }
    }

    @Test func accountGenerationChangesAtEveryFenceRollbackAndFinishLease() async throws {
        for failAt in 1...7 {
            let container = try container()
            var checks = 0, finished = false
            let service = service(current: { checks += 1; return checks < failAt }, finish: { finished = true })
            await #expect(throws: ObservationHistoryError.accountChanged) { try await run(service, container) }
            #expect(finished)
            try expectUnenrolled(container)
        }
    }

    @Test func unfinishedIngestionAndReviewDeferBeforeRemoteImport() async throws {
        for kind in [OfflineJobKind.scanIngestion, .identificationReviewSync] {
            for status in ["pending", "running", "future-status"] {
                let container = try container()
                try support.update(container) { scan, context in
                    let job = OfflineJobRecord(id: "fixture-enrollment", kind: kind, subjectId: scan.id)
                    job.statusRaw = status; context.insert(job)
                }
                var called = false
                await #expect(throws: (any Error).self) { try await run(service(duringEnroll: { called = true }), container) }
                #expect(!called)
                try expectUnenrolled(container)
            }
        }
        let container = try container()
        try support.update(container) { scan, context in context.insert(OfflineQueuedScan(id: scan.id)) }
        await #expect(throws: Failure.pendingWork) { try await run(service(), container) }
        try expectUnenrolled(container)
    }

    @Test func legacyOfflineCorrectionAndUndoAreNotOverwritten() async throws {
        for undo in [false, true] {
            let container = try container()
            try support.update(container) { scan, _ in
                scan.confirmedSpeciesIdentityData = nil
                if !undo { scan.userIdentificationOverride = "Offline correction" }
            }
            await #expect(throws: ObservationHistoryStateSyncService.AdmissionError.pendingReview) {
                try await run(service(state: support.fixture(revision: 1, rejected: undo)), container)
            }
            try expectUnenrolled(container)
        }
    }
}
