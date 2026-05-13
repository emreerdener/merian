import SwiftUI

struct SpeciesDictionaryPageView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SpeciesDictionaryPageViewModel

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown
    ) {
        self.scientificName = scientificName
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        self.entryPoint = entryPoint
        _viewModel = State(initialValue: SpeciesDictionaryPageViewModel(
            scientificName: scientificName,
            speciesId: speciesId,
            entryPoint: entryPoint
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close species page")
                    }
                }
        }
        .task(id: speciesId ?? scientificName) {
            await viewModel.load()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .loaded(let species):
            loadedView(species)
        case .notFound:
            EmptyStateView(
                iconName: "magnifyingglass",
                title: "Species not found",
                message: "This species is not in the dictionary yet."
            ) {
                retryButton
            }
        case .error(let message):
            EmptyStateView(
                iconName: "wifi.exclamationmark",
                title: "Unable to load species",
                message: message
            ) {
                retryButton
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading species details...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private func loadedView(_ species: SpeciesDictionaryEntry) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                SpeciesDictionaryReferenceGallery(
                    scientificName: species.scientificName,
                    images: species.referenceImages,
                    onImageLoadFailed: { image in
                        AppTelemetry.trackSpeciesDictionaryImageFallback(
                            entryPoint: viewModel.entryPoint.rawValue,
                            source: image.source.rawValue
                        )
                    }
                )

                header(for: species)

                VStack(alignment: .leading, spacing: 24) {
                    SpeciesDictionaryContentQualityCard(quality: species.effectiveContentQuality)

                    SpeciesDictionaryStatusCard(hazardType: species.hazardType)

                    ExploreOverviewCard(
                        scientificName: species.scientificName,
                        iucnRedListStatus: species.iucnRedListStatus,
                        wikipediaOverview: species.wikipediaOverview
                    )

                    SpeciesDictionaryNamesCard(names: species.alternativeCommonNames)

                    if let taxonomyData = species.taxonomyData {
                        TaxonomyCard(
                            taxonomyData: taxonomyData,
                            scientificName: species.scientificName
                        )
                    }

                    if species.gbifTaxonKey != nil || species.habitatDescription?.trimmedNonEmpty != nil {
                        ExploreHabitatDistributionCard(
                            scientificName: species.scientificName,
                            habitatDescription: species.habitatDescription,
                            gbifTaxonKey: species.gbifTaxonKey
                        )
                    }

                    SpeciesDictionaryTagsCard(tags: species.groupTags)

                    if let similarData = species.similarSpeciesData {
                        SimilarSpeciesGallery(
                            similarData: similarData,
                            currentScientificName: species.scientificName,
                            currentCommonName: species.commonName
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func header(for species: SpeciesDictionaryEntry) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(species.scientificName)
                .font(.system(.title3))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(species.commonName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var retryButton: some View {
        Button {
            Task { await viewModel.retry() }
        } label: {
            Text("Try again")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .foregroundStyle(Color(uiColor: .systemBackground))
        .background(Color.primary, in: Capsule(style: .continuous))
        .padding(.top, 4)
    }

    private var navigationTitle: String {
        viewModel.loadedSpecies?.commonName ?? "Species"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
