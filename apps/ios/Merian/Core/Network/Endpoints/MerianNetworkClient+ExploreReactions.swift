import Foundation

extension MerianNetworkClient {
    func setExploreReaction(target: ExploreReactionTarget, id: String, emoji: String, selected: Bool) async throws
        -> ExploreReactionResponse {
        try await performAuthenticatedJSONPost(
            function: "set-explore-\(target.rawValue)-reaction",
            payload: ["\(target.rawValue)_id": id, "emoji": emoji, "selected": selected],
            responseType: ExploreReactionResponse.self
        )
    }

    func getExploreReactions(target: ExploreReactionTarget, id: String, afterOrder: Int) async throws
        -> ExploreReactionPage {
        try await performAuthenticatedJSONPost(
            function: "get-explore-reactions",
            payload: ["target_kind": target.rawValue, "target_id": id, "after_order": afterOrder],
            responseType: ExploreReactionPage.self
        )
    }
    func getExplorePostReactors(postId: String, afterUserId: String?) async throws -> ExplorePostReactorsPage {
        var payload: [String: Any] = ["post_id": postId]
        if let afterUserId { payload["after_user_id"] = afterUserId }
        return try await performAuthenticatedJSONPost(
            function: "get-explore-post-reactors", payload: payload,
            responseType: ExplorePostReactorsPage.self)
    }

}
