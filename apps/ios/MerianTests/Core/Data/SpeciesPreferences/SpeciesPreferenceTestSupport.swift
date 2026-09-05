import Foundation
@testable import Merian
import SwiftData

let speciesPreferenceTestUserID = UUID(
    uuidString: "11111111-1111-1111-1111-111111111111"
)!

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
    ownerUserID: UUID = speciesPreferenceTestUserID,
    modelContext: ModelContext
) throws -> UserSpeciesPreference? {
    let targetID = UserSpeciesPreference.identifier(
        ownerUserID: ownerUserID,
        scientificName: scientificName
    )
    var descriptor = FetchDescriptor<UserSpeciesPreference>(
        predicate: #Predicate { $0.id == targetID }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
}

extension UserSpeciesPreference {
    convenience init(
        testOwnerUserID: UUID = speciesPreferenceTestUserID,
        scientificName: String,
        preferredCommonName: String,
        updatedAt: Date = Date()
    ) {
        self.init(
            ownerUserID: testOwnerUserID,
            scientificName: scientificName,
            preferredCommonName: preferredCommonName,
            updatedAt: updatedAt
        )
    }
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
    userID: UUID = speciesPreferenceTestUserID
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
