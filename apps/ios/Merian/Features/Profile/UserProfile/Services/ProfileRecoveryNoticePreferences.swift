import Foundation

enum ProfileRecoveryNoticePreferences {
    static func isDismissed(
        summary: ProfilePublicationRecoverySummary,
        signature: String?
    ) -> Bool {
        guard let count = dismissedCount(signature: signature) else { return false }
        return summary.recoveryNeededCount <= count
    }

    /// Only confirmed counts may reduce the acknowledged count. Loading and
    /// failed refreshes must preserve the dismissal.
    static func reconcile(
        stats: ProfileSocialStats?,
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) {
        guard let stats else { return }
        guard let summary = ProfilePublicationRecoverySummary.publishedOnly(from: stats) else {
            clear(ownerUserID: ownerUserID, defaults: defaults)
            return
        }
        guard isDismissed(
            summary: summary,
            signature: dismissedSignature(ownerUserID: ownerUserID, defaults: defaults)
        ) else { return }
        dismiss(
            signature: summary.overviewDismissalSignature,
            ownerUserID: ownerUserID,
            defaults: defaults
        )
    }

    private static func dismissedCount(signature: String?) -> Int? {
        guard let signature else { return nil }
        let fields = signature.split(separator: ":", omittingEmptySubsequences: false)
        // Preserve dismissals saved by the previous four-total format.
        let count: Int?
        switch fields.count {
        case 1: count = Int(fields[0])
        case 4: count = Int(fields[2])
        default: count = nil
        }
        guard let count, count > 0 else { return nil }
        return count
    }

    static func dismissedSignature(
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard !ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return defaults.string(forKey: preferenceKey(ownerUserID: ownerUserID))
    }

    static func dismiss(
        signature: String,
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) {
        guard !signature.isEmpty,
              !ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        defaults.set(signature, forKey: preferenceKey(ownerUserID: ownerUserID))
    }

    static func clear(
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) {
        guard !ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        defaults.removeObject(forKey: preferenceKey(ownerUserID: ownerUserID))
    }

    static func preferenceKey(ownerUserID: String) -> String {
        let normalizedOwnerUserID = ownerUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return UserDefaultsKeys
            .dismissedProfilePublicationRecoverySignaturePrefix +
            normalizedOwnerUserID
    }
}
