import Foundation

struct FieldTripProgressUpdatesResponse: Decodable {
    let data: [FieldTripProgressUpdate]
    let challengeUpdates: [FieldTripChallengeProgressUpdate]
    let firstFieldTripAchievement: FirstFieldTripAchievementProgress?
    let firstFieldTripAchievementNewlyUnlocked: Bool

    private enum CodingKeys: String, CodingKey {
        case data
        case challengeUpdates
        case firstFieldTripAchievement
        case firstFieldTripAchievementNewlyUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([FieldTripProgressUpdate].self, forKey: .data) ?? []
        challengeUpdates = try container.decodeIfPresent([FieldTripChallengeProgressUpdate].self, forKey: .challengeUpdates) ?? []
        firstFieldTripAchievement = try container.decodeIfPresent(
            FirstFieldTripAchievementProgress.self,
            forKey: .firstFieldTripAchievement
        )
        firstFieldTripAchievementNewlyUnlocked = try container.decodeIfPresent(
            Bool.self,
            forKey: .firstFieldTripAchievementNewlyUnlocked
        ) ?? false
    }
}

struct FieldTripProgressResult: Equatable {
    let fieldTripUpdates: [FieldTripProgressUpdate]
    let challengeUpdates: [FieldTripChallengeProgressUpdate]
    let firstFieldTripAchievement: FirstFieldTripAchievementProgress?
    let firstFieldTripAchievementNewlyUnlocked: Bool

    init(
        fieldTripUpdates: [FieldTripProgressUpdate],
        challengeUpdates: [FieldTripChallengeProgressUpdate],
        firstFieldTripAchievement: FirstFieldTripAchievementProgress? = nil,
        firstFieldTripAchievementNewlyUnlocked: Bool = false
    ) {
        self.fieldTripUpdates = fieldTripUpdates
        self.challengeUpdates = challengeUpdates
        self.firstFieldTripAchievement = firstFieldTripAchievement
        self.firstFieldTripAchievementNewlyUnlocked = firstFieldTripAchievementNewlyUnlocked
    }
}

struct FieldTripProgress: Decodable, Equatable, Sendable {
    let userFieldTripId: String
    let startedAt: String
    let currentLevelNumber: Int
    let completedAt: String?
    let isProfileVisible: Bool
    let completedCount: Int
    let targetCount: Int
    let publicationId: String?
    let publishedAt: String?
    let stoppedAt: String?
}

struct FieldTripProgressUpdate: Decodable, Identifiable, Equatable {
    let userFieldTripId: String
    let templateId: String
    let slug: String
    let title: String
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let creditedLevelNumber: Int?
    let creditedLevelTitle: String?
    let creditedCompletedCount: Int?
    let creditedTargetCount: Int?
    let newlyCompletedItems: [FieldTripProgressCompletedItem]
    let removedItemIds: [String]?

    var id: String { userFieldTripId }
}

struct FieldTripProgressCompletedItem: Decodable, Identifiable, Equatable {
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let completedAt: String?

    var id: String { itemId }
}

struct FieldTripChallengeProgressUpdate: Decodable, Identifiable, Equatable {
    let participationId: String
    let challengeId: String
    let slug: String
    let title: String
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let badgeAwardedAt: String?
    let suggestedHashtags: [String]
    let creditedLevelNumber: Int?
    let creditedLevelTitle: String?
    let creditedCompletedCount: Int?
    let creditedTargetCount: Int?
    let newlyCompletedItems: [FieldTripProgressCompletedItem]
    let removedItemIds: [String]?

    var id: String { participationId }
}
