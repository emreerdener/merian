import Foundation

enum FirstFieldTripAchievementPolicy {
    static func completionDate(
        for progress: FirstFieldTripAchievementProgress
    ) -> Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: progress.completedAt)
            ?? DateUtilities.iso8601Formatter.date(from: progress.completedAt)
    }

    static func destination(
        for progress: FirstFieldTripAchievementProgress
    ) -> CaptureGoalDestination? {
        switch progress.kind {
        case .standardOuting:
            guard let templateSlug = progress.templateSlug?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !templateSlug.isEmpty else { return nil }
            return .fieldTripTemplate(slug: templateSlug)
        case .seasonalChallenge:
            guard let challengeId = progress.challengeId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !challengeId.isEmpty else { return nil }
            return .fieldTripChallenge(challengeId: challengeId)
        }
    }

    static func awardPayload(
        for progress: FirstFieldTripAchievementProgress
    ) -> AwardPayload? {
        guard let completionDate = completionDate(for: progress),
              let destination = destination(for: progress) else { return nil }
        return AwardPayload(
            type: .firstFieldTrip,
            currentCount: 1,
            lastInteractionDate: completionDate,
            unlockedAt: completionDate,
            destination: destination
        )
    }

    static func merging(
        _ progress: FirstFieldTripAchievementProgress?,
        into awards: [AwardPayload]
    ) -> [AwardPayload] {
        guard let progress,
              let completedAward = awardPayload(for: progress) else {
            return awards
        }

        var merged = awards
        if let index = merged.firstIndex(where: { $0.type == .firstFieldTrip }) {
            merged[index] = completedAward
        } else {
            merged.append(completedAward)
        }
        return merged
    }
}

extension FirstFieldTripAchievementProgress {
    var completionDate: Date? {
        FirstFieldTripAchievementPolicy.completionDate(for: self)
    }

    var destination: CaptureGoalDestination? {
        FirstFieldTripAchievementPolicy.destination(for: self)
    }

    var awardPayload: AwardPayload? {
        FirstFieldTripAchievementPolicy.awardPayload(for: self)
    }
}

extension Array where Element == AwardPayload {
    func mergingFirstFieldTripAchievement(
        _ progress: FirstFieldTripAchievementProgress?
    ) -> [AwardPayload] {
        FirstFieldTripAchievementPolicy.merging(progress, into: self)
    }
}
