import Foundation
@testable import Merian
import SwiftData
import Testing

extension ObservationAnalysisReviewDeliveryTests {
    func fresh(decision: ObservationAnalysisReviewRequest.Decision = .reject) async throws -> (ModelContainer, ObservationAnalysisReviewIntent) {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        _ = try await fixture.source.service(data: fixture.source.fixture(revision: 10))
            .syncSelected(observationID: fixture.observation.uuidString, container: container)
        let request = try ObservationAnalysisReviewRequest(observationID: fixture.observation, analysisID: fixture.target,
            operationID: UUID(), expectedObservationRevision: 10, expectedReviewRevision: 0, decision: decision)
        return (container, try Store.stage(request, ownerID: fixture.owner, container: container, isCurrent: { true }, validateNew: { _ in }))
    }

    func receipt(_ request: ObservationAnalysisReviewRequest, outcome: String = "applied") throws -> ObservationAnalysisReviewReceipt {
        try ObservationAnalysisReviewPersistenceTests().receipt(request, outcome: outcome)
    }

    func job(_ intent: ObservationAnalysisReviewIntent, _ container: ModelContainer) throws -> OfflineJobRecord {
        try #require(try ModelContext(container).fetchOfflineJob(id: Store.jobID(intent.request.operationID, observationID: intent.request.observationID)))
    }

    func client(secondRevision: Int = 12, current: @escaping () -> Bool = { true },
                during: @escaping (Int) throws -> Void = { _ in }, finish: @escaping () -> Void = {}) throws -> ObservationHistoryCloudClient {
        fixture.cloud(targetData: try fixture.targetData(), selectedData: try fixture.selectedData(revision: secondRevision),
                      current: current, during: during, finish: finish)
    }

    func service(cloud: ObservationHistoryCloudClient? = nil, outcome: String = "applied") throws -> Service {
        try Service(cloud: cloud ?? client(), submit: { request, owner, validate in
            #expect(owner == fixture.owner); try validate(); return try receipt(request, outcome: outcome)
        }, now: { fixture.date })
    }
}
