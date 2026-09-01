import SwiftUI

struct SpeciesDictionaryOverviewView: View {
    let userRegion: String?

    @State private var viewModel = SpeciesDictionaryOverviewViewModel()

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.overview == nil {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.overview == nil {
                    errorState(message: errorMessage)
                } else if let overview = viewModel.overview {
                    overviewContent(overview)
                } else {
                    loadingState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: userRegion ?? "") {
            await viewModel.load(userRegion: userRegion)
        }
    }

    private func overviewContent(
        _ overview: SpeciesDictionaryOverview
    ) -> some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let gridSpacing: CGFloat = 12
            let availableWidth = max(
                0,
                geometry.size.width - horizontalPadding * 2
            )
            let cardSize = floor((availableWidth - gridSpacing) / 2)
            let groupCardHeight = SpeciesDictionaryGroupCard.preferredHeight(
                for: cardSize
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let featuredSpecies = overview.featuredSpecies {
                        NavigationLink(value: featuredSpecies.dictionaryRoute) {
                            SpeciesDictionaryFeaturedSpeciesCard(
                                species: featuredSpecies,
                                width: availableWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !overview.groups.isEmpty {
                        groupGrid(
                            overview.groups,
                            cardSize: cardSize,
                            cardHeight: groupCardHeight,
                            spacing: gridSpacing
                        )
                    }

                    regionSection(
                        overview,
                        availableWidth: availableWidth
                    )

                    let bottomCategories = SpeciesDictionaryOverviewPresentation
                        .bottomCategories(in: overview)
                    if !bottomCategories.isEmpty {
                        ForEach(bottomCategories) { category in
                            NavigationLink(
                                value: SpeciesDictionaryOverviewPresentation
                                    .route(for: category)
                            ) {
                                SpeciesDictionaryOverviewRow(category: category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.load(userRegion: userRegion)
            }
        }
    }

    private func groupGrid(
        _ groups: [SpeciesDictionaryGroupSummary],
        cardSize: CGFloat,
        cardHeight: CGFloat,
        spacing: CGFloat
    ) -> some View {
        VStack(spacing: spacing) {
            ForEach(
                SpeciesDictionaryOverviewPresentation.groupRowIndices(
                    for: groups
                ),
                id: \.self
            ) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(0..<2, id: \.self) { columnIndex in
                        let groupIndex = rowIndex * 2 + columnIndex
                        if groups.indices.contains(groupIndex) {
                            let group = groups[groupIndex]
                            NavigationLink(
                                value: SpeciesDictionaryCategoryRoute.group(
                                    title: group.title,
                                    group: group.id
                                )
                            ) {
                                SpeciesDictionaryGroupCard(
                                    group: group,
                                    width: cardSize,
                                    height: cardHeight
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: cardSize, height: cardHeight)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func regionSection(
        _ overview: SpeciesDictionaryOverview,
        availableWidth: CGFloat
    ) -> some View {
        let visibleRegions = SpeciesDictionaryOverviewPresentation
            .visibleRegions(in: overview)
        let regionCategory = SpeciesDictionaryOverviewPresentation.category(
            .yourRegion,
            in: overview
        )
        let showsRegionMapCard = regionCategory.map(
            SpeciesDictionaryOverviewPresentation.shouldShowRegionMapCard
        ) ?? false

        if showsRegionMapCard || !visibleRegions.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                if let regionCategory, showsRegionMapCard {
                    if regionCategory.count >= 1 {
                        NavigationLink(
                            value: SpeciesDictionaryOverviewPresentation.route(
                                for: regionCategory
                            )
                        ) {
                            SpeciesDictionaryRegionMapCard(
                                category: regionCategory,
                                width: availableWidth
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        SpeciesDictionaryRegionMapCard(
                            category: regionCategory,
                            width: availableWidth
                        )
                    }
                }

                if !visibleRegions.isEmpty {
                    NavigationLink(
                        value: SpeciesDictionaryCategoryRoute.regions
                    ) {
                        SpeciesDictionaryRegionRow(
                            title: "Browse all regions",
                            count: visibleRegions.count,
                            thumbnail: .browseAll
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingState: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let gridSpacing: CGFloat = 12
            let availableWidth = max(
                0,
                geometry.size.width - horizontalPadding * 2
            )
            let cardSize = floor((availableWidth - gridSpacing) / 2)
            let groupCardHeight = SpeciesDictionaryGroupCard.preferredHeight(
                for: cardSize
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SpeciesDictionaryFeaturedSkeletonCard(
                        width: availableWidth
                    )

                    VStack(spacing: gridSpacing) {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: gridSpacing) {
                                SpeciesDictionaryGroupSkeletonCard(
                                    width: cardSize,
                                    height: groupCardHeight
                                )
                                SpeciesDictionaryGroupSkeletonCard(
                                    width: cardSize,
                                    height: groupCardHeight
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        SpeciesDictionaryMapSkeletonCard(width: availableWidth)
                        SpeciesDictionaryOverviewRowSkeleton()
                    }

                    ForEach(0..<2, id: \.self) { _ in
                        SpeciesDictionaryOverviewRowSkeleton()
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .accessibilityHidden(true)
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label(
                "Dictionary unavailable",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await viewModel.load(userRegion: userRegion) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
