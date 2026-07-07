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
    @State private var fullscreenGalleryPresentation: InsightImageGalleryPresentation?

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
            .fullScreenCover(item: $fullscreenGalleryPresentation) { presentation in
                InsightFullscreenImageCarousel(presentation: presentation)
            }
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
                title: "Species details unavailable",
                message: "Public reference data is not available for this species yet."
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
        SpeciesDictionaryDetailLoadingSkeleton()
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
                    },
                    onImageTap: { presentation in
                        fullscreenGalleryPresentation = presentation
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

private struct SpeciesDictionaryDetailLoadingSkeleton: View {
    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)
            let contentWidth = max(pageWidth - 32, 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    hero(width: pageWidth)

                    header(width: contentWidth)

                    VStack(alignment: .leading, spacing: 32) {
                        SpeciesDictionaryDetailSkeletonCard(
                            width: contentWidth,
                            titleWidthRatio: 0.34,
                            rowWidthRatios: [0.64, 0.46],
                            showsBadge: true
                        )

                        SpeciesDictionaryDetailSkeletonCard(
                            width: contentWidth,
                            titleWidthRatio: 0.3,
                            rowWidthRatios: [0.9, 0.82, 0.58]
                        )

                        taxonomyCard(width: contentWidth)

                        observationChart(width: contentWidth)

                        similarSpecies(width: contentWidth)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(uiColor: .systemBackground))
            .ignoresSafeArea(.container, edges: .top)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading species details")
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func hero(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            SpeciesDictionaryDetailSkeletonBlock(width: width, height: width, cornerRadius: 0)

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index == 0 ? 0.7 : 0.35))
                        .frame(width: 7, height: 7)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.12), in: Capsule(style: .continuous))
            .padding(.bottom, 14)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: width)
        .clipped()
    }

    private func header(width: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            SpeciesDictionaryDetailSkeletonBlock(width: min(width * 0.52, 220), height: 18)

            SpeciesDictionaryDetailSkeletonBlock(
                width: min(width * 0.72, 280),
                height: 36,
                cornerRadius: 9
            )

            SpeciesDictionaryDetailSkeletonBlock(width: min(width * 0.56, 220), height: 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func taxonomyCard(width: CGFloat) -> some View {
        let innerWidth = max(width - 40, 1)
        let rowWidthRatios: [CGFloat] = [0.76, 0.62, 0.7, 0.48]

        return VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: innerWidth * 0.34)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(rowWidthRatios, id: \.self) { ratio in
                    HStack(spacing: 12) {
                        SpeciesDictionaryDetailSkeletonBlock(width: 74, height: 12, cornerRadius: 5)
                        SpeciesDictionaryDetailSkeletonBlock(width: innerWidth * ratio - 86, height: 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func observationChart(width: CGFloat) -> some View {
        let innerWidth = max(width - 40, 1)
        let barWidth = max((innerWidth - 48) / 7, 10)
        let barHeights: [CGFloat] = [48, 74, 58, 96, 68, 42, 84]

        return VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: innerWidth * 0.5)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(barHeights.indices, id: \.self) { index in
                    SpeciesDictionaryDetailSkeletonBlock(
                        width: barWidth,
                        height: barHeights[index],
                        cornerRadius: 5
                    )
                }
            }
            .frame(height: 112, alignment: .bottom)

            SpeciesDictionaryDetailSkeletonBlock(width: innerWidth * 0.58, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func similarSpecies(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: min(width * 0.46, 180))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SpeciesDetailSimilarCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -16)
            .disabled(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeletonHeader(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            SpeciesDictionaryDetailSkeletonBlock(width: 24, height: 24, cornerRadius: 12)
            SpeciesDictionaryDetailSkeletonBlock(width: width, height: 18)
        }
    }
}

private struct SpeciesDictionaryDetailSkeletonCard: View {
    let width: CGFloat
    let titleWidthRatio: CGFloat
    let rowWidthRatios: [CGFloat]
    var showsBadge = false

    var body: some View {
        let innerWidth = max(width - 40, 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SpeciesDictionaryDetailSkeletonBlock(width: 24, height: 24, cornerRadius: 12)
                SpeciesDictionaryDetailSkeletonBlock(width: innerWidth * titleWidthRatio, height: 18)
            }

            if showsBadge {
                SpeciesDictionaryDetailSkeletonBlock(width: 106, height: 28, cornerRadius: 14)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(rowWidthRatios, id: \.self) { ratio in
                    SpeciesDictionaryDetailSkeletonBlock(width: innerWidth * ratio, height: 13)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct SpeciesDetailSimilarCardSkeleton: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            SpeciesDictionaryDetailSkeletonBlock(width: 200, height: 260, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionaryDetailSkeletonBlock(width: 112, height: 16)
                SpeciesDictionaryDetailSkeletonBlock(width: 146, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(10)
        }
        .frame(width: 200, height: 260)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }
}

private struct SpeciesDictionaryDetailSkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: cornerRadius)
            .frame(width: max(width, 1), height: max(height, 1))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
