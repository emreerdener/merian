import Foundation

enum ExploreLocationPrivacy {
    private static let stateCodeToName: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
        "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
        "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]

    private static let stateNameToCode = Dictionary(
        uniqueKeysWithValues: stateCodeToName.map { ($0.value.lowercased(), $0.key) }
    )

    private static let countryNames: Set<String> = [
        "united states", "united states of america", "usa", "us", "canada"
    ]

    static func displayLabel(from rawLocation: String?) -> String? {
        guard let rawLocation else { return nil }
        let cleaned = rawLocation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !cleaned.isEmpty, !containsCoordinatePair(cleaned) else { return nil }

        var parts = cleaned
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        parts.removeAll(where: isCountry)

        guard !parts.isEmpty else { return nil }

        if let stateIndex = parts.lastIndex(where: { normalizedState(from: $0) != nil }),
           let state = normalizedState(from: parts[stateIndex]) {
            if let city = parts[..<stateIndex].reversed().first(where: isSafeCityPart) {
                return "\(city), \(state.code)"
            }

            return state.name
        }

        guard let lastPart = parts.last, !isPrivateLocationPart(lastPart) else { return nil }

        if parts.count >= 2 {
            let region = lastPart
            if let city = parts.dropLast().reversed().first(where: isSafeCityPart) {
                return "\(city), \(region)"
            }

            return nil
        }

        return isSafeCityPart(lastPart) ? lastPart : nil
    }

    private static func containsCoordinatePair(_ value: String) -> Bool {
        let commaSeparated = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if commaSeparated.count == 2,
           let latitude = Double(commaSeparated[0]),
           let longitude = Double(commaSeparated[1]),
           abs(latitude) <= 90,
           abs(longitude) <= 180 {
            return true
        }

        let pattern = #"[-+]?\d{1,3}\.\d{3,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        let numbers = matches.compactMap { match -> Double? in
            guard let numberRange = Range(match.range, in: value) else { return nil }
            return Double(value[numberRange])
        }

        guard numbers.count >= 2 else { return false }

        for index in numbers.indices.dropLast() {
            let latitude = numbers[index]
            let longitude = numbers[index + 1]
            if abs(latitude) <= 90, abs(longitude) <= 180 {
                return true
            }
        }

        return false
    }

    private static func isPrivateLocationPart(_ part: String) -> Bool {
        let lowercased = part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !lowercased.isEmpty else { return true }
        if isCountry(lowercased) || containsCoordinatePair(lowercased) { return true }

        let privatePatterns = [
            #"^\d+"#,
            #"(street|avenue|road|boulevard|drive|lane|court|terrace|highway|route|suite|unit|apartment)"#,
            #"\b(st|ave|rd|blvd|dr|ln|ct|pl)\.?$"#,
            #"(gps|latitude|longitude|coordinate)"#,
            #"\b(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground|bay|harbor|harbour|marina|island|lake|pond|river|canal|inlet|lagoon|wetland|swamp|sound|cove|estuary)\.?$"#
        ]

        return privatePatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func isSafeCityPart(_ part: String) -> Bool {
        guard !isPrivateLocationPart(part) else { return false }

        let lowercased = part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let administrativePatterns = [
            #"\b(county|parish|borough|district|municipality|prefecture)\b"#,
            #"\b(province|region)\b$"#
        ]

        return administrativePatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        } == false
    }

    private static func isCountry(_ value: String) -> Bool {
        countryNames.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func normalizedState(from value: String) -> (code: String, name: String)? {
        let trimmed = removingTrailingCountry(from: value)
        let uppercased = trimmed.uppercased()
        if let zipRange = trimmed.range(of: #"\s+\d{5}(?:-\d{4})?$"#, options: .regularExpression) {
            let stateCandidate = String(trimmed[..<zipRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stateCodeCandidate = stateCandidate.uppercased()
            if let stateName = stateCodeToName[stateCodeCandidate] {
                return (code: stateCodeCandidate, name: stateName)
            }
            if let stateCode = stateNameToCode[stateCandidate.lowercased()],
               let stateName = stateCodeToName[stateCode] {
                return (code: stateCode, name: stateName)
            }
        }

        if let stateName = stateCodeToName[uppercased] {
            return (code: uppercased, name: stateName)
        }

        if let stateCode = stateNameToCode[trimmed.lowercased()],
           let stateName = stateCodeToName[stateCode] {
            return (code: stateCode, name: stateName)
        }

        return nil
    }

    private static func removingTrailingCountry(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        for country in countryNames.sorted(by: { $0.count > $1.count }) {
            if lowercased == country {
                return ""
            }

            let suffix = " \(country)"
            if lowercased.hasSuffix(suffix) {
                return String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }
}
