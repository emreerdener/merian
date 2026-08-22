import SwiftUI

struct ExplorePostDetailInsightSection: View {
    let post: ExplorePost
    let scientificName: String
    let displayCommonName: String
    let alternativeCommonNames: [String]
    let detail: ExplorePostDetail?
    let isLoading: Bool
    let errorMessage: String?
    let onOpenExploreMap: ((ExploreMapFocusTarget) -> Void)?

    private var shouldShowSection: Bool {
        isLoading
            || detail != nil
            || errorMessage != nil
    }

    private var speciesDictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: detail?.speciesDictionaryId,
            entryPoint: .exploreDetailDictionary
        )
    }

    private var shouldShowOverviewCard: Bool {
        ExploreOverviewCard.hasVisibleContent(
            iucnRedListStatus: detail?.iucnRedListStatus,
            wikipediaOverview: detail?.wikipediaOverview
        )
    }

    private var referenceGalleryImages: [ExploreReferenceGalleryImage] {
        let mediaIdentifiers = [post.heroImageUrl] + post.resolvedMediaItems.flatMap { item in
            [item.url, item.thumbnailUrl].compactMap { $0 }
        }
        return detail?.referenceGalleryImages(excluding: mediaIdentifiers) ?? []
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
            if !referenceGalleryImages.isEmpty {
                ExploreReferenceGallery(
                    scientificName: scientificName,
                    images: referenceGalleryImages
                )
            }

            if shouldShowOverviewCard {
                ExploreOverviewCard(
                    scientificName: scientificName,
                    iucnRedListStatus: detail?.iucnRedListStatus,
                    wikipediaOverview: detail?.wikipediaOverview,
                    action: .speciesDictionary(speciesDictionaryRoute)
                )
            } else {
                ExploreSpeciesDictionaryLink(
                    scientificName: scientificName,
                    speciesId: detail?.speciesDictionaryId
                )
            }

            ExploreObservationContextCard(
                post: post,
                detail: detail,
                onOpenExploreMap: onOpenExploreMap
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
