import SwiftUI

struct SpeciesDictionaryOverviewRow: View {
    let category: SpeciesDictionaryCategorySummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: SpeciesDictionaryCatalogStyle
                        .thumbnailCornerRadius,
                    style: .continuous
                )
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }

    private var countLabel: String {
        switch category.id {
        case .recentlyAdded:
            "Newest \(category.count.formatted()) species"
        default:
            "\(category.count.formatted()) species"
        }
    }

    private var iconName: String {
        switch category.id {
        case .all: "book"
        case .taxonomy: "point.3.connected.trianglepath.dotted"
        case .yourRegion: "location"
        case .recentlyAdded: "sparkles"
        }
    }
}
