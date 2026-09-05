import Foundation

enum GhostProfileMergePolicy {
    nonisolated static func enqueuing(
        _ pending: PendingGhostProfileMerge,
        in handoffs: [PendingGhostProfileMerge]
    ) -> [PendingGhostProfileMerge] {
        var updated = handoffs.filter {
            $0.ghostUserId.caseInsensitiveCompare(pending.ghostUserId)
                != .orderedSame
        }
        updated.append(pending)
        return updated
    }

    nonisolated static func shouldDiscardPendingHandoff(
        serverCode: String?
    ) -> Bool {
        serverCode == "handoff_expired"
            || serverCode == "handoff_invalid"
    }
}
