import SwiftUI

struct SpeciesDictionaryRegionMapCard: View {
    let category: SpeciesDictionaryCategorySummary
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = SpeciesDictionaryRegionMapViewModel()

    private var imageHeight: CGFloat {
        SpeciesDictionaryCatalogStyle.regionMapImageHeight(for: width)
    }

    private var regionTitle: String {
        category.region?.trimmedNonEmptyValue
            ?? localeRegionTitle
            ?? Self.defaultFallbackRegionTitle
    }

    private var mapQuery: String {
        category.region?.trimmedNonEmptyValue
            ?? localeRegionTitle
            ?? Self.defaultFallbackRegionTitle
    }

    private var localeRegionTitle: String? {
        guard let regionIdentifier = Locale.current.region?.identifier else {
            return nil
        }
        return Locale.current.localizedString(forRegionCode: regionIdentifier)?
            .trimmedNonEmptyValue
    }

    private var snapshotTaskID: String {
        [
            mapQuery,
            "\(Int(width.rounded()))",
            colorScheme == .dark ? "dark" : "light"
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                mapImage

                Text("Your region")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        .black.opacity(0.42),
                        in: Capsule(style: .continuous)
                    )
                    .padding(14)
            }
            .frame(width: width, height: imageHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(regionTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(
                    category.count >= 1
                        ? "\(category.count.formatted()) species recorded"
                        : "Coverage updating"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: width)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(cardShape)
        .contentShape(cardShape)
        .accessibilityElement(children: .combine)
        .task(id: snapshotTaskID) {
            await viewModel.load(
                query: mapQuery,
                width: width,
                height: imageHeight,
                isDark: colorScheme == .dark
            )
        }
    }

    @ViewBuilder
    private var mapImage: some View {
        if let image = viewModel.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                .overlay {
                    if !viewModel.isLoading {
                        Image(systemName: "map")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
            style: .continuous
        )
    }

    private static let defaultFallbackRegionTitle = "United States"
}
