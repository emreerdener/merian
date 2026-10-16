import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized)
struct SelectedAnalysisPublicationTests {
    @MainActor final class Fixture {
        let source = ObservationPublicationConsentServiceTests()
        let container: ModelContainer
        let snapshot: ObservationPublicationConsentSnapshot
        let ticket: ObservationAnalysisReviewTicket
        let host = SelectedAnalysisReviewHost()
        let continuation = PublicationConsentContinuation()
        var current = true, presentation = true, opens = 0, fetches = 0, wakes = 0
        var model: IdentificationPublicationModel?
        init() async throws {
            let seeded = try await source.seed()
            container = seeded.0
            // The consent fixture deliberately targets a nonselected historical
            // result. Select it through production projection before testing the
            // selected-screen adapter; never loosen that adapter's baseline.
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(source.observation.uuidString, context: context)
            let entry = try ObservationHistoryListingService.entry(source.analysis, scan: scan, context: context)
            var state = try #require(JSONSerialization.jsonObject(with: source.history.support.nativeResponse(revision: 11, protected: true)) as? [String: Any])
            var analysis = try #require(state["analysis"] as? [String: Any])
            analysis["snapshot"] = String(decoding: entry.result.bytes, as: UTF8.self)
            state["analysis"] = analysis
            _ = try await source.history.support.support.service(data: JSONSerialization.data(withJSONObject: state))
                .syncSelected(observationID: source.observation.uuidString, container: container)
            ticket = try source.ticket(container)
            let consent: [String: Any] = ["schema_version": 1, "observation_id": source.observation.uuidString.lowercased(),
                "analysis_id": source.analysis.uuidString.lowercased(), "expected_observation_revision": ticket.observationRevision,
                "expected_review_revision": ticket.reviewRevision, "taxonomy_version_id": seeded.1.taxonomyVersionID.uuidString.lowercased(),
                "initial_taxon_id": NSNull(), "media": seeded.1.media.map {
                    ["media_id": $0.mediaID.uuidString.lowercased(), "content_type": $0.contentType,
                     "byte_count": $0.byteCount, "sha256": $0.sha256] as [String: Any]
                }]
            snapshot = try .decode(JSONSerialization.data(withJSONObject: consent),
                request: .init(observationID: source.observation, analysisID: source.analysis))
        }
        func bind(_ generation: UInt64 = 1, publication: Bool = true) throws {
            var cloud = source.service(snapshot, current: { self.current }).cloud
            cloud.begin = { expected in
                guard expected == self.source.owner else { throw ObservationHistoryError.accountChanged }
                return .init(id: UUID(), session: .init(userID: expected, isAnonymous: false))
            }
            let access = SelectedAnalysisReviewAccess.prepared(cloud: cloud, session: { id, container in
                self.opens += 1
                let configuration = IdentificationHistoryPublicationAccess.Configuration(owner: .init(), recoveryOwner: .init(),
                    fetchTarget: { _, _ in self.fetches += 1; return nil },
                    fetch: { _, _ in self.fetches += 1; return self.snapshot }, wake: { self.wakes += 1 }, generation: { 0 })
                return try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                    reviewWake: {}, publication: publication ? configuration : nil,
                    currentGeneration: { 1 }, sessionIsCurrent: { _ in self.current })
            })
            let baseline = try #require(SelectedAnalysisReviewBaseline(scanID: ticket.observationID.uuidString,
                ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString, revision: ticket.observationRevision))
            host.bind(.init(baseline: baseline, generation: generation, container: ObjectIdentifier(container)),
                access: access, container: container, isCurrent: { self.presentation })
        }
        func prepare(isCurrent: @escaping () -> Bool = { true }) throws -> CommunityConsentTicket? {
            host.preparePublication(token: try #require(host.token), container: container, continuation: continuation, isCurrent: isCurrent,
                present: { self.model = $0 })
        }
    }

    @Test func tapAndDismissalReuseTheSameSessionAndDoNotCreateConsent() async throws {
        let f = try await Fixture(); try f.bind()
        let action = try #require(try f.prepare())
        #expect(f.model == nil && f.opens == 1 && f.fetches == 0 && f.wakes == 0)
        action.resume()
        let model = try #require(f.model)
        #expect(model.ticket == f.ticket && model.phase == .idle && !f.continuation.isOccupied)
        action.resume(); #expect(f.model === model && f.opens == 1)
        await model.recover(); await model.prepare()
        #expect(f.fetches == 2 && model.phase == .choosing && model.selected.isEmpty)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: ["revision", "selection", "owner", "delete", "account", "presentation", "close", "cancel", "reopen"])
    func staleOrCancelledChildHandleCannotOpenAnotherTarget(_ mutation: String) async throws {
        let f = try await Fixture(); try f.bind()
        let action = try #require(try f.prepare())
        switch mutation {
        case "account": f.current = false
        case "presentation": f.presentation = false
        case "close": f.host.close()
        case "cancel": action.cancel()
        case "reopen": f.host.close(); try f.bind(2)
        default:
            let context = ModelContext(f.container)
            let scan = try ObservationHistorySyncService.enrolledScan(f.ticket.observationID.uuidString, context: context)
            switch mutation {
            case "revision": scan.observationStateRevision = 12
            case "selection": scan.selectedAnalysisID = UUID().uuidString.lowercased()
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            default: context.delete(scan)
            }
            try context.save()
        }
        action.resume()
        #expect(f.model == nil && f.fetches == 0 && f.wakes == 0 && !f.continuation.isOccupied)
    }

    @Test(arguments: [false, true])
    func engineOnlyScopeLossInvalidatesHandoffAndChooser(afterPresentation: Bool) async throws {
        let f = try await Fixture(); try f.bind()
        var engineCurrent = true
        let action = try #require(try f.prepare(isCurrent: { engineCurrent }))
        if afterPresentation {
            action.resume()
            let model = try #require(f.model)
            await model.recover(); await model.prepare()
            engineCurrent = false
            model.toggle(f.source.secondPhoto); model.submit()
            #expect(model.phase == .closed && model.candidates.isEmpty)
        } else {
            engineCurrent = false
            action.resume()
            #expect(f.model == nil)
        }
        #expect(f.wakes == 0 && !f.continuation.isOccupied)
    }

    @Test func nilCapabilityAndWrongContainerCannotPrepare() async throws {
        let f = try await Fixture(); try f.bind(publication: false)
        let unavailable = try f.prepare()
        #expect(!f.host.hasPublicationAccess && unavailable == nil)
        f.host.close(); try f.bind()
        let other = try InsightSheetTestSupport.createIsolatedContext().container
        #expect(f.host.preparePublication(token: try #require(f.host.token), container: other, continuation: f.continuation, isCurrent: { true },
            present: { _ in Issue.record("A different container cannot present") }) == nil)
        #expect(f.fetches == 0)
    }

    @Test func reviewStartedAfterCommunityTapPreventsDismissalHandoff() async throws {
        let f = try await Fixture(); try f.bind()
        let action = try #require(try f.prepare())
        f.host.submit(.reject, token: try #require(f.host.token))
        #expect(f.host.model?.hasUnresolvedRequest == true)
        action.resume()
        #expect(f.model == nil && f.fetches == 0 && !f.host.hasPublicationAccess)
        #expect(try f.prepare() == nil)
    }

    @Test func sharedContinuationKeepsExactAcceptanceAcrossHostReopening() async throws {
        let f = try await Fixture(); try f.bind()
        let prepared = try await f.source.prepare(f.source.service(f.snapshot), f.container)
        let acceptance = try prepared.accepting(mediaIDs: [f.source.secondPhoto])
        f.continuation.bind(owner: f.ticket.ownerID, observation: f.ticket.observationID, container: f.container)
        try f.continuation.retain(acceptance, ticket: f.ticket)
        let action = try #require(try f.prepare()); action.resume()
        #expect(f.model?.phase == .uncertain && f.model?.canRetrySave == true)
        f.host.close(); try f.bind(2)
        let reopened = try #require(try f.prepare()); reopened.resume()
        #expect(f.continuation.held?.acceptance.request == acceptance.request && f.model?.phase == .uncertain)
        #expect(f.fetches == 0 && f.wakes == 0)
    }

    @Test func authorityChangesAfterPresentationClearPrivateModelWithoutReplacingAcceptance() async throws {
        let f = try await Fixture(); try f.bind()
        let action = try #require(try f.prepare()); action.resume()
        let model = try #require(f.model)
        await model.recover(); await model.prepare()
        #expect(!model.candidates.isEmpty)
        try f.source.advanceTarget(f.container, revision: 12, reviewRevision: 1)
        model.toggle(f.source.secondPhoto)
        #expect(model.phase == .closed && model.candidates.isEmpty && f.wakes == 0)
    }
}
