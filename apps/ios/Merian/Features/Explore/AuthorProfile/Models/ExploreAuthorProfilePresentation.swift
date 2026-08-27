enum ExploreAuthorProfilePresentation {
    static let previewLimit = 9
    static let libraryPageSize = 30

    static func isCurrentUser(authorUserId: String, currentUserId: String?) -> Bool {
        authorUserId.lowercased() == currentUserId?.lowercased()
    }

    static func libraryNavigationTitle(
        route: ExploreAuthorProfileRoute,
        currentUserId: String?
    ) -> String {
        if isCurrentUser(authorUserId: route.authorUserId, currentUserId: currentUserId) {
            return "Your published scans"
        }

        let name = route.authorFirstName
        let possessiveName = name.hasSuffix("s") ? "\(name)’" : "\(name)’s"
        return "\(possessiveName) scans"
    }

    static func identityChangeAffects(
        authorUserId: String,
        previousUserId: String?,
        currentUserId: String
    ) -> Bool {
        let normalizedAuthorId = authorUserId.lowercased()
        return previousUserId == normalizedAuthorId || currentUserId == normalizedAuthorId
    }

    static func shouldShowProBadge(
        profile: ExploreAuthorProfile,
        currentUserId: String?,
        currentUserIsSubscribed: Bool
    ) -> Bool {
        profile.authorIsPro == true || (
            isCurrentUser(authorUserId: profile.authorUserId, currentUserId: currentUserId) &&
                currentUserIsSubscribed
        )
    }

    static func visibleAwards(
        for profile: ExploreAuthorProfile,
        fieldTripsEnabled: Bool
    ) -> [AwardPayload] {
        guard !fieldTripsEnabled else { return profile.awardPayloads }
        return profile.awardPayloads.filter { $0.type != .firstFieldTrip }
    }

    static func earnedFieldTripPatches(
        for profile: ExploreAuthorProfile,
        fieldTripsEnabled: Bool
    ) -> [EarnedFieldTripPatch] {
        guard fieldTripsEnabled, let fieldTrips = profile.fieldTrips else { return [] }
        return EarnedFieldTripPatchPresentation.items(profileSummaries: fieldTrips.active)
    }

    static func deduplicatedPosts(_ posts: [ExplorePost]) -> [ExplorePost] {
        var seenIds = Set<String>()
        return posts.filter { seenIds.insert($0.id).inserted }
    }
}

extension ExploreAuthorProfile {
    var profileTitle: String {
        if publicAuthorDisplayName == publicUsernameDisplayName {
            return "Explorer"
        }
        return publicAuthorDisplayName
    }
}
