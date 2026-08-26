import SwiftUI

struct CommunityTaxonomySearchSheet: View {
    let currentPath: String?
    let taxonomyVersionId: String?
    let initialSuggestions: [CommunityTaxonSearchResult]
    let onSelect: (CommunityTaxonSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var viewModel = CommunityTaxonomySearchViewModel()

    var body: some View {
        NavigationStack {
            List {
                if isShowingInitialSuggestions {
                    Section("Suggested from AI analysis") {
                        if initialSuggestions.isEmpty {
                            Text("No AI suggestions are available for this request.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(initialSuggestions) { suggestion in
                                taxonButton(for: suggestion)
                            }
                        }
                    }
                } else {
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }

                    ForEach(viewModel.results) { result in
                        taxonButton(for: result)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Suggest ID")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: query) {
                await viewModel.search(
                    query: query,
                    taxonomyVersionId: taxonomyVersionId
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Close")
                    .imageOverlayToolbarButtonChrome(
                        isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                    )
                }
            }
        }
    }

    private var isShowingInitialSuggestions: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    private func taxonButton(for result: CommunityTaxonSearchResult) -> some View {
        Button {
            onSelect(result)
            dismiss()
        } label: {
            CommunityTaxonSearchRow(result: result)
        }
        .buttonStyle(.plain)
    }
}

private struct CommunityTaxonSearchRow: View {
    let result: CommunityTaxonSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.displayName)
                .font(.body)
                .foregroundStyle(.primary)
            Text("\(result.displayRank) - \(result.scientificName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let label = result.suggestionSource?.displayLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
