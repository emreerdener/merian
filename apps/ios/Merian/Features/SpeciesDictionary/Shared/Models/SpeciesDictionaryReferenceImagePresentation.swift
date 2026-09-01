import Foundation

extension SpeciesDictionaryReferenceImage: Identifiable {
    var id: String { url }

    var naturebookAuthorUsername: String? {
        guard source == .merian else { return nil }
        return authorUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .trimmedNonEmptyValue
    }

    var fullscreenAttributionLabel: String {
        if source == .merian {
            return naturebookAuthorUsername
                .map { "@\($0) · \(source.label)" } ?? source.label
        }

        return [
            displayableCredit(attribution),
            displayableCredit(license),
            source.label
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func displayableCredit(_ value: String?) -> String? {
        guard let value = value?.trimmedNonEmptyValue,
              !value.localizedCaseInsensitiveContains(
                  "used with permission"
              ) else {
            return nil
        }
        return value
    }
}

extension SpeciesDictionaryReferenceImage.Source {
    var label: String {
        switch self {
        case .wikipedia:
            "Wikipedia"
        case .gbif:
            "GBIF"
        case .merian:
            "Naturebook"
        case .unknown:
            "Reference"
        }
    }

    var rawValue: String {
        switch self {
        case .wikipedia:
            "wikipedia"
        case .gbif:
            "gbif"
        case .merian:
            "merian"
        case .unknown(let value):
            value
        }
    }
}
