import SwiftUI

struct SpeciesDictionaryRegionsView: View {
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
                    let visibleRegions = SpeciesDictionaryOverviewPresentation
                        .visibleRegions(in: overview)
                    if visibleRegions.isEmpty {
                        emptyState
                    } else {
                        regionList(visibleRegions)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Regions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userRegion ?? "") {
            await viewModel.load(userRegion: userRegion)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No regions found",
            systemImage: "map",
            description: Text(
                "Country browsing will appear as verified GBIF occurrence coverage is refreshed."
            )
        )
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { _ in
                    SpeciesDictionaryOverviewRowSkeleton()
                }
            }
            .padding(16)
        }
        .accessibilityHidden(true)
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label(
                "Regions unavailable",
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

    private func regionList(
        _ regions: [SpeciesDictionaryRegionSummary]
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(regions) { region in
                    NavigationLink(
                        value: SpeciesDictionaryCategoryRoute.catalog(
                            title: region.title,
                            category: .region,
                            region: region.code ?? region.title
                        )
                    ) {
                        SpeciesDictionaryRegionRow(
                            title: region.title,
                            count: region.count,
                            thumbnail: .country(code: region.code)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.load(userRegion: userRegion)
        }
    }
}
