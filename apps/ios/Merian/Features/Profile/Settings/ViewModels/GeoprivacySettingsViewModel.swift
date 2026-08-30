import Observation

@MainActor
@Observable
final class GeoprivacySettingsViewModel {
    private(set) var isUpdating = false

    private let dependencies: GeoprivacySettingsDependencies
    private var pendingOptionID: String?

    init(dependencies: GeoprivacySettingsDependencies) {
        self.dependencies = dependencies
    }

    /// Serializes writes and coalesces queued selections to the latest value.
    /// This keeps the server preference aligned with rapid optimistic UI taps.
    func queuePreferenceUpdate(_ optionID: String) {
        pendingOptionID = optionID
        guard !isUpdating else { return }

        isUpdating = true
        Task { await drainPendingUpdates() }
    }

    private func drainPendingUpdates() async {
        while let optionID = pendingOptionID {
            pendingOptionID = nil
            await dependencies.updatePreference(optionID)
        }

        isUpdating = false
    }
}
