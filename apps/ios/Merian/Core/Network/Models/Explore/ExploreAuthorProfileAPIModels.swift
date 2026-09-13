import Foundation

struct ExploreAuthorProfile: Decodable, Equatable {
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorIsPro: Bool?
    let authorAvatarUrl: String?
    let speciesCount: Int
    let currentStreak: Int
    let heatmap: ExploreAuthorProfileHeatmap
    let awards: [ExploreAuthorProfileAward]
    let publishedPostCount: Int
    var followerCount: Int
    var followingCount: Int
    var viewerIsFollowing: Bool
    let viewerCanReport: Bool?
    let previewPosts: [ExplorePost]
    let fieldTrips: FieldTripProfileSummaries?
    let ownerPublicationSummary: ExploreOwnerPublicationSummary?

    var authorAvatarURL: URL? {
        SecureTransportPolicy.httpsURL(from: authorAvatarUrl)
    }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    var publicUsernameDisplayName: String? {
        ExplorePost.publicUsernameDisplayValue(authorUsername)
    }

    var profileHeatmapData: ProfileHeatmapData {
        heatmap.profileHeatmapData
    }

    var awardPayloads: [AwardPayload] {
        let payloadsByType = awards.reduce(into: [AchievementType: AwardPayload]()) { partialResult, award in
            guard let payload = award.awardPayload else { return }
            partialResult[payload.type] = payload
        }

        return AchievementType.allCases.map { type in
            payloadsByType[type] ?? AwardPayload(type: type, currentCount: 0, lastInteractionDate: nil)
        }
    }
}

struct ExploreOwnerPublicationSummary: Decodable, Equatable {
    let publicationIntentCount: Int
    let visiblePostCount: Int
    let recoveryNeededPostCount: Int
    let degradedPostCount: Int
    let quarantinedPostCount: Int
}

enum ExploreUserReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam"
    case harassment = "Harassment"
    case impersonation = "Impersonation"
    case inappropriateProfile = "Inappropriate profile"
    case other = "Other"

    var id: String { rawValue }
}

struct ExploreAuthorProfileAward: Decodable, Equatable {
    let type: String
    let currentCount: Int
    let lastInteractionAt: String?

    var awardPayload: AwardPayload? {
        guard let achievementType = AchievementType(rawValue: type) else {
            return nil
        }

        return AwardPayload(
            type: achievementType,
            currentCount: currentCount,
            lastInteractionDate: parsedLastInteractionDate
        )
    }

    private var parsedLastInteractionDate: Date? {
        guard let lastInteractionAt else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: lastInteractionAt)
            ?? DateUtilities.iso8601Formatter.date(from: lastInteractionAt)
    }
}

struct ExploreAuthorProfileHeatmap: Decodable, Equatable {
    let totalCaptures: Int
    let currentMonthCaptures: Int
    let yearString: String
    let weeks: [ExploreAuthorProfileHeatmapWeek]

    var profileHeatmapData: ProfileHeatmapData {
        ProfileHeatmapData(
            totalCaptures: totalCaptures,
            currentMonthCaptures: currentMonthCaptures,
            yearString: yearString,
            weeks: weeks.map(\.profileHeatmapWeek)
        )
    }
}

struct ExploreAuthorProfileHeatmapWeek: Decodable, Equatable {
    let monthLabel: String?
    let days: [ExploreAuthorProfileHeatmapDay]

    var profileHeatmapWeek: HeatmapWeek {
        HeatmapWeek(
            days: days.map(\.profileHeatmapDay),
            monthLabel: monthLabel
        )
    }
}

struct ExploreAuthorProfileHeatmapDay: Decodable, Equatable {
    let count: Int
    let date: String

    var profileHeatmapDay: HeatmapDay {
        HeatmapDay(
            count: count,
            date: DateUtilities.iso8601Formatter.date(from: date) ?? Date(timeIntervalSince1970: 0)
        )
    }
}
