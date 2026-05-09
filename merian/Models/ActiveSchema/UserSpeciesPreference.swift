import Foundation
import SwiftData

/// Persists the user's preferred display name for a species, keyed by scientific name.
/// Current production reads/writes flow through `SpeciesPreferredNameRepository`, which uses
/// SwiftData as the source of truth and mirrors the legacy per-species UserDefaults keys for
/// no-context Explore display paths. This entity is also the local backing store for eventual
/// cloud sync to `user_species_preferences` in Supabase.
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
