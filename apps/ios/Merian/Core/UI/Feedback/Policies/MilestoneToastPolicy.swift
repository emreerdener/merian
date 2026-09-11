import Foundation

enum MilestoneToastPolicy {
    static func normalizedAccountID(_ accountID: String?) -> String? {
        let trimmed = accountID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    static func deduplicationKey(
        for payload: MilestoneToastPayload
    ) -> MilestoneToastDeduplicationKey {
        switch payload {
        case .fieldTrip(let progress):
            .fieldTrip(
                destination: progress.destination,
                goalLabel: progress.goalLabel
            )
        case .achievement(let award):
            .achievement(award.type)
        case .dictionary(let milestone):
            .dictionary(title: milestone.title)
        }
    }
}
