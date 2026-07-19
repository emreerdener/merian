import Foundation

@MainActor
enum FieldTripsAvailability {
    static let isEnabled = true
}

@MainActor
enum FieldTripEventsAvailability {
    // swiftlint:disable:next todo
    // TODO(field-trip-events-release): When Events UI/UX is ready, follow the release
    // checklist in docs/features-and-hardware/25-field-trips.md, set this flag to true,
    // promote the preview changelog copy, and remove the tester/simulator bypasses.
    static let isReleased = false
    static let allowedEmail = "erdener.emre@gmail.com"

    static var isEnabled: Bool {
        isEnabled(
            isReleased: isReleased,
            email: SupabaseManager.shared.currentUser?.email,
            isSimulator: isSimulatorBuild
        )
    }

    static func isEnabled(isReleased: Bool, email: String?, isSimulator: Bool) -> Bool {
        if isReleased || isSimulator { return true }
        return email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == allowedEmail
    }

    static func logRolloutState() {
        #if DEBUG
        if isReleased {
            MerianLog.general.notice(
                "Field Trips rollout: Outings and Events are public."
            )
        } else {
            MerianLog.general.notice(
                "TODO(field-trip-events-release): Outings are public; Events remain staged to the tester allowlist and simulator builds."
            )
        }
        #endif
    }

    private static var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
