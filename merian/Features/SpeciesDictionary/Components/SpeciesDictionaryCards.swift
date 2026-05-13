import SwiftUI

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
                InsightCardHeader(systemImage: "exclamationmark.triangle", title: "Caution")

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

struct SpeciesDictionaryNamesCard: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                InsightCardHeader(systemImage: "textformat", title: "Also known as")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
                    }
                }
            }
            .card()
        }
    }
}

struct SpeciesDictionaryTagsCard: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                InsightCardHeader(systemImage: "tag", title: "Groups")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag.capitalized)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: Capsule(style: .continuous))
                    }
                }
            }
            .card()
        }
    }
}
