import Foundation
@testable import Merian
import SwiftData
import Testing

extension ObservationAnalysisReviewReconciliationTests {
    var owner: UUID { source.support.owner }
    var observation: UUID { UUID(uuidString: source.support.observation)! }
    var target: UUID { UUID(uuidString: source.analysisID)! }
    var selected: UUID { UUID(uuidString: projection.otherID)! }

    func seeded(outcome: String = "applied", audio: Bool = false) async throws -> (ModelContainer, Store.Claim) {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        _ = try await source.service(data: audio ? ObservationAnalysisReviewAdmissionTests().audioState(source.fixture(revision: 10)) : source.fixture(revision: 10)).syncSelected(observationID: observation.uuidString, container: container)
        let request = try ObservationAnalysisReviewRequest(observationID: observation, analysisID: target, operationID: UUID(),
            expectedObservationRevision: 10, expectedReviewRevision: 0, decision: outcome == "not_verified" ? .confirmPrimary : .reject)
        let pending = try Store.stage(request, ownerID: owner, container: container, isCurrent: { true }, validateNew: { _ in })
        let mutationClaim = try #require(try Store.claim(pending, at: date, container: container, isCurrent: { true }))
        var row = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        row["outcome"] = outcome
        if outcome == "applied" { row["observation_revision"] = 11; row["review_revision"] = 1 }
        let receipt = try ObservationAnalysisReviewReceipt.decode(JSONSerialization.data(withJSONObject: row), request: request)
        let received = try Store.acknowledge(receipt, claim: mutationClaim, at: date, container: container, isCurrent: { true })
        return (container, try #require(try Store.claim(received, at: date, container: container, isCurrent: { true })))
    }

    func targetData(revision: Int = 12, review: Int = 1, selectedID: UUID? = nil, changedBytes: Bool = false) throws -> Data {
        var row = try #require(JSONSerialization.jsonObject(with: source.fixture(revision: revision, rejected: true)) as? [String: Any])
        row["selected_analysis_id"] = (selectedID ?? selected).uuidString.lowercased()
        var item = try #require(row["analysis"] as? [String: Any]); item["review_revision"] = review
        if changedBytes { item["snapshot"] = (item["snapshot"] as! String) + " " }
        row["analysis"] = item
        return try source.support.bytes(row)
    }

    func selectedData(revision: Int = 12, changedSelection: Bool = false, imported: Bool = false) throws -> Data {
        var row = try #require(JSONSerialization.jsonObject(with: projection.nativeResponse(revision: revision, protected: true)) as? [String: Any])
        if changedSelection { row["selected_analysis_id"] = target.uuidString.lowercased() }
        if imported {
            let original = try #require(JSONSerialization.jsonObject(with: source.fixture(revision: revision)) as? [String: Any])
            let originalItem = try #require(original["analysis"] as? [String: Any])
            let originalText = try #require(originalItem["snapshot"] as? String)
            var snapshot = try #require(JSONSerialization.jsonObject(with: Data(originalText.utf8)) as? [String: Any])
            snapshot["analysis_id"] = selected.uuidString.lowercased(); snapshot["ordinal"] = 2
            var item = try #require(row["analysis"] as? [String: Any])
            let snapshotData = try source.support.bytes(snapshot)
            item["snapshot"] = try #require(String(bytes: snapshotData, encoding: .utf8))
            row["analysis"] = item
        }
        return try source.support.bytes(row)
    }

    func cloud(targetData: Data, selectedData: Data, current: @escaping () -> Bool = { true },
               during: @escaping (Int) throws -> Void = { _ in }, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        var client = source.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: current, finish: finish)
        var count = 0
        client.fetchState = { request in
            count += 1
            #expect(request.observation_id == observation.uuidString.lowercased())
            #expect(request.analysis_id == (count == 1 ? target : selected).uuidString.lowercased())
            try during(count)
            return count == 1 ? targetData : selectedData
        }
        return client
    }

    func state(_ id: UUID, in container: ModelContainer) throws -> LocalAnalysisStateRecord {
        let key = id.uuidString.lowercased()
        return try #require(ModelContext(container).fetch(FetchDescriptor<LocalAnalysisStateRecord>(predicate: #Predicate { $0.id == key })).first)
    }

    func requireUnchanged(_ container: ModelContainer, claim: Store.Claim) throws {
        let parent = try projection.parent(container)
        #expect(parent.selectedAnalysisID == target.uuidString.lowercased() && parent.observationStateRevision == 10)
        #expect(try state(target, in: container).reviewRevision == 0)
        #expect(try source.support.count(container) == 1)
        let job = try #require(try ModelContext(container).fetchOfflineJob(id: Store.jobID(claim.intent.request.operationID, observationID: observation)))
        #expect(try Store.restore(job).storedData() == claim.intent.storedData())
        #expect(job.status == .running)
    }
}
