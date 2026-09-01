import SwiftUI

struct SpeciesDictionaryCatalogRow: View {
    let item: SpeciesDictionaryCatalogItem

    private let thumbnailSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            SpeciesDictionaryCatalogRemoteImage(source: item.referenceImageUrl)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: SpeciesDictionaryCatalogStyle
                            .thumbnailCornerRadius,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.commonName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let taxonomySummary {
                    Text(taxonomySummary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var taxonomySummary: String? {
        [
            item.taxonomy?.kingdom,
            item.taxonomy?.className,
            item.taxonomy?.family
        ]
        .compactMap { $0?.trimmedNonEmptyValue }
        .joined(separator: " - ")
        .trimmedNonEmptyValue
    }
}
