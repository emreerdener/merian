import Foundation

enum MilestoneToastSource: Sendable, Equatable {
    case unlock
    case preview
}

struct DictionaryMilestonePayload: Sendable, Equatable {
    let title: String
    let subtitle: String
    let imageName: String

    static let newToMerian = DictionaryMilestonePayload(
        title: "New to Naturebook",
        subtitle: "Added to the species dictionary",
        imageName: "star"
    )
}

struct FieldTripMilestonePayload: Sendable, Equatable {
    let tripTitle: String
    let goalLabel: String
    let artwork: CaptureGoalArtwork
    let destination: CaptureGoalDestination

    var title: String {
        goalLabel.isEmpty ? "Goal complete" : "\(goalLabel) goal complete"
    }

    static func standard(
        update: FieldTripProgressUpdate
    ) -> FieldTripMilestonePayload? {
        guard let item = update.newlyCompletedItems.first else { return nil }

        return FieldTripMilestonePayload(
            tripTitle: update.title,
            goalLabel: item.toastGoalLabel,
            artwork: toastArtwork(for: item, templateSlug: update.slug),
            destination: .fieldTrip(
                templateId: update.templateId,
                checklistItemId: item.itemId
            )
        )
    }

    static func challenge(
        update: FieldTripChallengeProgressUpdate
    ) -> FieldTripMilestonePayload? {
        guard let item = update.newlyCompletedItems.first else { return nil }

        return FieldTripMilestonePayload(
            tripTitle: update.title,
            goalLabel: item.toastGoalLabel,
            artwork: toastArtwork(for: item, templateSlug: update.slug),
            destination: .fieldTripChallenge(challengeId: update.challengeId)
        )
    }

    private static func toastArtwork(
        for item: FieldTripProgressCompletedItem,
        templateSlug: String
    ) -> CaptureGoalArtwork {
        guard let imageName = FieldTripGoalArtwork.exactImageName(
            for: item.prompt,
            templateSlug: templateSlug
        ) else {
            return .systemSymbol(name: "binoculars.fill")
        }

        return .bundledImage(name: imageName)
    }

    #if DEBUG
    static let preview = FieldTripMilestonePayload(
        tripTitle: "Backyard Safari",
        goalLabel: "Spider",
        artwork: .bundledImage(name: "fieldtrip-backyard-spider"),
        destination: .fieldTrip(
            templateId: "preview",
            checklistItemId: "preview"
        )
    )
    #endif
}

private extension FieldTripProgressCompletedItem {
    var toastGoalLabel: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MilestoneToastPayload: Sendable, Equatable {
    case fieldTrip(FieldTripMilestonePayload)
    case achievement(AwardPayload)
    case dictionary(DictionaryMilestonePayload)
}

struct MilestoneToastItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let payload: MilestoneToastPayload
    let source: MilestoneToastSource

    var award: AwardPayload? {
        guard case let .achievement(award) = payload else { return nil }
        return award
    }
}

enum MilestoneToastDeduplicationKey: Sendable, Equatable {
    case fieldTrip(destination: CaptureGoalDestination, goalLabel: String)
    case achievement(AchievementType)
    case dictionary(title: String)
}

enum MilestoneToastEnqueueOutcome: Sendable, Equatable {
    case enqueued(UUID)
    case coalesced(into: UUID)
    case droppedOverflow
    case rejectedStaleSession
}

struct MilestoneToastSessionToken: Sendable, Equatable {
    let accountGeneration: UInt64
    let sessionGeneration: UInt64
}
