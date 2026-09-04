import Foundation
@testable import Merian
import SwiftData

@MainActor
func makeSpeciesPreferenceContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: UserSpeciesPreference.self,
        configurations: configuration
    )
    return ModelContext(container)
}

@MainActor
func fetchSpeciesPreference(
    for scientificName: String,
    modelContext: ModelContext
) throws -> UserSpeciesPreference? {
    let targetScientificName = scientificName
    var descriptor = FetchDescriptor<UserSpeciesPreference>(
        predicate: #Predicate<UserSpeciesPreference> {
            $0.scientificName == targetScientificName
        }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
}

func makeSpeciesPreferenceDefaults(
    named name: String = UUID().uuidString
) -> (UserDefaults, String) {
    let suiteName = "merian.tests.species-preferences.\(name)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

func makeSpeciesPreferenceLease(
    userID: UUID = UUID()
) -> AccountBoundWorkLease {
    AccountBoundWorkLease(
        id: UUID(),
        session: AuthTransitionSession(
            userID: userID,
            isAnonymous: false
        )
    )
}

func makeSpeciesPreferenceCloudRow(
    scientificName: String,
    preferredName: String?,
    updatedAt: String,
    deletedAt: String? = nil
) -> SpeciesPreferenceCloudRow {
    SpeciesPreferenceCloudRow(
        scientific_name: scientificName,
        preferred_common_name: preferredName,
        updated_at: updatedAt,
        deleted_at: deletedAt
    )
}
