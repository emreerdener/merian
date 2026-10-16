import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioSourceHostTests {
    let fixture = ObservationAudioPreparationTests()

    @Test(arguments: [false, true])
    func uncertainSourceSaveReopensExactCandidate(committed: Bool) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        var fail = true, starts: [UUID] = []
        let parent = CaptureAudioReanalysisHostOwner(), target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let host = try parent.open(target: target, container: seed.container, route: .source) {
            CaptureAudioReanalysisHost(source: .init(session: session, isCurrent: { true }, submit: { current in
                try await session.submitSource(generation: session.generation, preparation: service,
                    isCurrentAccount: { true }, isCurrentPresentation: current, save: { context in
                        if fail {
                            if committed { try context.save() }; throw CocoaError(.fileWriteUnknown)
                        }
                        try context.save()
                    }, start: { saved, _ in
                        guard case let .source(snapshot) = saved else { Issue.record("Source host used execution binding"); return .unavailable }
                        starts.append(snapshot.identity.analysisID); return .unavailable
                    })
            }))
        }
        #expect(host.route == .source && host.present())
        host.submit([.audio(seed.bytes)])
        let identity = try #require(host.analysisID)
        while host.isBusy { await Task.yield() }
        #expect(starts.isEmpty && host.message != nil)
        host.close(); fail = false
        #expect(try parent.open(target: target, container: seed.container, route: .source, make: {
            Issue.record("Reopening replaced source candidate"); throw MerianError.invalidResponse
        }) === host)
        #expect(host.present()); host.retry()
        while host.isBusy { await Task.yield() }
        #expect(host.analysisID == identity && starts == [identity])
        let saved = try ObservationSourceReservationStore.read(#require(session.plan).verify().proof.preparation.identity,
            container: seed.container, isCurrent: { true })
        #expect(saved.identity.analysisID == identity)
    }

    @Test func routesNeverCoalesceOrAcceptWrongFactory() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID, analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let owner = CaptureAudioReanalysisHostOwner()
        func session() -> CaptureAudioReanalysisSession { .init(source: seed.source, generation: UUID(), container: seed.container) }
        let legacy = try owner.open(target: target, container: seed.container) {
            CaptureAudioReanalysisHost(opened: .init(session: session(), isCurrent: { true }, submit: { _ in .unavailable }))
        }
        #expect(throws: (any Error).self) {
            try owner.open(target: target, container: seed.container, route: .source) {
                Issue.record("Route mismatch must not create another candidate")
                return CaptureAudioReanalysisHost(source: .init(session: session(), isCurrent: { true }, submit: { _ in .unavailable }))
            }
        }
        #expect(legacy.route == .legacy)
        let wrongOwner = CaptureAudioReanalysisHostOwner()
        #expect(throws: (any Error).self) {
            try wrongOwner.open(target: target, container: seed.container, route: .source) {
                CaptureAudioReanalysisHost(opened: .init(session: session(), isCurrent: { true }, submit: { _ in .unavailable }))
            }
        }
    }

    @Test func closeRetainsSourceWaiterAndLateReplyCannotPresent() async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        let host = CaptureAudioReanalysisHost(source: .init(session: session, isCurrent: { true }, submit: { current in
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            #expect(!current()); return .started
        }))
        #expect(host.present()); host.submit([.audio(seed.bytes)])
        for await _ in entered.stream { break }
        let identity = host.analysisID
        host.close(); #expect(host.isBusy && !host.present())
        release?.resume()
        while host.isBusy { await Task.yield() }
        #expect(host.message == nil && !host.isPresented && host.analysisID == identity)
        #expect(host.present())
    }

    @Test func appPreparedBundleHasDualInertAccessWithOneHostOwner() {
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: .preview)
        #expect(bundle.audioCapture != nil && bundle.audioSourceCapture != nil && bundle.audioHostOwner != nil)
        #expect(PreparedHistoryReanalysisComposition.appInstallation { bundle } == nil)
    }

    @Test func sourceOnlyCompositionCannotOpenLegacyHostAndRemainsUninstalled() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: fixture.fixture.account(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { $0 === seed.container },
            submitted: { _ in Issue.record("Source composition entered photo admission") }, cleanup: {},
            audioSource: .init(start: { _, _, _, _ in .unavailable }, sourceStart: { _, _, _, _ in .unavailable }), documents: { seed.root })
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID, analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let first = try bundle.openAudioSourceHost(target: target, container: seed.container)
        #expect(first.route == .source && !first.isPresented && first.analysisID == nil)
        #expect(try bundle.openAudioSourceHost(target: target, container: seed.container) === first)
        #expect(bundle.audioCapture == nil && bundle.audioStatus == nil)
        #expect(throws: (any Error).self) { try bundle.openAudioHost(target: target, container: seed.container) }
        #expect(PreparedHistoryReanalysisComposition.appInstallation { bundle } == nil)
    }
}
