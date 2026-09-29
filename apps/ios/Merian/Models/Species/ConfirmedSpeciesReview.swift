import Foundation

/// Server-owned review authority. The AI answer and its confidence are separate.
/// Legacy review flags describe local intent; they never manufacture this value.
struct ConfirmedSpeciesReview: Codable, Equatable, Sendable {
    struct Identity: Codable, Equatable, Sendable {
        let version: Int
        let speciesID: String
        let scientificName: String
        let commonName: String?
        let gbifTaxonKey: Int

        private enum CodingKeys: String, CodingKey {
            case version
            case speciesID = "species_id"
            case scientificName = "scientific_name"
            case commonName = "common_name"
            case gbifTaxonKey = "gbif_taxon_key"
        }

        init(from decoder: Decoder) throws {
            try ReviewFieldKey.requireExact(decoder, keys: [
                "version", "species_id", "scientific_name", "common_name", "gbif_taxon_key"
            ])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            speciesID = try values.decode(String.self, forKey: .speciesID)
            scientificName = try values.decode(String.self, forKey: .scientificName)
            commonName = try values.decode(String?.self, forKey: .commonName)
            gbifTaxonKey = try values.decode(Int.self, forKey: .gbifTaxonKey)
            guard version == 1, Self.isCanonicalID(speciesID),
                  Self.validScientificName(scientificName), commonName == nil,
                  (1...2_147_483_647).contains(gbifTaxonKey) else {
                throw IntegrityError.invalidEnvelope
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(version, forKey: .version)
            try values.encode(speciesID, forKey: .speciesID)
            try values.encode(scientificName, forKey: .scientificName)
            try values.encode(commonName, forKey: .commonName)
            try values.encode(gbifTaxonKey, forKey: .gbifTaxonKey)
        }

        static func isCanonicalID(_ value: String) -> Bool {
            value.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                        options: .regularExpression) != nil
        }

        static func validScientificName(_ value: String) -> Bool {
            (1...160).contains(value.utf16.count) &&
                value == value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))) &&
                !ConfirmedSpeciesReview.hasControls(value)
        }
    }

    enum IntegrityError: Error, Equatable {
        case invalidEnvelope, conflictingRevision, invalidRequest, missingRecord
    }

    let version: Int
    let revision: Int
    let identity: Identity?
    let userIdentificationOverride: String?
    let userConfirmedIdentification: Bool
    let confirmedSpeciesID: String?
    let userReviewState: UserReviewState

    private enum CodingKeys: String, CodingKey {
        case version, revision, identity
        case userIdentificationOverride = "user_identification_override"
        case userConfirmedIdentification = "user_confirmed_identification"
        case confirmedSpeciesID = "confirmed_species_id"
        case userReviewState = "user_review_state"
    }

    init(from decoder: Decoder) throws {
        try ReviewFieldKey.requireExact(decoder, keys: [
            "version", "revision", "identity", "user_identification_override",
            "user_confirmed_identification", "confirmed_species_id", "user_review_state"
        ])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        revision = try values.decode(Int.self, forKey: .revision)
        identity = try values.decode(Identity?.self, forKey: .identity)
        userIdentificationOverride = try values.decode(String?.self, forKey: .userIdentificationOverride)
        userConfirmedIdentification = try values.decode(Bool.self, forKey: .userConfirmedIdentification)
        confirmedSpeciesID = try values.decode(String?.self, forKey: .confirmedSpeciesID)
        userReviewState = try values.decode(UserReviewState.self, forKey: .userReviewState)
        try validate()
    }

    /// Owner-history columns are an alternate projection of the same envelope.
    init(revision: Int, identity: Identity?, override: String?, confirmed: Bool,
         speciesID: String?, state: UserReviewState) throws {
        version = 1
        self.revision = revision
        self.identity = identity
        userIdentificationOverride = override
        userConfirmedIdentification = confirmed
        confirmedSpeciesID = speciesID
        userReviewState = state
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(revision, forKey: .revision)
        try values.encode(identity, forKey: .identity)
        try values.encode(userIdentificationOverride, forKey: .userIdentificationOverride)
        try values.encode(userConfirmedIdentification, forKey: .userConfirmedIdentification)
        try values.encode(confirmedSpeciesID, forKey: .confirmedSpeciesID)
        try values.encode(userReviewState, forKey: .userReviewState)
    }

    func storedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 8_192 else { throw IntegrityError.invalidEnvelope }
        return data
    }

    static func restoring(_ data: Data?) throws -> Self? {
        guard let data else { return nil }
        guard data.count <= 8_192 else { throw IntegrityError.invalidEnvelope }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    /// Omission preserves authority, clear is a revisioned envelope, and an
    /// equal revision with different content is corruption rather than an edit.
    static func merging(stored: Self?, incoming: Self?) throws -> Self? {
        guard let incoming else { return stored }
        guard let stored else { return incoming }
        if incoming.revision < stored.revision { return stored }
        if incoming.revision == stored.revision && incoming != stored {
            throw IntegrityError.conflictingRevision
        }
        return incoming
    }

    func matchesIntent(override: String?, confirmed: Bool, state: UserReviewState) -> Bool {
        userIdentificationOverride == override && userConfirmedIdentification == confirmed && userReviewState == state
    }

    private func validate() throws {
        guard version == 1, (0...2_147_483_647).contains(revision),
              confirmedSpeciesID == identity?.speciesID,
              userConfirmedIdentification == (userReviewState == .aiConfirmed),
              identity == nil || (revision > 0 && userReviewState != .unreviewed) else {
            throw IntegrityError.invalidEnvelope
        }
        if userReviewState == .userOverridden {
            guard let name = userIdentificationOverride, name.utf8.count <= 1_024,
                  !name.trimmingCharacters(in: CharacterSet(charactersIn: " ")).isEmpty,
                  !Self.hasControls(name) else { throw IntegrityError.invalidEnvelope }
        } else if userIdentificationOverride != nil {
            throw IntegrityError.invalidEnvelope
        }
    }

    private static func hasControls(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

struct ReviewFieldKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }

    static func requireExact(_ decoder: Decoder, keys: Set<String>) throws {
        let raw = try decoder.container(keyedBy: Self.self)
        guard Set(raw.allKeys.map(\.stringValue)) == keys else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
    }
}
