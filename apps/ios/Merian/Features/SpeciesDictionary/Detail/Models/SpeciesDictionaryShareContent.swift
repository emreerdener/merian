import Foundation

enum SpeciesDictionaryShareContent {
    private static let slugMaximumLength = 80

    static func url(
        speciesId: String,
        commonName: String,
        scientificName: String
    ) -> URL? {
        guard let uuid = UUID(
            uuidString: speciesId.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) else {
            return nil
        }
        let slug = slug(
            commonName: commonName,
            scientificName: scientificName
        )
        return PublicBrand.websiteURL(
            path: "species/\(uuid.uuidString.lowercased())/\(slug)"
        )
    }

    static func slug(commonName: String, scientificName: String) -> String {
        for candidate in [commonName, scientificName] {
            if let slug = slugCandidate(candidate) {
                return slug
            }
        }
        return "species"
    }

    static func message(commonName: String) -> String {
        let name = commonName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let displayName = name.isEmpty ? "this species" : name
        return "Learn about \(displayName) on Naturebook."
    }

    private static func slugCandidate(_ value: String) -> String? {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .decomposedStringWithCompatibilityMapping
            .lowercased()

        var result = ""
        var needsSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.nonBaseCharacters.contains(scalar) {
                continue
            }

            let value = scalar.value
            let isASCIILetter = (97...122).contains(value)
            let isASCIIDigit = (48...57).contains(value)
            guard isASCIILetter || isASCIIDigit else {
                needsSeparator = !result.isEmpty
                continue
            }

            let requiredCharacters = needsSeparator && !result.isEmpty ? 2 : 1
            guard result.count + requiredCharacters <= slugMaximumLength else {
                break
            }
            if needsSeparator && !result.isEmpty {
                result.append("-")
            }
            result.unicodeScalars.append(scalar)
            needsSeparator = false
        }

        return result.isEmpty ? nil : result
    }
}
