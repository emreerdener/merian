import Foundation

enum SpeciesDictionaryIdentity {
    static let maximumScientificNameLength = 160

    static func canonicalSpeciesID(_ value: String?) -> String? {
        guard let value = value?.trimmedNonEmptyValue,
              let uuid = UUID(uuidString: value) else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    static func normalizedScientificName(_ value: String?) -> String? {
        guard let normalized = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter({ !$0.isEmpty })
            .joined(separator: " ")
            .trimmedNonEmptyValue,
            normalized.count <= maximumScientificNameLength else {
            return nil
        }
        return normalized
    }

    static func scientificNameCacheKey(_ value: String?) -> String? {
        normalizedScientificName(value)?.lowercased()
    }
}
