import SwiftUI

struct SpeciesDictionaryPageView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint

    @Environment(\.dismiss) private var dismiss

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown
    ) {
        self.scientificName = scientificName
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        self.entryPoint = entryPoint
    }

    var body: some View {
        NavigationStack {
            SpeciesDictionaryPageContentView(
                scientificName: scientificName,
                speciesId: speciesId,
                entryPoint: entryPoint,
                showsCloseButton: true,
                onClose: { dismiss() }
            )
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

struct SpeciesDictionaryPageContentView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint
    let showsCloseButton: Bool
    let onClose: () -> Void

    @State private var viewModel: SpeciesDictionaryPageViewModel
    @State private var isCommonNameScrolledPast = false

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint,
        showsCloseButton: Bool,
        onClose: @escaping () -> Void = {}
    ) {
        self.scientificName = scientificName
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        self.entryPoint = entryPoint
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
        _viewModel = State(initialValue: SpeciesDictionaryPageViewModel(
            scientificName: scientificName,
            speciesId: speciesId,
            entryPoint: entryPoint
        ))
    }

    var body: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 32)
                                .imageOverlayToolbarIconChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                        }
                        .buttonStyle(.plain)
                        .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                        .accessibilityLabel("Close species page")
                    }
                }

                ToolbarItem(placement: .principal) {
                    ScrollAwareToolbarTitleBadge(
                        title: toolbarBadgeTitle,
                        isVisible: isCommonNameScrolledPast
                    )
                }
            }
            .task(id: speciesId ?? scientificName) {
                isCommonNameScrolledPast = false
                await viewModel.load()
            }
            .toolbar(.hidden, for: .bottomBar)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .loaded(let species):
            loadedView(species)
        case .notFound:
            UnscannedSpeciesCallToActionView(scientificName: scientificName)
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

                VStack(alignment: .leading, spacing: 32) {
                    SpeciesDictionaryContentQualityCard(quality: species.effectiveContentQuality)

                    SpeciesDictionaryStatusCard(hazardType: species.hazardType)

                    ExploreOverviewCard(
                        scientificName: species.scientificName,
                        iucnRedListStatus: species.iucnRedListStatus,
                        wikipediaOverview: species.wikipediaOverview
                    )

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

                    SpeciesObservationChartsCard(
                        speciesId: species.id,
                        scientificName: species.scientificName
                    )

                    if let similarData = species.similarSpeciesData {
                        SimilarSpeciesGallery(
                            similarData: similarData,
                            currentScientificName: species.scientificName,
                            currentCommonName: species.commonName,
                            routeForSpecies: speciesDictionaryRoute
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .coordinateSpace(name: "SpeciesDictionaryScrollSpace")
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent)
        .onChange(of: species.id, initial: true) { _, _ in
            isCommonNameScrolledPast = false
        }
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(
                                of: geo.frame(in: .named("SpeciesDictionaryScrollSpace")).maxY,
                                initial: true
                            ) { _, newMaxY in
                                evaluateCommonNameScrollOffset(maxY: newMaxY)
                            }
                    }
                )

            AlternativeCommonNamesLine(
                names: species.alternativeCommonNames,
                primaryCommonName: species.commonName
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func evaluateCommonNameScrollOffset(maxY: CGFloat) {
        guard maxY != .infinity else { return }

        let isPast = maxY < 44
        guard isCommonNameScrolledPast != isPast else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isCommonNameScrolledPast = isPast
        }
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
        viewModel.loadedSpecies?.commonName ?? scientificName.trimmedNonEmpty ?? "Species"
    }

    private var toolbarBadgeTitle: String {
        viewModel.loadedSpecies?.commonName ?? ""
    }

    private func speciesDictionaryRoute(for entry: SimilarSpeciesEntry) -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId,
            entryPoint: .speciesDictionarySimilarSpecies
        )
    }
}

private struct UnscannedSpeciesCallToActionView: View {
    let scientificName: String

    @State private var imageFetcher = SimilarSpeciesImageFetcher()

    private var displayScientificName: String {
        scientificName.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty ?? "This species"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Undocumented in Merian")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(displayScientificName)
                            .font(.system(.largeTitle, design: .serif).weight(.bold))
                            .italic()
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("No one has added this species to the community dictionary yet.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Find it in the wild and scan it to help complete this page.", systemImage: "viewfinder")
                        Label("A confirmed observation can add reference media, habitat context, and future lookalike links.", systemImage: "leaf")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(.container, edges: .top)
        .task(id: displayScientificName) {
            _ = await imageFetcher.fetchImage(for: displayScientificName)
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        ZStack {
            Color(uiColor: .systemGray6)

            if let image = imageFetcher.images.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if imageFetcher.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.macro")
                        .font(.system(size: 42, weight: .regular))
                    Text("Reference image pending")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if imageFetcher.images.first != nil {
                Text("Public reference preview")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule(style: .continuous))
                    .padding(16)
            }
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
