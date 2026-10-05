import Foundation
import SwiftData
import UIKit

@MainActor
struct IdentificationHistoryAccess {
    let hasMultiple: (String, ModelContainer) -> Bool
    let open: (String, ModelContainer) throws -> IdentificationHistoryDependencies
    var requestReanalysis: ((HistoricalReanalysisTarget) -> Void)?

    /// Prepared opt-in only. InsightShellDependencies.live supplies nil until the
    /// complete history activation contract is satisfied.
    static func prepared(routes: any AppRouteRequesting) -> Self {
        var access = prepared
        access.requestReanalysis = { target in
            routes.request(.historicalReanalysis(target), source: .internalUserAction)
        }
        return access
    }

    static var prepared: Self {
        prepared(cloud: .live, session: { try IdentificationHistorySession(observation: $0, container: $1) })
    }

    static func prepared(cloud: ObservationHistoryCloudClient,
                         session: @escaping (String, ModelContainer) throws -> IdentificationHistorySession) -> Self {
        Self(hasMultiple: { id, container in
            guard let current = try? session(id, container), current.isCurrent() else { return false }
            defer { current.close() }
            return (try? ObservationHistoryListingService(cloud: cloud).hasMultiple(observationID: id, container: container)) ?? false
        }, open: { id, container in try session(id, container).dependencies })
    }
}

@MainActor
struct IdentificationHistoryDependencies {
    var context: () throws -> ObservationHistoryListingService.Context
    var page: (Int?) async throws -> IdentificationHistoryPage
    var preview: (UUID) async throws -> IdentificationHistoryDetail
    var prepare: (UUID) throws -> Void
    var prepareUndo: (UUID) throws -> Void
    var sendPending: () async throws -> ObservationHistorySelectionOutcome
    var photo: (UUID, UUID) async throws -> UIImage
    var isCurrent: () -> Bool
    var close: () -> Void
    var now: () -> Date = Date.init
    var reanalysis: ((UUID, ObservationHistoryListingService.Context) throws -> IdentificationHistoryReanalysisAction)?
}

/// Retains only account/session values for one sheet. Each Core operation owns
/// its short-lived work lease; idle or background UI cannot block Auth draining.
@MainActor
final class IdentificationHistorySession {
    let observation: String
    let container: ModelContainer
    let cloud: ObservationHistoryCloudClient
    private let photos: ObservationHistoryPhotoLoader
    let session: AuthTransitionSession
    let generation: UInt64
    private let currentGeneration: @MainActor () -> UInt64
    private let sessionIsCurrent: @MainActor (AuthTransitionSession) -> Bool
    private var closed = false

    init(observation: String, container: ModelContainer,
         cloud: ObservationHistoryCloudClient = .live,
         photos: ObservationHistoryPhotoLoader? = nil,
         currentGeneration: @escaping @MainActor () -> UInt64 = { SupabaseManager.shared.authSessionGeneration },
         sessionIsCurrent: @escaping @MainActor (AuthTransitionSession) -> Bool = { session in
             let manager = SupabaseManager.shared
             return manager.allowsUnownedAccountBoundWork
                 && manager.currentUser?.id == session.userID
                 && manager.currentUser?.isAnonymous == session.isAnonymous
                 && manager.client.auth.currentSession?.user.id == session.userID
                 && manager.client.auth.currentSession?.user.isAnonymous == session.isAnonymous
         }) throws {
        self.observation = observation; self.container = container
        self.photos = photos ?? ObservationHistoryPhotoLoader(account: cloud, resolve: cloud.resolvePhoto)
        self.cloud = cloud; self.currentGeneration = currentGeneration; self.sessionIsCurrent = sessionIsCurrent
        let state = try ObservationHistoryListingService(cloud: cloud).context(observationID: observation, container: container)
        let lease = try cloud.begin(state.owner)
        defer { cloud.finish(lease) }
        guard lease.session.userID == state.owner, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        session = lease.session; generation = currentGeneration()
        guard sessionIsCurrent(session) else { throw ObservationHistoryError.accountChanged }
    }
    func isCurrent() -> Bool {
        !closed && currentGeneration() == generation && sessionIsCurrent(session)
    }
    func check() throws {
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let state = try ObservationHistoryListingService(cloud: cloud).context(observationID: observation, container: container)
        guard state.owner == session.userID else { throw ObservationHistoryError.accountChanged }
    }
    func close() {
        guard !closed else { return }
        closed = true
    }
    var dependencies: IdentificationHistoryDependencies {
        let listing = ObservationHistoryListingService(cloud: cloud)
        let selection = ObservationHistorySelectionService(cloud: cloud)
        return IdentificationHistoryDependencies(context: { [self] in
            try check(); return try listing.context(observationID: observation, container: container)
        }, page: { [self] before in
            try check()
            if try listing.context(observationID: observation, container: container).pendingOperation == nil {
                _ = try await ObservationHistoryStateSyncService(cloud: cloud).syncSelected(observationID: observation, container: container)
            }
            let page = try await listing.page(observationID: observation, beforeOrdinal: before, container: container)
            try check()
            return IdentificationHistoryPage(rows: try page.entries.map(IdentificationHistoryPresentation.row), nextBeforeOrdinal: page.nextBeforeOrdinal, context: page.context)
        }, preview: { [self] analysis in
            try check()
            var cached = false
            do { _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation, analysisID: analysis, container: container) }
            catch ObservationHistoryError.unavailable { cached = true }
            catch is URLError { cached = true }
            try check()
            let entry = try listing.cached(observationID: observation, analysisID: analysis, container: container)
            return try IdentificationHistoryPresentation.detail(entry, context: listing.context(observationID: observation, container: container), cached: cached)
        }, prepare: { [self] target in
            try check(); try selection.prepare(observationID: observation, analysisID: target, ownerID: session.userID, container: container)
        }, prepareUndo: { [self] operation in
            try check(); try selection.prepareUndo(observationID: observation, operationID: operation, ownerID: session.userID, container: container)
        }, sendPending: { [self] in
            try check(); let result = try await selection.sendPending(observationID: observation, container: container)
            try check(); return result
        }, photo: { [self] analysis, media in
            try check()
            let bytes = try await photos.load(observationID: observation, analysisID: analysis, mediaID: media, container: container)
            let image = await Self.downsample(bytes)
            try check()
            guard let image else { throw ObservationHistoryError.unavailable }
            return UIImage(cgImage: image.cgImage)
        }, isCurrent: { [self] in isCurrent() }, close: { [self] in close() },
           reanalysis: { [self] analysis, context in try reanalysisAction(analysis, context: context) })
    }
    func reanalysisAction(_ analysis: UUID, context: ObservationHistoryListingService.Context) throws -> IdentificationHistoryReanalysisAction {
        try check()
        guard context.pendingOperation == nil, context.owner == session.userID,
              try ObservationHistoryListingService(cloud: cloud).context(observationID: observation, container: container) == context else {
            throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
        }
        let source = try ObservationReanalysisSource.capture(observationID: ObservationHistoryPage.uuid(observation),
            analysisID: analysis, ownerID: context.owner, container: container)
        // A committed handoff may outlive the dismissed sheet, but never its account,
        // source or revision. It retains values and no long-lived account lease.
        let action = IdentificationHistoryReanalysisAction { [cloud, container, session, generation, currentGeneration, sessionIsCurrent, observation] in
            guard currentGeneration() == generation, sessionIsCurrent(session) else { throw ObservationHistoryError.accountChanged }
            guard try ObservationHistoryListingService(cloud: cloud).context(observationID: observation, container: container) == context else {
                throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
            }
            try source.validate(container: container)
            return HistoricalReanalysisTarget(observationID: source.observationID, analysisID: source.analysisID, ownerID: source.ownerID)
        }
        _ = try action.resolve()
        return action
    }
    nonisolated private static func downsample(_ data: Data) async -> ImageDownsampler.SendableImage? {
        ImageDownsampler.downsampledSendableImage(data: data, maxSize: 1_280)
    }
}
