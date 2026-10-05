import Foundation
@testable import Merian
import SwiftData
import SwiftUI
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct HistoryReanalysisCompositionTests {
    let fixture = CaptureReanalysisSessionTests()

    @Test func ordinaryInstallationDoesNotConstructAnyAccess() {
        var builds = 0
        let installation = PreparedHistoryReanalysisComposition.appInstallation {
            builds += 1
            return .prepared(in: .preview)
        }
        #expect(!PreparedHistoryReanalysisComposition.isAppInstallationQualified)
        #expect(installation == nil && builds == 0)
        #expect(EnvironmentValues().insightHistoryReanalysisAccesses == nil)
        let ordinary = InsightShellDependencies()
        #expect(ordinary.historyAccess == nil && ordinary.reanalysisStatusAccess == nil && ordinary.savedReanalysisAccess == nil)
    }

    @Test func groupedInstallationPreservesOtherShellDependencies() throws {
        let container = AppDIContainer.preview
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: container)
        var feedback = 0
        let base = InsightShellDependencies(selectionFeedback: { feedback += 1 })
        let installed = bundle.insightAccesses.applying(to: base)
        #expect(installed.historyAccess != nil && installed.reanalysisStatusAccess != nil && installed.savedReanalysisAccess != nil)
        #expect(base.historyAccess == nil && base.reanalysisStatusAccess == nil && base.savedReanalysisAccess == nil)
        installed.selectionFeedback()
        #expect(feedback == 1)
        let target = HistoricalReanalysisTarget(observationID: UUID(), analysisID: UUID(), ownerID: UUID())
        try #require(installed.savedReanalysisAccess).dispatch(target)
        let request = try #require(container.appRouteCoordinator.pendingRequests.first)
        guard case let .historicalReanalysis(actual) = request.route else { Issue.record("Wrong route"); return }
        #expect(actual == target)
    }

    @Test(arguments: ["history", "status", "reanalysis"])
    func singleFixtureAccessPreventsAnyPartialInstallation(_ slot: String) {
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: .preview)
        var fixture = InsightShellDependencies()
        switch slot {
        case "history": fixture.historyAccess = bundle.history
        case "status": fixture.reanalysisStatusAccess = bundle.status
        default: fixture.savedReanalysisAccess = bundle.reanalyze
        }
        let result = bundle.insightAccesses.applying(to: fixture)
        #expect((result.historyAccess != nil) == (slot == "history"))
        #expect((result.reanalysisStatusAccess != nil) == (slot == "status"))
        #expect((result.savedReanalysisAccess != nil) == (slot == "reanalysis"))
    }

    @Test func captureResolvesInstallationBeforeRoutingAndPreservesExplicitDependencies() {
        let container = AppDIContainer.preview
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: container)
        let installed = CaptureWorkspaceViewModel(diContainer: container, reanalysisAccess: bundle.capture,
            prewarmHeadersOnInit: false)
        #expect(installed.diContainer === container && installed.dependencies.reanalysis != nil)
        let fixture = CaptureWorkspaceDependencies.live(diContainer: container)
        let explicit = CaptureWorkspaceViewModel(diContainer: container, reanalysisAccess: bundle.capture,
            dependencies: fixture, prewarmHeadersOnInit: false)
        #expect(explicit.diContainer === container && explicit.dependencies.reanalysis == nil)
    }

    @Test func appBuilderIsInertAndUsesSuppliedRouteOwner() throws {
        let dependencies = AppDIContainer.preview
        let bundle = PreparedHistoryReanalysisComposition.prepared(in: dependencies)
        #expect(dependencies.appRouteCoordinator.pendingRequests.isEmpty)
        let target = HistoricalReanalysisTarget(observationID: UUID(), analysisID: UUID(), ownerID: UUID())
        let dispatch = try #require(bundle.history.requestReanalysis)
        dispatch(target)
        let request = try #require(dependencies.appRouteCoordinator.pendingRequests.first)
        guard case let .historicalReanalysis(actual) = request.route else { Issue.record("Wrong route"); return }
        #expect(actual == target)
    }

    @Test func oneInjectedAccountOwnsHistoryPhotosCaptureAndSubmittedStatus() async throws {
        let seed = try fixture.seed(count: 1), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var begins = [UUID](), finishes = 0, resolves = [UUID](), submitted = [UUID](), cleanups = 0
        var cloud = fixture.fixture.account(finish: { finishes += 1 })
        cloud.begin = { owner in begins.append(owner); return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        cloud.resolvePhoto = { request in
            #expect(request.observation_id == seed.source.observationID.uuidString.lowercased())
            #expect(request.analysis_id == seed.source.analysisID.uuidString.lowercased())
            resolves.append(try #require(UUID(uuidString: request.media_id)))
            return try ticket(request, seed: seed)
        }
        let routes = AppRouteCoordinator(), bytes = seed.bytes
        let bundle = PreparedHistoryReanalysisComposition(routes: routes, cloud: cloud,
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { $0.userID == seed.source.ownerID },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { _ in true }, submitted: { submitted.append($0) }, cleanup: { cleanups += 1 },
            documents: { root }, downloadPhoto: { _ in bytes })
        #expect(begins.isEmpty && resolves.isEmpty && submitted.isEmpty && routes.pendingRequests.isEmpty)
        let id = seed.source.observationID.uuidString
        #expect(!bundle.history.hasMultiple(id, seed.container) && !bundle.status.available(id, seed.container))
        let history = try bundle.history.open(id, seed.container)
        let context = try history.context()
        let photo = try #require(seed.source.photos.first)
        _ = try await history.photo(seed.source.analysisID, photo.mediaID)
        let prepareReanalysis = try #require(history.reanalysis)
        let action = try prepareReanalysis(seed.source.analysisID, context)
        history.close()
        let dispatch = try #require(bundle.history.requestReanalysis)
        dispatch(try action.resolve())
        let route = try #require(routes.pendingRequests.first)
        guard case let .historicalReanalysis(target) = route.route else { Issue.record("Wrong route"); return }
        #expect(target.analysisID == seed.source.analysisID && target.ownerID == seed.source.ownerID)
        let editor = try bundle.capture.open(target, seed.container)
        editor.toggle(photo.mediaID); await editor.loadSelection(); await editor.submit()
        #expect(editor.phase == .submitted && submitted.count == 1 && cleanups == 0)
        #expect(resolves == [photo.mediaID, photo.mediaID, photo.mediaID])
        #expect(!begins.isEmpty && begins.allSatisfy { $0 == seed.source.ownerID } && begins.count == finishes)
        #expect(bundle.status.available(id, seed.container) && !bundle.history.hasMultiple(id, seed.container))
        let status = try bundle.status.open(id, seed.container)
        let page = try await status.page(nil)
        #expect(page.items.map(\.id) == submitted && page.items.first?.sourceAnalysisID == seed.source.analysisID)
        status.close()
        let parent = try #require(ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
        #expect(editor.discard() && cleanups == 1 && editor.phase == .closed)
    }

    @Test func multipleResultAvailabilityUsesInjectedCloudAndSessionPredicate() async throws {
        let fixture = ObservationHistorySelectionIntentTests(), container = try await fixture.seeded()
        let support = fixture.support.support.support
        var current = true
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: support.client(fetch: { _ in Data() }),
            currentOwner: { support.owner }, generation: { 1 }, sessionIsCurrent: { _ in current },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { _ in true }, submitted: { _ in Issue.record("Availability submitted work") }, cleanup: { Issue.record("Availability erased work") })
        #expect(bundle.history.hasMultiple(fixture.observation, container))
        current = false
        #expect(!bundle.history.hasMultiple(fixture.observation, container))
        #expect(throws: (any Error).self) { try bundle.history.open(fixture.observation, container) }
    }

    @Test(arguments: ["owner", "generation", "session"])
    func invalidatedCompositionCannotReadRouteOrPreparePrivateMedia(_ reason: String) async throws {
        let seed = try fixture.seed(count: 1), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var owner = seed.source.ownerID, generation: UInt64 = 1, current = true, resolves = 0, wake = 0
        var cloud = fixture.fixture.account()
        cloud.resolvePhoto = { request in resolves += 1; return try ticket(request, seed: seed) }
        let bytes = seed.bytes
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: cloud,
            currentOwner: { owner }, generation: { generation }, sessionIsCurrent: { _ in current },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { _ in true }, submitted: { _ in wake += 1 }, cleanup: { wake += 1 },
            documents: { root }, downloadPhoto: { _ in bytes })
        let id = seed.source.observationID.uuidString
        let history = try bundle.history.open(id, seed.container), status = try bundle.status.open(id, seed.container)
        let prepareReanalysis = try #require(history.reanalysis)
        let action = try prepareReanalysis(seed.source.analysisID, history.context())
        let target = try action.resolve(), editor = try bundle.capture.open(target, seed.container)
        editor.toggle(try #require(seed.source.photos.first).mediaID)
        switch reason {
        case "owner": owner = UUID()
        case "generation": generation += 2 // Same account after A → B → A still invalidates old presentations.
        default: current = false
        }
        #expect(!history.isCurrent() && !status.isCurrent())
        #expect(throws: (any Error).self) { try history.context() }
        #expect(throws: (any Error).self) { try status.validate() }
        #expect(throws: (any Error).self) { try action.resolve() }
        await editor.loadSelection()
        #expect(resolves == 0 && wake == 0 && !editor.canSubmit)
        if reason != "generation" {
            #expect(throws: (any Error).self) { try bundle.capture.open(target, seed.container) }
            #expect(!bundle.history.hasMultiple(id, seed.container) && !bundle.status.available(id, seed.container))
        }
        history.close(); status.close(); editor.invalidate()
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    private func ticket(_ request: ObservationHistoryPhotoRequest, seed: CaptureReanalysisSessionTests.Seed) throws -> ObservationHistoryPhotoTicket {
        let photo = try #require(seed.source.photos.first { $0.mediaID.uuidString.lowercased() == request.media_id })
        return ObservationHistoryPhotoTicket(schema_version: 1, owner_id: seed.source.ownerID.uuidString.lowercased(),
            observation_id: request.observation_id, analysis_id: request.analysis_id, media_id: request.media_id,
            content_type: photo.contentType, byte_count: photo.byteCount, sha256: photo.sha256,
            url: try #require(URL(string: "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com/synthetic")),
            expires_at_ms: Int64(Date().addingTimeInterval(20).timeIntervalSince1970 * 1000))
    }
}
