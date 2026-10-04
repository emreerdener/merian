import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationPublicationConsentServiceTests {
    let history = ObservationHistorySelectionIntentTests()
    var owner: UUID { history.owner }
    var observation: UUID { UUID(uuidString: history.observation)! }
    var analysis: UUID { history.target }
    let secondPhoto = UUID(uuidString: "00000000-0000-4000-8000-000000000077")!

    func seed() async throws -> (ModelContainer, ObservationPublicationConsentSnapshot) {
        let container = try await history.support.seeded()
        var response = try JSONSerialization.jsonObject(with: history.support.nativeResponse(revision: 10, protected: true)) as! [String: Any]
        response["selected_analysis_id"] = history.support.support.analysisID
        var item = response["analysis"] as! [String: Any]
        var result = try JSONSerialization.jsonObject(with: Data((item["snapshot"] as! String).utf8)) as! [String: Any]
        var manifest = result["evidence_manifest"] as! [String: Any]
        var entries = manifest["items"] as! [[String: Any]]
        var second = entries[0]; second["media_id"] = secondPhoto.uuidString.lowercased()
        entries.append(second); manifest["items"] = entries; result["evidence_manifest"] = manifest
        item["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        response["analysis"] = item
        var cloud = history.support.support.support.client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try JSONSerialization.data(withJSONObject: response) }
        let preview = try await ObservationHistoryPreviewService(cloud: cloud).preview(
            observationID: history.observation, analysisID: analysis, container: container)
        let row: [String: Any] = ["schema_version": 1, "observation_id": observation.uuidString.lowercased(),
            "analysis_id": analysis.uuidString.lowercased(), "expected_observation_revision": preview.state.revision,
            "expected_review_revision": preview.state.reviewRevision, "taxonomy_version_id": UUID().uuidString.lowercased(),
            "initial_taxon_id": NSNull(), "media": preview.state.result.photos.map {
                ["media_id": $0.mediaID.uuidString.lowercased(), "content_type": $0.contentType,
                 "byte_count": $0.byteCount, "sha256": $0.sha256] as [String: Any]
            }]
        return (container, try .decode(JSONSerialization.data(withJSONObject: row), request: .init(observationID: observation, analysisID: analysis)))
    }

    func service(_ snapshot: ObservationPublicationConsentSnapshot, current: @escaping () -> Bool = { true },
                 duringFetch: @escaping () throws -> Void = {}, wake: @escaping () -> Void = {}) -> ObservationPublicationConsentService {
        .init(cloud: history.support.support.support.client(fetch: { _ in Data() }, current: current), fetch: { request, expected in
            #expect(expected == owner && request.observationID == observation && request.analysisID == analysis)
            try duringFetch(); return snapshot
        }, wake: wake)
    }

    func prepare(_ service: ObservationPublicationConsentService, _ container: ModelContainer,
                 current: () -> Bool = { true }) async throws -> ObservationPublicationConsentService.Prepared {
        try await service.prepare(observationID: observation, analysisID: analysis, ownerID: owner,
                                  container: container, isCurrent: current)
    }

    @Test func historicalConsentPreservesUserOrderAndSavesBeforeWake() async throws {
        let (container, snapshot) = try await seed()
        var wakes = 0
        let service = service(snapshot, wake: {
            wakes += 1
            #expect((try? ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>())) == 1)
        })
        let prepared = try await prepare(service, container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let ids = snapshot.media.map(\.mediaID).reversed().map { $0 }
        let acceptance = try prepared.accepting(mediaIDs: ids)
        let intent = try service.stage(acceptance, container: container, isCurrent: { true })
        #expect(intent.request?.mediaIDs == ids && intent.request?.note == nil && intent.request?.initialTaxonID == nil)
        #expect(wakes == 1)
        #expect(try history.support.parent(container).selectedAnalysisID == history.support.support.analysisID)
        #expect(try history.support.parent(container).fieldNotes == "Preserved private note")
    }

    @Test func invalidSelectionNeverMintsOperation() async throws {
        let (container, snapshot) = try await seed(), prepared = try await prepare(service(snapshot), container)
        var minted = 0
        for ids in [[], [UUID()], [secondPhoto, secondPhoto], (0..<7).map { _ in UUID() }] {
            #expect(throws: (any Error).self) {
                try prepared.accepting(mediaIDs: ids, makeOperationID: { minted += 1; return UUID() })
            }
        }
        #expect(minted == 0)
    }

    @Test func failedSaveKeepsExactAcceptanceAndNeverWakes() async throws {
        let (container, snapshot) = try await seed()
        var wakes = 0, minted = 0
        var service = service(snapshot, wake: { wakes += 1 })
        let prepared = try await prepare(service, container)
        let acceptance = try prepared.accepting(mediaIDs: [secondPhoto], makeOperationID: { minted += 1; return UUID() })
        service.save = { _ in throw ObservationHistoryError.unavailable }
        #expect(throws: ObservationHistoryError.unavailable) { try service.stage(acceptance, container: container, isCurrent: { true }) }
        #expect(wakes == 0 && minted == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        service.save = { try $0.save() }
        let first = try service.stage(acceptance, container: container, isCurrent: { true })
        let retry = try service.stage(acceptance, container: container, isCurrent: { true })
        #expect(try first.storedData() == retry.storedData())
        #expect(first.identity.operationID == acceptance.request.operationID && minted == 1)
    }

    @Test func terminalReplayPrecedesMutableNewConsentChecks() async throws {
        let (container, snapshot) = try await seed()
        var wakes = 0
        let service = service(snapshot, wake: { wakes += 1 }), prepared = try await prepare(service, container)
        let accepted = try prepared.accepting(mediaIDs: [secondPhoto])
        let original = try service.stage(accepted, container: container, isCurrent: { true })
        let row: [String: Any] = ["schema_version": 1, "operation_id": original.identity.operationID.uuidString.lowercased(),
            "observation_id": observation.uuidString.lowercased(), "analysis_id": analysis.uuidString.lowercased(), "status": "admitted"]
        let receipt = try ObservationPublicationReceipt.decodeStatus(JSONSerialization.data(withJSONObject: row), request: original.identity)
        _ = try ObservationPublicationPersistence.acknowledge(receipt, expected: original, at: Date(), container: container, isCurrent: { true })
        try history.support.support.update(container) { scan, _ in scan.observationStateRevision = 11 }
        #expect(try service.stage(accepted, container: container, isCurrent: { true }).isTerminal)
        #expect(wakes == 1)
        let new = try prepared.accepting(mediaIDs: [secondPhoto])
        #expect(throws: (any Error).self) { try service.stage(new, container: container, isCurrent: { true }) }
    }

    @Test func stateMutationBeforeSaveDeniesNewConsent() async throws {
        for mutation in 0..<5 {
            let (container, snapshot) = try await seed()
            var wakes = 0
            let service = service(snapshot, wake: { wakes += 1 })
            let acceptance = try await prepare(service, container).accepting(mediaIDs: [secondPhoto])
            try history.support.support.update(container) { scan, context in
                switch mutation {
                case 0: scan.observationStateRevision = 11
                case 1: context.insert(OfflineJobRecord(id: "pending-review", kind: .identificationReviewSync, subjectId: scan.id))
                case 2: _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: context)
                case 3: scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
                default: context.delete(scan)
                }
            }
            #expect(throws: (any Error).self) { try service.stage(acceptance, container: container, isCurrent: { true }) }
            #expect(wakes == 0)
        }
    }

    @Test func ownerLossAcrossPreflightAndBeforeSaveFailsClosed() async throws {
        let (container, snapshot) = try await seed()
        var current = true
        let stale = service(snapshot, duringFetch: { current = false })
        await #expect(throws: ObservationHistoryError.accountChanged) { try await prepare(stale, container, current: { current }) }
        let prepared = try await prepare(service(snapshot), container)
        let acceptance = try prepared.accepting(mediaIDs: [secondPhoto])
        #expect(throws: (any Error).self) { try service(snapshot).stage(acceptance, container: container, isCurrent: { false }) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }
}
