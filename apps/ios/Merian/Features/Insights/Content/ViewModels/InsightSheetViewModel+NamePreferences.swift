import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    // MARK: - Name Preference

    /// Loads the user's preferred common name for the given scientific name.
    /// Call this whenever a new species is presented so `resolvedHeaderTitle` reflects the preference.
    func loadPreferredCommonName(for scientificName: String, modelContext: ModelContext) {
        state.preferredCommonName = contentDependencies.loadPreferredCommonName(
            scientificName,
            modelContext
        )
    }

    /// Persists the user's preferred common name and updates the in-memory state immediately
    /// so `resolvedHeaderTitle` recomputes without requiring a re-fetch.
    func setPreferredCommonName(
        _ name: String,
        for scientificName: String,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              inferenceEngine?.speciesData?.scientificName
                .caseInsensitiveCompare(scientificName) == .orderedSame else {
            return
        }
        let didSave = contentDependencies.setPreferredCommonName(
            name,
            scientificName,
            modelContext
        )
        guard didSave else {
            state.toastMessage = .error("Could not save preferred name")
            dependencies.errorFeedback()
            return
        }

        state.preferredCommonName = contentDependencies.loadPreferredCommonName(
            scientificName,
            modelContext
        )
        state.toastMessage = .success("Preferred name set to \"\(name)\"")
        dependencies.selectionFeedback()
    }

    /// Removes the stored preference, reverting the headline to the canonical DB common name.
    func clearPreferredCommonName(
        for scientificName: String,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              inferenceEngine?.speciesData?.scientificName
                .caseInsensitiveCompare(scientificName) == .orderedSame else {
            return
        }
        let didClear = contentDependencies.clearPreferredCommonName(
            scientificName,
            modelContext
        )
        guard didClear else {
            state.toastMessage = .error("Could not clear preferred name")
            dependencies.errorFeedback()
            return
        }

        state.preferredCommonName = nil
        state.toastMessage = .success("Reverted to default name")
        dependencies.selectionFeedback()
    }
}
