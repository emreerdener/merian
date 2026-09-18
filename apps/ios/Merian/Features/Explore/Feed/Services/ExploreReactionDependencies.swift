import Foundation

struct ExploreReactionDependencies {
    var set: @MainActor (ExploreReactionTarget, String, String, Bool) async throws -> ExploreReactionResponse
    var load: @MainActor (ExploreReactionTarget, String, Int) async throws -> ExploreReactionPage

    var loadPeople: @MainActor (String, String?) async throws -> ExplorePostReactorsPage = { _, _ in
        throw URLError(.unsupportedURL)
    }

    static var live: Self {
        .init(
            set: {
                try await MerianNetworkClient.shared.setExploreReaction(target: $0, id: $1, emoji: $2, selected: $3)
            },
            load: { try await MerianNetworkClient.shared.getExploreReactions(target: $0, id: $1, afterOrder: $2) },
            loadPeople: { try await MerianNetworkClient.shared.getExplorePostReactors(postId: $0, afterUserId: $1) }
        )
    }

    static var unavailable: Self {
        .init(
            set: { _, _, _, _ in throw URLError(.unsupportedURL) }, load: { _, _, _ in throw URLError(.unsupportedURL) }
        )
    }
}
