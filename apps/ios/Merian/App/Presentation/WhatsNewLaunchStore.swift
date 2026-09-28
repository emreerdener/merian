import Foundation

/// A stable content identifier prevents repeated prompts across beta builds.
struct WhatsNewLaunchStore {
    static let currentReleaseID = "2026-09-faster-identifications"

    var defaults: UserDefaults = .standard
    var releaseID: String = Self.currentReleaseID

    func prepareLaunch(
        hasCompletedOnboarding: Bool,
        isRunningTests: Bool,
        hasStartupInterruption: Bool
    ) -> Bool {
        guard !isRunningTests else { return false }
        // New installations already start with these features. They should not
        // get an update announcement after finishing their first onboarding.
        guard hasCompletedOnboarding else {
            acknowledge()
            return false
        }
        guard !hasStartupInterruption else { return false }
        return defaults.string(forKey: UserDefaultsKeys.lastSeenWhatsNewRelease)
            != releaseID
    }

    func acknowledge() {
        defaults.set(releaseID, forKey: UserDefaultsKeys.lastSeenWhatsNewRelease)
    }
}
