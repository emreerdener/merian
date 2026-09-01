import SwiftUI

enum SpeciesDictionaryRegionThumbnail {
    case browseAll
    case country(code: String?)
}

struct SpeciesDictionaryRegionRow: View {
    let title: String
    let count: Int
    let thumbnail: SpeciesDictionaryRegionThumbnail

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(count.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private var thumbnailView: some View {
        RoundedRectangle(
            cornerRadius: SpeciesDictionaryCatalogStyle.thumbnailCornerRadius,
            style: .continuous
        )
        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        .frame(width: 48, height: 48)
        .overlay {
            thumbnailContent
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        switch thumbnail {
        case .browseAll:
            Image(systemName: "globe.americas")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
        case .country(let code):
            if let flag = SpeciesDictionaryRegionFlag.emoji(for: code) {
                Text(flag)
                    .font(.system(size: 27))
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
