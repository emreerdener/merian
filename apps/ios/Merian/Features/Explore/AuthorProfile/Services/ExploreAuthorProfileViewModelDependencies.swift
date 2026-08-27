extension ExploreAuthorProfileViewModel.Dependencies {
    static let live = Self(
        loadProfile: { authorUserId, previewLimit in
            try await MerianNetworkClient.shared.getExploreAuthorProfile(
                authorUserId: authorUserId,
                previewLimit: previewLimit
            )
        },
        loadPosts: { authorUserId, limit, cursor in
            try await MerianNetworkClient.shared.getExploreAuthorPosts(
                authorUserId: authorUserId,
                limit: limit,
                cursor: cursor
            )
        },
        setFollowing: { authorUserId, isFollowing in
            try await MerianNetworkClient.shared.setUserFollow(
                authorUserId: authorUserId,
                isFollowing: isFollowing
            )
        },
        prefetchImages: { imageUrls in
            LocalImageLoader.shared.prefetch(
                records: imageUrls.map {
                    (imagePath: Optional<String>.none, fallbackUrl: $0)
                },
                maxDimension: 360
            )
        },
        successFeedback: { HapticManager.shared.triggerSelectionPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension ExploreReportUserViewModel.Dependencies {
    static let live = Self(
        reportUser: { reportedUserId, reason, details in
            try await MerianNetworkClient.shared.reportUser(
                reportedUserId: reportedUserId,
                reason: reason,
                details: details
            )
        },
        successFeedback: { HapticManager.shared.triggerSuccessPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}
