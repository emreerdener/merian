import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioReanalysisHostTests {
    let fixture = ObservationAudioPreparationTests()

    @Test(arguments: [false, true])
    func ambiguousBindingReopensSameCandidateAndRequest(committed: Bool) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let owner = ObservationReanalysisPreparationOwner(), account = fixture.fixture.account()
        let producer = ObservationAudioPreparationProducer(files: .init(documents: seed.root), ownership: owner, account: account)
        var authorizations = 0, fail = true, starts: [UUID] = []
        let binding = ObservationAudioSubmissionBinding(ownership: owner, account: account, authorize: { _, validate in
            try validate(); authorizations += 1; return .init(recipient: .gemini, validate: validate)
        })
        let host = CaptureAudioReanalysisHost(opened: .init(session: session, isCurrent: { true }, submit: { current in
            try await session.submit(generation: session.generation, producer: producer, binding: binding,
                isCurrentAccount: { true }, isCurrentPresentation: current, save: { context in
                    if fail {
                        if committed { try context.save() }
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try context.save()
                }, start: { snapshot, _ in starts.append(snapshot.work.intent.request.analysisID); return .unavailable })
        }))
        #expect(host.present())
        host.submit([.description("Before"), .audio(seed.bytes), .description("After")])
        let id = try #require(host.analysisID), plan = try #require(session.plan)
        #expect(host.isFrozen && host.isBusy && starts.isEmpty)
        while host.isBusy { await Task.yield() }
        #expect(host.message != nil && starts.isEmpty)
        host.close(); #expect(!host.isPresented && host.analysisID == id)
        fail = false
        #expect(host.present()); host.retry()
        while host.isBusy { await Task.yield() }
        #expect(host.analysisID == id && session.plan?.choices == plan.choices && starts == [id])
        #expect(authorizations == (committed ? 1 : 2))
        let snapshot = try ObservationAudioExecutionStore.read(plan.verify().proof, container: seed.container, isCurrent: { true })
        #expect(snapshot.work.intent.request.analysisID == id)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        host.close(); #expect(host.present()); host.submit([.audio(seed.bytes)])
        #expect(host.analysisID == id && !host.isBusy && starts == [id])
    }

    @Test func closeRetainsWaiterUntilExitAndCannotReopenOrReplaceIt() async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, calls = 0
        let host = CaptureAudioReanalysisHost(opened: .init(session: session, isCurrent: { true }, submit: { current in
            calls += 1
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            #expect(!current()); return .started
        }))
        #expect(host.present()); host.submit([.audio(seed.bytes)])
        let id = host.analysisID
        var begin = entered.stream.makeAsyncIterator(); _ = await begin.next()
        host.close()
        #expect(!host.present() && host.isBusy && host.analysisID == id)
        host.retry(); #expect(calls == 1)
        try #require(release).resume()
        while host.isBusy { await Task.yield() }
        #expect(host.message == nil && host.analysisID == id && !host.isPresented)
        #expect(host.present())
    }

    @Test func preparedAccessScopeLossClearsCandidateWithoutLegacyFallback() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var current = true
        let access = CaptureAudioReanalysisAccess.prepared(account: fixture.fixture.account(), ownership: .init(),
            configuration: .init(authorize: { _, _ in Issue.record("Unexpected authorization"); throw MerianError.invalidResponse },
                start: { _, _, _, _ in Issue.record("Unexpected execution"); return .started }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in current },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let opened = try access.open(.init(observationID: seed.source.observationID, analysisID: seed.source.analysisID,
            ownerID: seed.source.ownerID), seed.container, UUID())
        let host = CaptureAudioReanalysisHost(opened: opened)
        #expect(host.present()); current = false; host.submit([.audio(seed.bytes)])
        #expect(!host.isPresented && !host.isCurrent && host.analysisID == nil)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func compositionFactoryUsesExactSourceAndReleasesOpeningLease() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var leases = 0, current = true
        var account = fixture.fixture.account(finish: { leases -= 1 })
        account.begin = { owner in leases += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        func bundle(audio: CaptureAudioReanalysisAccess.Configuration?) -> PreparedHistoryReanalysisComposition {
            .init(routes: AppRouteCoordinator(), cloud: account, currentOwner: { seed.source.ownerID }, generation: { 1 },
                sessionIsCurrent: { _ in current }, preparationOwner: .init(), enrollmentOwner: .init(),
                containerIsCurrent: { $0 === seed.container }, submitted: { _ in Issue.record("Photo submission") }, cleanup: {},
                audio: audio, documents: { seed.root })
        }
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        #expect(throws: (any Error).self) { try bundle(audio: nil).openAudioHost(target: target, container: seed.container) }
        let prepared = bundle(audio: .init(authorize: { _, _ in Issue.record("Opening authorized inference"); throw MerianError.invalidResponse },
            start: { _, _, _, _ in Issue.record("Opening started execution"); return .started }))
        #expect(leases == 0)
        let host = try prepared.openAudioHost(target: target, container: seed.container)
        #expect(leases == 0 && host.analysisID == nil && !host.isPresented)
        #expect(host.present()); host.close(); #expect(host.present())
        current = false
        #expect(!host.present() && !host.isCurrent && leases == 0)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

}
