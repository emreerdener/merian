import SwiftData

@MainActor
struct InsightContentDependencies {
    let loadPreferredCommonName: @MainActor (
        _ scientificName: String,
        _ modelContext: ModelContext
    ) -> String?
    let setPreferredCommonName: @MainActor (
        _ name: String,
        _ scientificName: String,
        _ modelContext: ModelContext
    ) -> Bool
    let clearPreferredCommonName: @MainActor (
        _ scientificName: String,
        _ modelContext: ModelContext
    ) -> Bool
    let factManager: @MainActor () -> FactManager
    let headerRevealFeedback: @MainActor () -> Void
    let fieldTripOpenFeedback: @MainActor () -> Void

    init(
        loadPreferredCommonName: @escaping @MainActor (
            _ scientificName: String,
            _ modelContext: ModelContext
        ) -> String? = { _, _ in nil },
        setPreferredCommonName: @escaping @MainActor (
            _ name: String,
            _ scientificName: String,
            _ modelContext: ModelContext
        ) -> Bool = { _, _, _ in false },
        clearPreferredCommonName: @escaping @MainActor (
            _ scientificName: String,
            _ modelContext: ModelContext
        ) -> Bool = { _, _ in false },
        factManager: @escaping @MainActor () -> FactManager = {
            FactManager.shared
        },
        headerRevealFeedback: @escaping @MainActor () -> Void = {},
        fieldTripOpenFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.loadPreferredCommonName = loadPreferredCommonName
        self.setPreferredCommonName = setPreferredCommonName
        self.clearPreferredCommonName = clearPreferredCommonName
        self.factManager = factManager
        self.headerRevealFeedback = headerRevealFeedback
        self.fieldTripOpenFeedback = fieldTripOpenFeedback
    }

    static var live: Self {
        let hapticManager = AppDIContainer.shared.hapticManager
        let supabaseManager = SupabaseManager.shared
        return Self(
            loadPreferredCommonName: { scientificName, modelContext in
                guard let ownerUserID = supabaseManager.currentUser?.id else {
                    return nil
                }
                return SpeciesPreferredNameRepository.preferredName(
                    for: scientificName,
                    ownerUserID: ownerUserID,
                    modelContext: modelContext
                )
            },
            setPreferredCommonName: { name, scientificName, modelContext in
                guard let ownerUserID = supabaseManager.currentUser?.id else {
                    return false
                }
                return SpeciesPreferredNameRepository.setPreferredName(
                    name,
                    for: scientificName,
                    ownerUserID: ownerUserID,
                    modelContext: modelContext
                )
            },
            clearPreferredCommonName: { scientificName, modelContext in
                guard let ownerUserID = supabaseManager.currentUser?.id else {
                    return false
                }
                return SpeciesPreferredNameRepository.clearPreferredName(
                    for: scientificName,
                    ownerUserID: ownerUserID,
                    modelContext: modelContext
                )
            },
            factManager: { FactManager.shared },
            headerRevealFeedback: {
                hapticManager.triggerLightImpact(intensity: 0.5)
            },
            fieldTripOpenFeedback: {
                hapticManager.triggerSelectionPulse(
                    source: "insight.fieldTripProgress.open"
                )
            }
        )
    }
}
