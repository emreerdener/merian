import Foundation
import SwiftData

/// Persists the user's preferred display name for a species, keyed by scientific name.
/// Currently, preferences are read/written via UserDefaults (see InsightSheetViewModel).
/// This entity serves as the SwiftData backing store for eventual cloud sync to
/// `user_species_preferences` in Supabase; migration from UserDefaults is a future task.
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
