import Foundation

enum ExploreReactionTarget: String, Encodable {
    case post, comment
}

struct ExploreReactionPage: Decodable {
    let reactions: [ExploreCommentReaction]
    let reactionsNextCursor: Int?
}

struct ExploreReactionResponse: Decodable {
    let targetId: String
    let reaction: ExploreCommentReaction
    let likeCount: Int?
    let viewerHasLiked: Bool?
}

struct ExplorePostReactor: Decodable, Identifiable, Equatable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let emojis: [String]
    var id: String { userId }
}

struct ExplorePostReactorsPage: Decodable {
    let totalCount: Int
    let previewNames: [String]
    let reactors: [ExplorePostReactor]
    let nextCursor: String?
}
