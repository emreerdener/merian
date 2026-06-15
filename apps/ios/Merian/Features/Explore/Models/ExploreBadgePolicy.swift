import Foundation

enum ExploreBadgePolicy {
    static func hasUnseenExternalPost(
        in recentPosts: [ExplorePost],
        lastSeenSharedAt: String
    ) -> Bool {
        guard let lastSeenDate = DateUtilities.iso8601FractionalFormatter.date(from: lastSeenSharedAt)
            ?? DateUtilities.iso8601Formatter.date(from: lastSeenSharedAt) else {
            return false
        }

        return recentPosts.contains { post in
            guard !post.isOwnedByViewer, let sharedAtDate = post.sharedAtDate else { return false }
            return sharedAtDate > lastSeenDate
        }
    }
}
