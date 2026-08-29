struct ProfilePublicationRecoverySummary: Equatable {
    let publicationIntentCount: Int
    let visibleCount: Int
    let recoveryNeededCount: Int
    let quarantinedCount: Int

    static func publishedOnly(from stats: ProfileSocialStats) -> Self? {
        let publicationIntentCount = max(stats.publicationIntentCount, 0)
        let recoveryNeededCount = min(
            max(stats.recoveryNeededPostCount, 0),
            publicationIntentCount
        )
        guard recoveryNeededCount > 0 else { return nil }

        return Self(
            publicationIntentCount: publicationIntentCount,
            visibleCount: min(
                max(stats.visiblePublishedPostCount, 0),
                publicationIntentCount
            ),
            recoveryNeededCount: recoveryNeededCount,
            quarantinedCount: min(
                max(stats.quarantinedPostCount, 0),
                recoveryNeededCount
            )
        )
    }

    var userFacingTitle: String {
        let noun = recoveryNeededCount == 1 ? "scan" : "scans"
        let verb = recoveryNeededCount == 1 ? "needs" : "need"
        return "\(recoveryNeededCount.formatted()) published \(noun) \(verb) attention"
    }

    var userFacingMessage: String {
        let safetyMessage = "Your posts and activity are safe."

        if quarantinedCount == recoveryNeededCount {
            let unavailableMessage = recoveryNeededCount == 1
                ? "Its media isn’t available, so it’s temporarily hidden from Explore."
                : "Their media isn’t available, so they’re temporarily hidden from Explore."
            return "\(unavailableMessage) \(safetyMessage)"
        }

        if quarantinedCount > 0 {
            let hiddenSubject = quarantinedCount == 1
                ? "one scan is"
                : "\(quarantinedCount.formatted()) scans are"
            return "Some media isn’t available, so \(hiddenSubject) temporarily hidden from Explore. "
                + safetyMessage
        }

        return "Some media isn’t available, but these scans remain visible in Explore. "
            + safetyMessage
    }

    var userFacingEmptyMessage: String {
        "Your published scans are temporarily hidden until their media is available again."
    }

    var overviewDismissalSignature: String {
        [
            publicationIntentCount,
            visibleCount,
            recoveryNeededCount,
            quarantinedCount
        ]
        .map(String.init)
        .joined(separator: ":")
    }
}
