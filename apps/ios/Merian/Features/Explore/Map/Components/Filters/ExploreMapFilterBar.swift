import SwiftUI

struct ExploreMapFilterBar: View {
    @Bindable var viewModel: ExploreMapViewModel
    let onShowFilters: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    title: viewModel.hasActiveFilters
                        ? "Filters \(viewModel.activeFilterCount.formatted())"
                        : "Filters",
                    systemImage: "line.3.horizontal.decrease",
                    isSelected: viewModel.hasActiveFilters,
                    action: onShowFilters
                )
                .accessibilityLabel("Map filters")

                filterPill(
                    title: "All",
                    isSelected: !viewModel.hasActiveFilters
                ) {
                    Task { await viewModel.clearFilters() }
                }

                ForEach(viewModel.visibleCategoryCounts) { categoryCount in
                    filterPill(
                        title: categoryCount.category.title,
                        isSelected: viewModel.selectedSpeciesCategories.contains(
                            categoryCount.category
                        )
                    ) {
                        Task {
                            await viewModel.toggleSpeciesFilter(categoryCount.category)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func filterPill(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }

                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary)
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
