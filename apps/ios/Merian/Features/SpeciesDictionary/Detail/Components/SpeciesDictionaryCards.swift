import SwiftUI

struct SpeciesDictionaryContentQualityCard: View {
    let quality: SpeciesDictionaryContentQuality

    var body: some View {
        if quality != .complete {
            VStack(alignment: .leading, spacing: 12) {
                MerianCardHeader(systemImage: iconName, title: title)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    private var iconName: String {
        switch quality {
        case .complete:
            return "checkmark.circle"
        case .sparse:
            return "info.circle"
        case .needsEnrichment:
            return "hourglass"
        }
    }

    private var title: String {
        switch quality {
        case .complete:
            return "Complete entry"
        case .sparse:
            return "Limited details"
        case .needsEnrichment:
            return "Early dictionary entry"
        }
    }

    private var message: String {
        switch quality {
        case .complete:
            return ""
        case .sparse:
            return "Some public reference details are still limited for this species."
        case .needsEnrichment:
            return "Only basic identity is available right now."
        }
    }
}

struct SpeciesDictionaryStatusCard: View {
    let hazardType: String?

    private var normalizedHazard: String? {
        guard let hazardType else { return nil }
        let normalized = hazardType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        guard !normalized.isEmpty, normalized != "none" else { return nil }
        return String(normalized.prefix(1)).uppercased() + String(normalized.dropFirst())
    }

    var body: some View {
        if let normalizedHazard {
            VStack(alignment: .leading, spacing: 14) {
                MerianCardHeader(systemImage: "exclamationmark.triangle", title: "Caution")

                KeyValueRow(
                    title: "HAZARD",
                    value: normalizedHazard,
                    valueIcon: "exclamationmark.shield.fill",
                    valueIconColor: .red,
                    valueTextColor: .red,
                    valueFontWeight: .semibold
                )
            }
            .card()
        }
    }
}

struct AlternativeCommonNamesLine: View {
    let names: [String]
    let primaryCommonName: String

    private var displayNames: [String] {
        Self.displayNames(from: names, excluding: primaryCommonName)
    }

    var body: some View {
        if !displayNames.isEmpty {
            Text("Also known as: \(displayNames.joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    static func displayNames(from names: [String], excluding primaryCommonName: String) -> [String] {
        var seenKeys = Set<String>()
        let primaryKey = primaryCommonName.alternativeCommonNameKey
        if !primaryKey.isEmpty {
            seenKeys.insert(primaryKey)
        }

        return names
            .flatMap { $0.components(separatedBy: ",") }
            .compactMap { rawName in
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                guard seenKeys.insert(name.alternativeCommonNameKey).inserted else { return nil }
                return name
            }
    }
}

private extension String {
    var alternativeCommonNameKey: String {
        let separatorCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-‐‑‒–—―−_"))
        let folded = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedSeparators = folded.unicodeScalars.map { scalar in
            separatorCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()

        return normalizedSeparators
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
