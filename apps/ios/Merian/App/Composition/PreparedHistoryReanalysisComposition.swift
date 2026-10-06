import Foundation
import SwiftData

/// Inert assembly for qualification. Ordinary live dependencies do not install this bundle.
@MainActor
struct PreparedHistoryReanalysisComposition {
    // Source-controlled qualification boundary. No preference or remote flag can enable it.
    static let isAppInstallationQualified = false

    static func appInstallation(make: () -> Self) -> Self? {
        guard isAppInstallationQualified else { return nil }
        return make()
    }

    let history: IdentificationHistoryAccess
    let status: ReanalysisStatusAccess
    let capture: CaptureReanalysisAccess
    let reanalyze: SavedIdentificationReanalysisAccess
    let protectedChat: ProtectedInsightChatAccess
    let selectedReview: SelectedAnalysisReviewAccess

    var insightAccesses: InsightHistoryReanalysisAccesses {
        .init(history: history, status: status, reanalyze: reanalyze, protectedChat: protectedChat, selectedReview: selectedReview)
    }

    init(routes: any AppRouteRequesting, cloud: ObservationHistoryCloudClient,
         currentOwner: @escaping @MainActor () -> UUID?, generation: @escaping @MainActor () -> UInt64,
         sessionIsCurrent: @escaping @MainActor (AuthTransitionSession) -> Bool,
         preparationOwner: ObservationReanalysisPreparationOwner,
         enrollmentOwner: ObservationHistoryEnrollmentOwner, containerIsCurrent: @escaping @MainActor (ModelContainer) -> Bool,
         submitted: @escaping @MainActor (UUID) -> Void, cleanup: @escaping @MainActor () -> Void,
         reviewWake: (() -> Void)? = nil, reviewGeneration: @escaping () -> UInt64 = { 0 },
         publication: IdentificationHistoryPublicationAccess.Configuration? = nil,
         documents: @escaping @MainActor () throws -> URL = {
             try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
         },
         downloadPhoto: @escaping @Sendable (ObservationHistoryPhotoTicket) async throws -> Data = { ticket in
             try await PrivateHistoryPhotoTransport.download(ticket)
         }) {
        let photos = ObservationHistoryPhotoLoader(account: cloud, resolve: cloud.resolvePhoto, download: downloadPhoto)
        let session: (String, ModelContainer) throws -> IdentificationHistorySession = { id, container in
            try IdentificationHistorySession(observation: id, container: container, cloud: cloud, photos: photos,
                reviewWake: reviewWake, reviewGeneration: reviewGeneration, publication: publication, currentGeneration: generation, sessionIsCurrent: { currentOwner() == $0.userID && sessionIsCurrent($0) && containerIsCurrent(container) })
        }
        var history = IdentificationHistoryAccess.prepared(cloud: cloud, session: session)
        history.requestReanalysis = { routes.request(.historicalReanalysis($0), source: .internalUserAction) }
        self.history = history
        protectedChat = .prepared(cloud: cloud, session: session)
        selectedReview = .prepared(cloud: cloud, session: session)
        status = .prepared(session: session)
        reanalyze = .prepared(cloud: cloud, enrollment: enrollmentOwner, currentOwner: currentOwner,
            generation: generation, sessionIsCurrent: sessionIsCurrent, containerIsCurrent: containerIsCurrent,
            dispatch: { routes.request(.historicalReanalysis($0), source: .internalUserAction) })
        capture = .prepared(ownership: preparationOwner, account: cloud, photos: photos, documents: documents,
            isCurrentOwner: currentOwner, generation: generation, sessionIsCurrent: sessionIsCurrent, requestSubmitted: submitted, requestCleanup: cleanup)
    }

    /// Uses the supplied AppDI owners, including private photo resolution. No work starts here.
    static func prepared(in dependencies: AppDIContainer) -> Self {
        let manager = dependencies.supabaseManager
        let queue = dependencies.offlineQueueManager
        return Self(routes: dependencies.appRouteCoordinator, cloud: .live(manager: manager),
            currentOwner: { manager.currentUser?.id }, generation: { manager.authSessionGeneration },
            sessionIsCurrent: { session in
                manager.allowsUnownedAccountBoundWork
                    && manager.currentUser?.id == session.userID
                    && manager.currentUser?.isAnonymous == session.isAnonymous
                    && manager.client.auth.currentSession?.user.id == session.userID
                    && manager.client.auth.currentSession?.user.isAnonymous == session.isAnonymous
            }, preparationOwner: queue.reanalysisPreparationOwner,
            enrollmentOwner: queue.historyEnrollmentOwner, containerIsCurrent: { queue.modelContext?.container === $0 },
            submitted: { queue.requestReanalysisAdmissionRecovery(.submitted($0)) },
            cleanup: { queue.requestReanalysisErasureRecovery() },
            reviewWake: { queue.requestAnalysisReviewRecovery() }, reviewGeneration: { queue.analysisReviewDeliveryGeneration },
            publication: .init(owner: queue.publicationConsentPreparationOwner,
                recoveryOwner: queue.publicationTargetRecoveryOwner, fetchTarget: { request, owner in
                    try await MerianNetworkClient.shared.observationPublicationTarget(request, ownerID: owner)
                }, fetch: { request, owner in
                try await MerianNetworkClient.shared.prepareObservationPublicationConsent(request, ownerID: owner)
            }, wake: { OfflineJobScheduler.shared.scheduleNextPersistedWake(using: queue) },
                generation: { queue.publicationDeliveryGeneration }))
    }
}
