enum ExploreAuthorProfileNavigationPolicy {
    static let maxProfileDepth = 1

    static func canOpenProfile(from currentDepth: Int) -> Bool {
        currentDepth < maxProfileDepth
    }

    static func nextProfileDepth(from currentDepth: Int) -> Int {
        min(currentDepth + 1, maxProfileDepth)
    }
}

struct ExploreAuthorProfileRoute: Identifiable, Equatable, Hashable {
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let navigationDepth: Int

    var id: String { authorUserId }

    var authorFirstName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    init(post: ExplorePost, navigationDepth: Int = 0) {
        self.authorUserId = post.authorUserId
        self.authorName = post.authorName
        self.authorUsername = post.authorUsername
        self.authorAvatarUrl = post.authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    init(comment: ExploreComment, navigationDepth: Int = 0) {
        self.authorUserId = comment.authorUserId
        self.authorName = comment.authorName
        self.authorUsername = comment.authorUsername
        self.authorAvatarUrl = comment.authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    init(mention: ExploreCommentMention, navigationDepth: Int = 0) {
        self.authorUserId = mention.userId
        self.authorName = mention.displayName
        self.authorUsername = mention.username
        self.authorAvatarUrl = mention.avatarUrl
        self.navigationDepth = navigationDepth
    }

    init(
        authorUserId: String,
        authorName: String,
        authorUsername: String?,
        authorAvatarUrl: String?,
        navigationDepth: Int = 0
    ) {
        self.authorUserId = authorUserId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorAvatarUrl = authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    func withNavigationDepth(_ depth: Int) -> ExploreAuthorProfileRoute {
        ExploreAuthorProfileRoute(
            authorUserId: authorUserId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorAvatarUrl: authorAvatarUrl,
            navigationDepth: depth
        )
    }
}
