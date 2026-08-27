extension ExploreHashtagPostsViewModel.Dependencies {
    static let live = Self(
        loadPage: { hashtag, limit, cursor in
            try await MerianNetworkClient.shared.getExploreHashtagPosts(
                hashtag: hashtag,
                limit: limit,
                cursor: cursor
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}
