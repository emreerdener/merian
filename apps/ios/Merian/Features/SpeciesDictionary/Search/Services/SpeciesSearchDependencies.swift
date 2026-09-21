extension SpeciesSearchViewModel.Dependencies {
    static var live: Self {
        Self(search: { try await MerianNetworkClient.shared.searchSpecies($0) },
             errorMessage: { ExploreErrorFormatter.message(for: $0) })
    }
}

@MainActor
enum SpeciesSearchSightings {
    static func canSurface(_ post: ExplorePost, in feed: ExploreFeedViewModel) -> Bool {
        feed.postRemovalRevisions[post.id, default: 0] == 0 && !feed.blockedAuthorUserIDs.contains(post.authorUserId)
    }
    static func register(_ posts: [ExplorePost], previous: [ExplorePost], in feed: ExploreFeedViewModel) {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for post in posts where previousByID[post.id] != post {
            // Pagination must not revive a post removed during this Explore session.
            guard canSurface(post, in: feed) else { continue }
            feed.upsertPost(post)
        }
    }
}
