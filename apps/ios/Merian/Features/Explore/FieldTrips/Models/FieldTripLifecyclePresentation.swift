extension FieldTripTemplate {
    var viewerProgress: FieldTripProgress? {
        activeProgress ?? stoppedProgress
    }

    var isStopped: Bool {
        stoppedProgress != nil
    }
}

extension FieldTripProgress {
    var isComplete: Bool { completedAt != nil }
    var isPublished: Bool { publicationId != nil }

    var fractionComplete: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }
}

extension FieldTripChallenge {
    var isLive: Bool { status == "live" }
    var isUpcoming: Bool { status == "upcoming" }
    var isEnded: Bool { status == "ended" }
}

extension FieldTripChallengeParticipation {
    var isComplete: Bool { completedAt != nil }

    var fractionComplete: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }
}
