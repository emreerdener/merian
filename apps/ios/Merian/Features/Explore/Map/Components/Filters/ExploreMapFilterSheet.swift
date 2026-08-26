import SwiftUI

struct ExploreMapFilterSheet: View {
    @Bindable var viewModel: ExploreMapViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    sectionTitle("Species")

                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.clearSpeciesFilters() }
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All species",
                            subtitle: ExploreMapPresentation.discoveriesInViewLabel(
                                count: totalAvailableDiscoveryCount
                            ),
                            systemImage: "map",
                            isSelected: !viewModel.hasActiveSpeciesFilters
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.visibleCategoryCounts) { categoryCount in
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            Task {
                                await viewModel.toggleSpeciesFilter(categoryCount.category)
                            }
                        } label: {
                            FilterSheetSelectionRow(
                                title: categoryCount.category.title,
                                subtitle: categoryCount.count >= 1
                                    ? ExploreMapPresentation.discoveriesInViewLabel(
                                        count: categoryCount.count
                                    )
                                    : "Filter map",
                                systemImage: categoryCount.category.symbolName,
                                isSelected: viewModel.selectedSpeciesCategories.contains(
                                    categoryCount.category
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    sectionTitle("Media type")
                        .padding(.top, 8)

                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.clearMediaTypeFilters() }
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All media",
                            subtitle: viewModel.hasActiveMediaTypeFilters
                                ? "Show every media type"
                                : ExploreMapPresentation.discoveriesInViewLabel(
                                    count: viewModel.visibleDiscoveryCount
                                ),
                            systemImage: "rectangle.stack",
                            isSelected: !viewModel.hasActiveMediaTypeFilters
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.visibleMediaTypeCounts) { mediaTypeCount in
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            Task {
                                await viewModel.toggleMediaTypeFilter(mediaTypeCount.mediaType)
                            }
                        } label: {
                            FilterSheetSelectionRow(
                                title: mediaTypeCount.mediaType.filterTitle,
                                subtitle: mediaTypeCount.count >= 1
                                    ? ExploreMapPresentation.discoveriesInViewLabel(
                                        count: mediaTypeCount.count
                                    )
                                    : "Filter map",
                                systemImage: mediaTypeCount.mediaType.filterSymbolName,
                                isSelected: viewModel.selectedMediaTypes.contains(
                                    mediaTypeCount.mediaType
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Map filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.clearFilters() }
                    }
                    .disabled(!viewModel.hasActiveFilters)
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

    private var totalAvailableDiscoveryCount: Int {
        let countedTotal = viewModel.categoryCounts.reduce(0) { $0 + $1.count }
        return max(countedTotal, viewModel.visibleCount)
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
}
