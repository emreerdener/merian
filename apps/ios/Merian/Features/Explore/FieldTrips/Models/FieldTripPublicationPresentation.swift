extension FieldTripRecentPublication {
    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    var communityReasonLabel: String? {
        if viewerIsFollowingAuthor {
            return "Following"
        }

        switch communityReason {
        case "near_you":
            return "Near you"
        case "global":
            return "Global"
        case "new":
            return "New"
        case "following":
            return "Following"
        default:
            return nil
        }
    }
}

extension FieldTripChallengeEntry {
    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}

extension FieldTripChallengeEntryDetail {
    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}

extension FieldTripPublicationDetail {
    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}
