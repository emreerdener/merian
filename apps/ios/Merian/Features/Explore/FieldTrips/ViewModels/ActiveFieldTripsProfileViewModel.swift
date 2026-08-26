import Foundation
import Observation

@MainActor
@Observable
final class ActiveFieldTripsProfileViewModel {
    struct Dependencies {
        let loadTemplates: @MainActor (_ limit: Int) async throws -> [FieldTripTemplate]
        let earnedPatchesDidChange: @MainActor ([EarnedFieldTripPatch]) -> Void
        let loadingDidChange: @MainActor (Bool) -> Void
    }

    var items: [ActiveFieldTripProfileItem] = []
    // Start rendered so SwiftUI mounts the task that performs the first load.
    var isLoading = true
    var hasLoaded = false

    private let dependencies: Dependencies
    private var isLoadInFlight = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func load(isAuthenticated: Bool) async {
        guard isAuthenticated else {
            items = []
            dependencies.earnedPatchesDidChange([])
            dependencies.loadingDidChange(false)
            hasLoaded = true
            isLoading = false
            return
        }
        guard !isLoadInFlight else { return }

        isLoadInFlight = true
        isLoading = true
        dependencies.loadingDidChange(true)
        defer {
            isLoadInFlight = false
            isLoading = false
            hasLoaded = true
            dependencies.loadingDidChange(false)
        }

        do {
            let templates = try await dependencies.loadTemplates(80)
            let loadedItems = ActiveFieldTripProfilePresentation.items(
                templates: templates
            )
            let loadedPatches = EarnedFieldTripPatchPresentation.items(
                templates: templates
            )
            guard !Task.isCancelled else { return }
            items = loadedItems
            dependencies.earnedPatchesDidChange(loadedPatches)
            MerianLog.network.debug(
                "Loaded \(loadedItems.count, privacy: .public) active Profile Field trips and \(loadedPatches.count, privacy: .public) earned patches."
            )
        } catch {
            MerianLog.network.warning(
                "Failed to load active Profile Field trips: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}
