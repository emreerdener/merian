import SwiftUI

struct ExplorePostDetailInsightSection: View {
    let scientificName: String
    let displayCommonName: String
    let alternativeCommonNames: [String]
    let detail: ExplorePostDetail?
    let isLoading: Bool
    let errorMessage: String?

    private var shouldShowSection: Bool {
        isLoading
            || detail != nil
            || errorMessage != nil
    }

    var body: some View {
        if shouldShowSection {
            VStack(alignment: .leading, spacing: 24) {
                cards

                if let errorMessage, detail == nil {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if isLoading && detail == nil {
            ExploreLoadingInsightCard()
        } else {
            if let referenceGalleryImages = detail?.referenceGalleryImages,
               !referenceGalleryImages.isEmpty {
                ExploreReferenceGallery(
                    scientificName: scientificName,
                    images: referenceGalleryImages
                )
            }

            ExploreSpeciesDictionaryLink(
                scientificName: scientificName,
                speciesId: detail?.speciesDictionaryId
            )

            AlternativeCommonNamesLine(
                names: alternativeCommonNames,
                primaryCommonName: displayCommonName
            )
        }
    }
}

struct ExploreSpeciesDictionaryLink: View {
    let scientificName: String
    let speciesId: String?

    private var speciesDictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: speciesId,
            entryPoint: .exploreDetailDictionary
        )
    }

    var body: some View {
        NavigationLink(value: speciesDictionaryRoute) {
            Label("View species dictionary", systemImage: "book")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
