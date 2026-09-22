import SwiftUI

struct SpeciesSearchIntroduction: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let prompts: [String]
    let illustrationName: String
    @Bindable var catalog: SpeciesDictionaryCatalogViewModel
    let isSearching: Bool
    var imageDependencies: SpeciesCatalogImageDependencies = .live
    var factDependencies: SpeciesSearchFactDependencies = .live
    let onSubmit: (String) -> Void

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(illustrationName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 124, height: 124)
                        .accessibilityHidden(true)
                    Text("What would you like to discover?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 10) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button { onSubmit(prompt) } label: {
                            HStack(spacing: 12) {
                                Text(prompt)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").accessibilityHidden(true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSearching)
                    }
                }

                DidYouKnowCard(
                    factManager: factDependencies.factManager(),
                    onSelectionFeedback: factDependencies.selectionFeedback
                )

                speciesSuggestions
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            await catalog.loadIfNeeded(category: .recentlyAdded, region: nil, group: nil, query: nil)
        }
    }

    @ViewBuilder private var speciesSuggestions: some View {
        if !catalog.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Explore a species")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stride(from: 0, to: catalog.items.count, by: columnCount)), id: \.self) { rowStart in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(catalog.items[rowStart..<min(rowStart + columnCount, catalog.items.count)]) { item in
                                NavigationLink(value: SpeciesDictionaryRoute(
                                    scientificName: item.scientificName, speciesId: item.id, entryPoint: .search
                                )) {
                                    speciesTile(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                            }
                            if columnCount == 2 && rowStart + 1 == catalog.items.count {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                        }
                        // Use the tallest intrinsic card height for both cards in this row.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("SpeciesSearchStarterGrid")
        } else if catalog.isLoadingInitial {
            ProgressView("Loading species…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if catalog.errorMessage != nil {
            Button("Retry species suggestions") {
                Task { await catalog.reload(category: .recentlyAdded, region: nil, group: nil, query: nil) }
            }
            .font(.subheadline)
        }
    }

    private func speciesTile(_ item: SpeciesDictionaryCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1.25, contentMode: .fit)
                .overlay {
                    SpeciesDictionaryCatalogRemoteImage(
                        source: item.referenceImageUrl, prominentPlaceholder: true, dependencies: imageDependencies
                    )
                }
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.commonName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.scientificName)
                    .font(.caption).italic()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
