import Foundation
import SwiftData

/// Persists the user's preferred display name for a species, keyed by scientific name.
/// Current production reads/writes flow through `SpeciesPreferredNameRepository`, which uses
/// SwiftData as the source of truth. Legacy per-species UserDefaults keys are promoted at
/// startup and then removed after a successful SwiftData save. This entity is also the local
/// backing store for eventual cloud sync to `user_species_preferences` in Supabase.
/// Added in V34.
@Model
public final class UserSpeciesPreference {
    @Attribute(.unique) public var scientificName: String
    public var preferredCommonName: String
    public var updatedAt: Date = Date()

    public init(scientificName: String, preferredCommonName: String, updatedAt: Date = Date()) {
        self.scientificName = scientificName
        self.preferredCommonName = preferredCommonName
        self.updatedAt = updatedAt
    }
}
