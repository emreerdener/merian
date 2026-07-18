import Foundation

@MainActor
enum FieldTripsAvailability {
    // TODO(field-trips-release): Remove this preview allowlist when Field trips are ready
    // for public release. Then remove the allowlist-specific tests and update README.md,
    // CHANGELOG.md, docs/rfcs/explore-page.md, and the Explore shell README.
    static let allowedEmail = "erdener.emre@gmail.com"

    static var isEnabled: Bool {
        isEnabled(
            email: SupabaseManager.shared.currentUser?.email,
            isSimulator: isSimulatorBuild
        )
    }

    static func isEnabled(email: String?, isSimulator: Bool) -> Bool {
        if isSimulator { return true }
        return email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == allowedEmail
    }

    private static var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
