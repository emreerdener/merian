import SwiftUI

struct PrivateScanMapFilterSheet: View {
    let viewModel: PrivateScanMapViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    sectionTitle("Species")

                    Button {
                        viewModel.clearCategories()
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All species",
                            subtitle: PrivateScanMapPresentation.scanCountLabel(
                                viewModel.points.count
                            ),
                            systemImage: "map",
                            isSelected: viewModel.selectedCategories.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.categoryCounts) { categoryCount in
                        Button {
                            viewModel.toggleCategory(categoryCount.category)
                        } label: {
                            FilterSheetSelectionRow(
                                title: categoryCount.category.title,
                                subtitle: PrivateScanMapPresentation.scanCountLabel(
                                    categoryCount.count
                                ),
                                systemImage:
                                    categoryCount.category.privateMapSymbolName,
                                isSelected: viewModel.selectedCategories.contains(
                                    categoryCount.category
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "PrivateScanMapCategory-\(categoryCount.category.rawValue)"
                        )
                    }

                    sectionTitle("Media type")
                        .padding(.top, 8)

                    Button {
                        viewModel.clearMediaFilters()
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All media",
                            subtitle: PrivateScanMapPresentation.scanCountLabel(
                                viewModel.points.count
                            ),
                            systemImage: "rectangle.stack",
                            isSelected: viewModel.selectedMediaFilters.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.mediaCounts) { mediaCount in
                        Button {
                            viewModel.toggleMediaFilter(mediaCount.mediaFilter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: mediaCount.mediaFilter.rawValue,
                                subtitle: PrivateScanMapPresentation.scanCountLabel(
                                    mediaCount.count
                                ),
                                systemImage:
                                    mediaCount.mediaFilter.privateMapSymbolName,
                                isSelected: viewModel.selectedMediaFilters.contains(
                                    mediaCount.mediaFilter
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
                        viewModel.clearFilters()
                    }
                    .disabled(!viewModel.hasActiveFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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
