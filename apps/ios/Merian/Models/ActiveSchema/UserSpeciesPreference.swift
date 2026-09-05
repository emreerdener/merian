import Foundation
import SwiftData

/// Persists one account's preferred display name for a species.
///
/// `id` is the account/scientific-name compound identity encoded as a stable
/// string because the deployment target predates SwiftData compound unique
/// constraints. Production access flows through
/// `SpeciesPreferredNameRepository`, which always requires an account id.
/// Added in V34 and account-scoped in V51.
@Model
public final class UserSpeciesPreference {
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var ownerUserId: String = ""
    public var scientificName: String
    public var preferredCommonName: String
    public var updatedAt: Date = Date()

    public init(
        ownerUserID: UUID,
        scientificName: String,
        preferredCommonName: String,
        updatedAt: Date = Date()
    ) {
        id = Self.identifier(
            ownerUserID: ownerUserID,
            scientificName: scientificName
        )
        ownerUserId = ownerUserID.uuidString.lowercased()
        self.scientificName = scientificName
        self.preferredCommonName = preferredCommonName
        self.updatedAt = updatedAt
    }

    public static func identifier(
        ownerUserID: UUID,
        scientificName: String
    ) -> String {
        "\(ownerUserID.uuidString.lowercased())|\(scientificName)"
    }
}
