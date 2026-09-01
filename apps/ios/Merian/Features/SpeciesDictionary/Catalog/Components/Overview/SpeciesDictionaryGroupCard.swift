import SwiftUI

struct SpeciesDictionaryGroupCard: View {
    let group: SpeciesDictionaryGroupSummary
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            groupGraphic
                .frame(width: graphicSize, height: graphicSize)
                .padding(.top, topInset)

            VStack(spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text("\(group.count.formatted()) species discovered")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity)
            .frame(height: textBandHeight, alignment: .top)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, bottomInset)
        .frame(width: width, height: height)
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

    static func preferredHeight(for width: CGFloat) -> CGFloat {
        topInset
            + min(width * 0.76, 138)
            + 6
            + max(46, width * 0.28)
            + bottomInset
    }

    @ViewBuilder
    private var groupGraphic: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(
            cornerRadius: SpeciesDictionaryCatalogStyle.thumbnailCornerRadius,
            style: .continuous
        )
        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        .overlay {
            Image(systemName: iconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var graphicSize: CGFloat {
        min(width * 0.76, 138)
    }

    private var textBandHeight: CGFloat {
        max(46, width * 0.28)
    }

    private var topInset: CGFloat {
        Self.topInset
    }

    private var bottomInset: CGFloat {
        Self.bottomInset
    }

    private var assetName: String? {
        switch group.id {
        case "plants": "fern"
        case "birds": "eagle"
        case "insects": "butterfly-monarch"
        case "fungi": "mushrooms"
        case "mammals": "squirrel"
        case "reptiles_amphibians": "turtle"
        default: nil
        }
    }

    private var iconName: String {
        switch group.id {
        case "plants": "leaf"
        case "birds": "bird"
        case "insects": "ladybug"
        case "fungi": "circle.hexagongrid"
        case "mammals": "pawprint"
        case "reptiles_amphibians": "lizard"
        default: "square.grid.2x2"
        }
    }

    private static let topInset: CGFloat = 10
    private static let bottomInset: CGFloat = 12
}
