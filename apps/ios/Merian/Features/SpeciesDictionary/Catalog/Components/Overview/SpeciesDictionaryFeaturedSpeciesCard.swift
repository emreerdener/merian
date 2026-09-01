import SwiftUI

struct SpeciesDictionaryFeaturedSpeciesCard: View {
    let species: SpeciesDictionaryFeaturedSpecies
    let width: CGFloat

    private var imageHeight: CGFloat {
        max(300, min(430, width * 0.96))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpeciesDictionaryCatalogRemoteImage(
                source: species.referenceImageUrl,
                prominentPlaceholder: true
            )
            .frame(width: width, height: imageHeight)
            .clipped()

            bottomTextFade
            badge
            titleOverlay
        }
        .frame(width: width)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .contentShape(cardShape)
        .accessibilityElement(children: .combine)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
            style: .continuous
        )
    }

    private var badge: some View {
        Text("Recently added")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.42), in: Capsule(style: .continuous))
            .padding(14)
    }

    private var bottomTextFade: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.24),
                .black.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(species.commonName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 2)

            Text(species.scientificName)
                .font(.subheadline.italic())
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 2)
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottomLeading
        )
    }
}
