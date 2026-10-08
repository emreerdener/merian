import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioReanalysisAccessTests {
    let fixture = ObservationAudioPreparationTests()

    @Test func inertCompositionOpensExactSourceWithoutIdleLeaseAndHandsOffOriginalScope() async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var begins = 0, finishes = 0, authorizations = 0, starts = 0
        var account = fixture.fixture.account(finish: { finishes += 1 })
        account.begin = { owner in begins += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        let config = CaptureAudioReanalysisAccess.Configuration(authorize: { _, validate in
            try validate(); authorizations += 1; return .init(recipient: .gemini, validate: validate)
        }, start: { key, proof, container, _ in
            starts += 1
            #expect(key.session.userID == seed.source.ownerID && key.generation == 9)
            #expect(key.container == ObjectIdentifier(seed.container) && container === seed.container)
            #expect(key.snapshot.work.intent.request.analysisID == proof.preparation.identity.analysisID)
            return .unavailable
        })
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: account,
            currentOwner: { seed.source.ownerID }, generation: { 9 }, sessionIsCurrent: { _ in true },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { $0 === seed.container },
            submitted: { _ in Issue.record("Audio entered photo admission") }, cleanup: {}, audio: config, documents: { seed.root })
        #expect(begins == 0 && starts == 0 && authorizations == 0)
        let access = try #require(bundle.audioCapture), generation = UUID()
        let opened = try access.open(.init(observationID: seed.source.observationID, analysisID: seed.source.analysisID,
            ownerID: seed.source.ownerID), seed.container, generation)
        #expect(begins == finishes && opened.session.source == seed.source)
        let plan = try opened.session.freeze([.audio(seed.bytes)], generation: generation)
        let first = try await opened.submit { true }
        #expect(first == .unavailable && starts == 1 && authorizations == 1 && begins == finishes)
        let second = try await opened.submit { true }
        #expect(second == .unavailable && starts == 2 && authorizations == 1)
        #expect(opened.session.plan?.analysisID == plan.analysisID && begins == finishes)
    }

    @Test(arguments: ["owner", "generation", "session", "container", "presentation"])
    func changedScopeWithholdsSubmissionWithoutReminting(_ change: String) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var owner = seed.source.ownerID, generation: UInt64 = 1, sessionCurrent = true, containerCurrent = true, starts = 0
        let access = CaptureAudioReanalysisAccess.prepared(account: fixture.fixture.account(), ownership: .init(),
            configuration: .init(authorize: { _, validate in try validate(); return .init(recipient: .gemini, validate: validate) },
                start: { _, _, _, _ in starts += 1; return .started }), currentOwner: { owner }, generation: { generation },
            sessionIsCurrent: { _ in sessionCurrent }, containerIsCurrent: { _ in containerCurrent }, documents: { seed.root })
        let presentation = UUID(), target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let opened = try access.open(target, seed.container, presentation)
        let plan = try opened.session.freeze([.audio(seed.bytes)], generation: presentation)
        switch change {
        case "owner": owner = UUID()
        case "generation": generation += 2
        case "session": sessionCurrent = false
        case "container": containerCurrent = false
        default: break
        }
        await #expect(throws: (any Error).self) { try await opened.submit { change != "presentation" } }
        #expect(starts == 0 && opened.session.plan?.analysisID == plan.analysisID)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        if change == "owner" || change == "session" || change == "container" {
            #expect(throws: (any Error).self) { try access.open(target, seed.container, UUID()) }
        }
    }

    @Test func appAssemblyPreparesAudioButNeverInstallsOrdinaryAccess() {
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: .preview)
        #expect(bundle.audioCapture != nil)
        #expect(PreparedHistoryReanalysisComposition.appInstallation { bundle } == nil)
    }
}
