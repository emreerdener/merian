import Foundation

/// The original AI answer, independent of dictionary enrichment and user review.
/// Present invalid bytes stay present so damaged storage can never become legacy.
struct PrimaryIdentification: Equatable, Sendable {
    enum Resolution: String, Codable, CaseIterable, Sendable {
        case species, genus, family
        case unresolvedBiological = "unresolved_biological"
        case nonBiological = "non_biological"

        var isNamedBiologicalTaxon: Bool {
            self == .species || self == .genus || self == .family
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let version: Int
        let resolution: Resolution
        let scientificName: String?
        let commonName: String?

        init(resolution: Resolution, scientificName: String?, commonName: String?) throws {
            self.version = 1
            self.resolution = resolution
            self.scientificName = scientificName
            self.commonName = commonName
            try validate()
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: FieldKey.self)
            let allowed: Set<String> = ["version", "resolution", "scientific_name", "common_name"]
            guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
                throw IntegrityError.invalidSnapshot
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            resolution = try values.decode(Resolution.self, forKey: .resolution)
            // Required nullable fields; omission is a damaged snapshot.
            scientificName = try values.decode(String?.self, forKey: .scientificName)
            commonName = try values.decode(String?.self, forKey: .commonName)
            try validate()
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(version, forKey: .version)
            try values.encode(resolution, forKey: .resolution)
            try values.encode(scientificName, forKey: .scientificName)
            try values.encode(commonName, forKey: .commonName)
        }

        private func validate() throws {
            guard version == 1,
                  Self.validName(scientificName), Self.validName(commonName),
                  !resolution.isNamedBiologicalTaxon || scientificName != nil,
                  resolution != .unresolvedBiological || scientificName == nil else {
                throw IntegrityError.invalidSnapshot
            }
        }

        private static func validName(_ name: String?) -> Bool {
            guard let name else { return true }
            return (1...255).contains(name.utf16.count) &&
                name == name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))) &&
                !name.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        }
    }

    enum IntegrityError: Error, Equatable {
        case invalidSnapshot
        case conflictingSnapshot
        case missingRequiredSnapshot
    }

    let data: Data
    let value: Snapshot?

    init(storedData: Data, matchesProvenance: Bool = true) {
        data = storedData
        value = matchesProvenance && storedData.count <= 4_096
            ? try? JSONDecoder().decode(Snapshot.self, from: storedData)
            : nil
    }

    init(snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= 4_096 else { throw IntegrityError.invalidSnapshot }
        self.data = data
        self.value = snapshot
    }

    /// Restore the pair without turning missing, malformed, or unpaired new
    /// metadata into a legacy identification.
    static func restoring(stored: Data?, provenance: IdentificationResultProvenance?) -> Self? {
        let required = provenance?.requiresPrimaryIdentification == true
        guard stored != nil || required else { return nil }
        return Self(storedData: stored ?? Data(), matchesProvenance: required)
    }

    /// Omitted legacy history cannot erase an explicit completed answer. A
    /// competing answer for the same scan is an integrity failure, not an update.
    static func merging(stored: Data?, incoming: PrimaryIdentification?) throws -> Data? {
        let current = stored.map { PrimaryIdentification(storedData: $0) }
        if let current, current.value == nil { throw IntegrityError.invalidSnapshot }
        if let incoming, incoming.value == nil { throw IntegrityError.invalidSnapshot }
        if let current, let incoming, current.value != incoming.value {
            throw IntegrityError.conflictingSnapshot
        }
        return stored ?? incoming?.data
    }

    private struct FieldKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

extension PrimaryIdentification.Snapshot {
    private enum CodingKeys: String, CodingKey {
        case version, resolution
        case scientificName = "scientific_name"
        case commonName = "common_name"
    }
}
