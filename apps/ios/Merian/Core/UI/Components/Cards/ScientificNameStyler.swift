import SwiftUI

enum ScientificNameStyler {
    static func highlightedText(_ text: String, scientificName: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let scientificName, !scientificName.isEmpty else { return result }

        var searchRange = result.startIndex..<result.endIndex
        while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.secondary.opacity(0.15)
            searchRange = range.upperBound..<result.endIndex
        }

        return result
    }
}
