import SwiftUI

struct ExploreFeedFilterSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Binding var isPresented: Bool
    let isResolvingNearbyLocation: Bool
    let onSelectFilter: (ExploreFeedFilter) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    sectionTitle("Feed")
                    feedOptions

                    sectionTitle("Media type")
                        .padding(.top, 8)
                    mediaOptions

                    sectionTitle("Date shared")
                        .padding(.top, 8)
                    dateOptions

                    if viewModel.activeFilter == .nearby {
                        sectionTitle("Distance")
                            .padding(.top, 8)
                        distanceOptions
                    }

                    sectionTitle("Species")
                        .padding(.top, 8)
                    speciesOptions
                }
                .padding()
            }
            .navigationTitle("Feed filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.resetAdvancedFilters() }
                    }
                    .disabled(!viewModel.hasStoredAdvancedFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.triggerSelectionPulse()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var feedOptions: some View {
        ForEach(ExploreFeedFilter.allCases) { filter in
            Button {
                HapticManager.shared.triggerSelectionPulse()
                onSelectFilter(filter)
            } label: {
                FilterSheetSelectionRow(
                    title: filter.title,
                    subtitle: subtitle(for: filter),
                    systemImage: symbol(for: filter),
                    isSelected: viewModel.activeFilter == filter
                )
            }
            .buttonStyle(.plain)
            .disabled(isResolvingNearbyLocation)
        }
    }

    @ViewBuilder
    private var mediaOptions: some View {
        Button {
            updateMediaTypes([])
        } label: {
            FilterSheetSelectionRow(
                title: "All media",
                subtitle: "Show every media type",
                systemImage: "rectangle.stack",
                isSelected: viewModel.advancedFilters.mediaTypes.isEmpty
            )
        }
        .buttonStyle(.plain)

        ForEach(ExploreMediaKind.feedFilterCases) { mediaType in
            Button {
                toggleMediaType(mediaType)
            } label: {
                FilterSheetSelectionRow(
                    title: mediaType.filterTitle,
                    subtitle: "Show posts containing \(mediaType.filterTitle.lowercased())",
                    systemImage: mediaType.filterSymbolName,
                    isSelected: viewModel.advancedFilters.mediaTypes.contains(mediaType)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var dateOptions: some View {
        ForEach(ExploreFeedDateRange.allCases) { dateRange in
            Button {
                updateDateRange(dateRange)
            } label: {
                FilterSheetSelectionRow(
                    title: dateRange.title,
                    subtitle: dateRange.subtitle,
                    systemImage: "calendar",
                    isSelected: viewModel.advancedFilters.dateRange == dateRange
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var distanceOptions: some View {
        ForEach(ExploreFeedNearbyRadius.allCases) { radius in
            Button {
                updateNearbyRadius(radius)
            } label: {
                FilterSheetSelectionRow(
                    title: radius.title,
                    subtitle: "Search within \(radius.rawValue) miles of your current location",
                    systemImage: "location.circle",
                    isSelected: viewModel.advancedFilters.nearbyRadius == radius
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var speciesOptions: some View {
        Button {
            updateSpeciesCategories([])
        } label: {
            FilterSheetSelectionRow(
                title: "All species",
                subtitle: "Show every species group",
                systemImage: "map",
                isSelected: viewModel.advancedFilters.speciesCategories.isEmpty
            )
        }
        .buttonStyle(.plain)

        ForEach(ExploreMapSpeciesCategory.defaultFilters) { category in
            Button {
                toggleSpeciesCategory(category)
            } label: {
                FilterSheetSelectionRow(
                    title: category.title,
                    subtitle: "Show discoveries in this species group",
                    systemImage: category.symbolName,
                    isSelected: viewModel.advancedFilters.speciesCategories.contains(category)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func subtitle(for filter: ExploreFeedFilter) -> String {
        switch filter {
        case .recent: "Newest discoveries first"
        case .following: "Discoveries from people you follow"
        case .trending: "Discoveries getting attention now"
        case .nearby: "Discoveries near your current location"
        }
    }

    private func symbol(for filter: ExploreFeedFilter) -> String {
        switch filter {
        case .recent: "clock.arrow.circlepath"
        case .following: "person.2"
        case .trending: "flame"
        case .nearby: "location"
        }
    }

    private func updateSpeciesCategories(_ categories: Set<ExploreMapSpeciesCategory>) {
        var filters = viewModel.advancedFilters
        filters.speciesCategories = categories
        apply(filters)
    }

    private func toggleSpeciesCategory(_ category: ExploreMapSpeciesCategory) {
        var categories = viewModel.advancedFilters.speciesCategories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        updateSpeciesCategories(categories)
    }

    private func updateMediaTypes(_ mediaTypes: Set<ExploreMediaKind>) {
        var filters = viewModel.advancedFilters
        filters.mediaTypes = mediaTypes
        apply(filters)
    }

    private func toggleMediaType(_ mediaType: ExploreMediaKind) {
        var mediaTypes = viewModel.advancedFilters.mediaTypes
        if mediaTypes.contains(mediaType) {
            mediaTypes.remove(mediaType)
        } else {
            mediaTypes.insert(mediaType)
        }
        updateMediaTypes(mediaTypes)
    }

    private func updateDateRange(_ dateRange: ExploreFeedDateRange) {
        var filters = viewModel.advancedFilters
        filters.dateRange = dateRange
        apply(filters)
    }

    private func updateNearbyRadius(_ radius: ExploreFeedNearbyRadius) {
        var filters = viewModel.advancedFilters
        filters.nearbyRadius = radius
        apply(filters)
    }

    private func apply(_ filters: ExploreFeedAdvancedFilters) {
        HapticManager.shared.triggerSelectionPulse()
        Task { await viewModel.applyAdvancedFilters(filters) }
    }
}
