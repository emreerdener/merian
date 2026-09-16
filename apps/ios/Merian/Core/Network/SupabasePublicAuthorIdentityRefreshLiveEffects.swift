import Foundation

enum SupabasePublicAuthorRefreshLiveEffects {
    @MainActor
    static func publishIdentityChanged(
        previousUserID: String?,
        currentUserID: String
    ) {
        AppDIContainer.shared.appEventPublisher.send(
            .publicAuthorIdentityChanged(
                previousUserId: previousUserID?.lowercased(),
                currentUserId: currentUserID.lowercased()
            )
        )
    }

    @MainActor
    static func reportRefreshFailure(_ error: Error) {
        MerianLog.auth.debug(
            "Public author identity refresh failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
        )
    }
}
