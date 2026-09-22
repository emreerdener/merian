import SwiftUI

struct SpeciesSearchResults: View {
    @Bindable var model: SpeciesSearchViewModel
    let exploreViewModel: ExploreFeedViewModel
    var imageDependencies: SpeciesCatalogImageDependencies = .live
    var sightingImageDependencies: ExploreHeroImageDependencies = .live
    let onOpenPost: (ExplorePost) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleSightings: [ExplorePost] {
        model.sightings.compactMap { exploreViewModel.post(id: $0.id) }
            .filter { SpeciesSearchSightings.canSurface($0, in: exploreViewModel) }
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 32)
            let speciesWidth = dynamicTypeSize.isAccessibilitySize ? availableWidth : min(200, availableWidth)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    speciesSection(cardWidth: speciesWidth)
                        .id("species")
                    sightingsSection(singleWidth: speciesWidth)
                        .id("sightings")
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .scrollPosition(id: $model.resultsScrollID)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func speciesSection(cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MerianCardHeader(systemImage: "camera.filters", title: "Species")
            if !model.species.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(model.species) { match in
                            NavigationLink(value: SpeciesDictionaryRoute(
                                scientificName: match.item.scientificName, speciesId: match.id, entryPoint: .search
                            )) {
                                speciesCard(match, width: cardWidth)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if model.hasLoaded(.species) {
                emptyResults("No matching species", message: "Try a name or fewer descriptive traits. Naturebook may not have an entry yet.")
            }
            moreButton(.species, title: "More species")
        }
    }

    private func speciesCard(_ match: SpeciesSearchMatch, width: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.item.commonName)
                    .font(.subheadline.weight(.semibold))
                Text(match.item.scientificName)
                    .font(.caption).italic().foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(10)
        }
        .frame(width: width)
        .frame(minHeight: width * 1.3)
        .background {
            SpeciesDictionaryCatalogRemoteImage(source: match.item.referenceImageUrl,
                                                prominentPlaceholder: true, dependencies: imageDependencies)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityValue(match.excerpt.isEmpty ? "" : "From the dictionary: \(match.excerpt)")
    }

    private func sightingsSection(singleWidth: CGFloat) -> some View {
        let posts = visibleSightings
        return VStack(alignment: .leading, spacing: 14) {
            MerianCardHeader(systemImage: "person.3", title: "Community sightings")
            if posts.count == 1, let post = posts.first {
                sighting(post)
                    .frame(width: singleWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if !posts.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 2) {
                    ForEach(posts) { post in sighting(post) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if model.hasLoaded(.sightings) {
                emptyResults("No matching public sightings", message: "There may still be matching species above. Try broader search criteria.")
            } else if model.isLoading {
                ProgressView("Loading community sightings…")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            moreButton(.sightings, title: "More sightings")
        }
    }

    private func sighting(_ post: ExplorePost) -> some View {
        SpeciesSearchSightingCard(post: post, mediaReloadGeneration: exploreViewModel.mediaReloadGeneration,
                                 imageDependencies: sightingImageDependencies) {
            onOpenPost(post)
        }
    }

    private func emptyResults(_ title: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(message))
    }

    @ViewBuilder private func moreButton(_ kind: SpeciesSearchResultKind, title: String) -> some View {
        if model.hasMore(kind) {
            Button(title) { model.loadMore(kind) }
                .frame(maxWidth: .infinity).padding(12)
        }
    }
}
