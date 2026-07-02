import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    // MARK: - Name Preference

    /// Loads the user's preferred common name for the given scientific name.
    /// Call this whenever a new species is presented so `resolvedHeaderTitle` reflects the preference.
    func loadPreferredCommonName(for scientificName: String, modelContext: ModelContext) {
        state.preferredCommonName = SpeciesPreferredNameRepository.preferredName(
            for: scientificName,
            modelContext: modelContext
        )
    }

    /// Persists the user's preferred common name and updates the in-memory state immediately
    /// so `resolvedHeaderTitle` recomputes without requiring a re-fetch.
    func setPreferredCommonName(_ name: String, for scientificName: String, modelContext: ModelContext) {
        let didSave = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            modelContext: modelContext
        )
        guard didSave else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Could not save preferred name"
            }
            HapticManager.shared.triggerErrorThump()
            return
        }

        state.preferredCommonName = SpeciesPreferredNameRepository.preferredName(
            for: scientificName,
            modelContext: modelContext
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = "Preferred name set to \"\(name)\""
        }
        HapticManager.shared.triggerSelectionPulse()
    }

    /// Removes the stored preference, reverting the headline to the canonical DB common name.
    func clearPreferredCommonName(for scientificName: String, modelContext: ModelContext) {
        let didClear = SpeciesPreferredNameRepository.clearPreferredName(
            for: scientificName,
            modelContext: modelContext
        )
        guard didClear else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Could not clear preferred name"
            }
            HapticManager.shared.triggerErrorThump()
            return
        }

        state.preferredCommonName = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = "Reverted to default name"
        }
        HapticManager.shared.triggerSelectionPulse()
    }
}
