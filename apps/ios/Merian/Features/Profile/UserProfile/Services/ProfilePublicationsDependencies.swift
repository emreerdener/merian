import Combine
import SwiftData

@MainActor
struct ProfilePublicationsDependencies {
    let loadPosts: @MainActor (
        _ authorUserID: String,
        _ limit: Int,
        _ cursor: ExploreAuthorPostCursor?
    ) async throws -> ExploreAuthorPostsResponse
    let loadPost: @MainActor (_ postID: String) async throws -> ExplorePost
    let appEvents: AnyPublisher<AppEvent, Never>
    let reviewRecovery: @MainActor (_ ownerUserID: String) -> Void
    let selectionFeedback: @MainActor () -> Void
    let resolveScanRoute: @MainActor (
        _ scanID: String,
        _ modelContext: ModelContext
    ) -> ScanInsightRoute?

    static var live: Self {
        let container = AppDIContainer.shared
        return Self(
            loadPosts: { authorUserID, limit, cursor in
                try await MerianNetworkClient.shared.getExploreAuthorPosts(
                    authorUserId: authorUserID,
                    limit: limit,
                    cursor: cursor
                )
            },
            loadPost: { postID in
                try await MerianNetworkClient.shared.getExplorePost(
                    postId: postID
                )
            },
            appEvents: container.appEventPublisher.publisher,
            reviewRecovery: { ownerUserID in
                container.hapticManager.triggerSelectionPulse()
                container.appRouteCoordinator.request(
                    .scansLibraryRecovery(
                        ExploreMediaRecoveryRouteContext(
                            ownerUserId: ownerUserID.lowercased()
                        )
                    ),
                    source: .internalUserAction
                )
            },
            selectionFeedback: {
                container.hapticManager.triggerSelectionPulse()
            },
            resolveScanRoute: { scanID, modelContext in
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { $0.id == scanID }
                )
                descriptor.fetchLimit = 1
                guard let record = try? modelContext.fetch(descriptor).first else {
                    return nil
                }
                return ScanInsightRoute(scanId: record.id)
            }
        )
    }
}
