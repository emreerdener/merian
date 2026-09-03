import SwiftUI

struct SpeciesDictionaryPageContentView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint
    let showsCloseButton: Bool
    let onClose: () -> Void

    private let suppliedExploreViewModel: ExploreFeedViewModel?
    private let dependencies: SpeciesDictionaryDetailDependencies

    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @State private var viewModel: SpeciesDictionaryPageViewModel
    @State private var fallbackExploreViewModel: ExploreFeedViewModel
    @State private var dictionaryChatViewModel: InsightChatViewModel
    @State private var isCommonNameScrolledPast = false
    @State private var isTopScrollEdgeEffectHidden = true
    @State private var activePresentation: SpeciesDictionaryPresentation?
    @State private var pendingDictionaryChatSpeciesID: String?
    @State private var dictionaryChatToast: ToastPayload?

    @MainActor
    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint,
        showsCloseButton: Bool,
        exploreViewModel: ExploreFeedViewModel? = nil,
        dependencies: SpeciesDictionaryDetailDependencies? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        let dependencies = dependencies ?? .live
        let request = SpeciesDictionaryDetailRequest(
            speciesId: speciesId,
            scientificName: scientificName
        )
        self.scientificName = request.scientificName ?? ""
        self.speciesId = request.speciesId
        self.entryPoint = entryPoint
        self.showsCloseButton = showsCloseButton
        self.dependencies = dependencies
        suppliedExploreViewModel = exploreViewModel
        self.onClose = onClose
        _viewModel = State(initialValue: SpeciesDictionaryPageViewModel(
            scientificName: request.scientificName ?? "",
            speciesId: request.speciesId,
            entryPoint: entryPoint,
            dependencies: dependencies.page
        ))
        _fallbackExploreViewModel = State(
            initialValue: dependencies.makeExploreViewModel()
        )
        _dictionaryChatViewModel = State(
            initialValue: dependencies.presentation.makeFieldChatViewModel()
        )
    }

    var body: some View {
        content
            .modifier(DictionaryTopEdgeModifier(
                isHidden: isTopScrollEdgeEffectHidden
            ))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .task(id: speciesId ?? scientificName) {
                isCommonNameScrolledPast = false
                isTopScrollEdgeEffectHidden = true
                await viewModel.load()
            }
            .toolbar(
                fieldChatSpeciesID == nil ? .hidden : .visible,
                for: .bottomBar
            )
            .onChange(
                of: offlineQueueManager.isOnline,
                initial: true
            ) { _, isOnline in
                dictionaryChatViewModel.updateConnectivity(isOnline: isOnline)
            }
            .task(id: pendingDictionaryChatSpeciesID) {
                await prepareDictionaryFieldChatIfNeeded()
            }
            .fullScreenCover(
                item: fullscreenPresentationBinding
            ) { presentation in
                fullscreenPresentationContent(presentation)
            }
            .sheet(item: sheetPresentationBinding) { presentation in
                sheetPresentationContent(presentation)
            }
            .merianSystemFeedback(toast: $dictionaryChatToast)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsCloseButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome
                                .shouldUseContainedBackground
                        )
                }
                .buttonStyle(.plain)
                .imageOverlayToolbarButtonChrome(
                    isFallbackActive: ImageOverlayToolbarChrome
                        .shouldUseContainedBackground
                )
                .accessibilityLabel("Close species page")
            }
        }

        ToolbarItem(placement: .principal) {
            ScrollAwareToolbarTitleBadge(
                title: toolbarBadgeTitle,
                isVisible: isCommonNameScrolledPast
            )
        }

        if let species = viewModel.loadedSpecies,
           let shareURL = SpeciesDictionaryShareContent.url(
            speciesId: species.id,
            commonName: species.commonName,
            scientificName: species.scientificName
           ) {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: shareURL,
                    subject: Text(species.commonName),
                    message: Text(SpeciesDictionaryShareContent.message(
                        commonName: species.commonName
                    ))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome
                                .shouldUseContainedBackground
                        )
                }
                .buttonStyle(.plain)
                .imageOverlayToolbarButtonChrome(
                    isFallbackActive: ImageOverlayToolbarChrome
                        .shouldUseContainedBackground
                )
                .accessibilityLabel("Share species page")
            }
        }

        if fieldChatSpeciesID != nil {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                FieldChatToolbarButton {
                    openDictionaryFieldChat()
                }
            }
        }
    }

    private var sheetPresentationBinding:
        Binding<SpeciesDictionaryPresentation?> {
        Binding(
            get: {
                guard activePresentation?.usesFullscreenCover == false else {
                    return nil
                }
                return activePresentation
            },
            set: { presentation in
                guard presentation == nil,
                      activePresentation?.usesFullscreenCover == false
                else {
                    return
                }
                activePresentation = nil
            }
        )
    }

    private var fullscreenPresentationBinding:
        Binding<SpeciesDictionaryPresentation?> {
        Binding(
            get: {
                guard activePresentation?.usesFullscreenCover == true else {
                    return nil
                }
                return activePresentation
            },
            set: { presentation in
                guard presentation == nil,
                      activePresentation?.usesFullscreenCover == true
                else {
                    return
                }
                activePresentation = nil
            }
        )
    }

    @ViewBuilder
    private func sheetPresentationContent(
        _ presentation: SpeciesDictionaryPresentation
    ) -> some View {
        switch presentation {
        case .author(let route):
            ExploreAuthorProfileSheet(
                viewModel: effectiveExploreViewModel,
                route: route
            )
        case .fieldChat(let chat):
            InsightChatSheet(
                viewModel: dictionaryChatViewModel,
                scanId: chat.id,
                speciesData: nil,
                displayName: chat.displayName,
                timestamp: nil,
                publicScientificName: chat.scientificName,
                publicAlternativeNames: chat.alternativeScientificNames,
                allowsOwnerActions: false,
                prepareForInitialLoad: nil,
                onToast: { dictionaryChatToast = $0 },
                onAppendToFieldNotes: { _, _ in },
                onReviewAlternatives: nil,
                onReanalyzeSpecies: nil,
                onClose: {
                    dismissPresentation(ifMatching: presentation.id)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        case .paywall:
            PaywallView()
        case .gallery:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullscreenPresentationContent(
        _ presentation: SpeciesDictionaryPresentation
    ) -> some View {
        switch presentation {
        case .gallery(let gallery):
            FullscreenMediaGallery(presentation: gallery)
        case .author, .fieldChat, .paywall:
            EmptyView()
        }
    }

    private func beginPresentation(
        _ presentation: SpeciesDictionaryPresentation
    ) {
        guard activePresentation == nil else { return }
        pendingDictionaryChatSpeciesID = nil
        activePresentation = presentation
    }

    private func dismissPresentation(ifMatching presentationID: String) {
        guard activePresentation?.id == presentationID else { return }
        activePresentation = nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            SpeciesDictionaryDetailLoadingSkeleton()
        case .loaded(let species):
            loadedView(species)
        case .notFound:
            EmptyStateView(
                iconName: "magnifyingglass",
                title: "Species details unavailable",
                message:
                    "Public reference data is not available for this species yet."
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

    private func loadedView(_ species: SpeciesDictionaryEntry) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                SpeciesDictionaryReferenceGallery(
                    scientificName: species.scientificName,
                    images: species.referenceImages,
                    onImageLoadFailed: { image in
                        dependencies.presentation.track(.imageFallback(
                            entryPoint: viewModel.entryPoint.rawValue,
                            source: image.source.rawValue
                        ))
                    },
                    onHeroBottomChange: evaluateHeroScrollOffset,
                    onImageTap: { presentation in
                        beginPresentation(.gallery(presentation))
                    },
                    onAuthorTap: { image in
                        presentAuthorProfile(for: image)
                    }
                )

                VStack(alignment: .leading, spacing: 24) {
                    header(for: species)

                    VStack(alignment: .leading, spacing: 32) {
                        SpeciesDictionaryContentQualityCard(
                            quality: species.effectiveContentQuality
                        )
                        SpeciesDictionaryStatusCard(
                            hazardType: species.hazardType
                        )
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

                        if species.gbifTaxonKey != nil
                            || species.habitatDescription?
                            .trimmedNonEmptyValue != nil {
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
                        SpeciesCommunitySightingsSection(
                            speciesId: species.id,
                            exploreViewModel: effectiveExploreViewModel,
                            dependencies: dependencies.communitySightings
                        )

                        if let similarData = species.similarSpeciesData {
                            SimilarSpeciesGallery(
                                similarData: similarData,
                                currentScientificName: species.scientificName,
                                currentCommonName: species.commonName,
                                currentSpeciesId: species.id,
                                routeForSpecies: speciesDictionaryRoute
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .modifier(DictionaryHeroContentSheetModifier())
            }
        }
        .background(Color(uiColor: .systemBackground))
        .coordinateSpace(name: "SpeciesDictionaryScrollSpace")
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent)
        .onChange(of: species.id, initial: true) { _, _ in
            isCommonNameScrolledPast = false
            isTopScrollEdgeEffectHidden = true
        }
    }

    private func presentAuthorProfile(
        for image: SpeciesDictionaryReferenceImage
    ) {
        guard image.source == .merian,
              let authorUserId = image.authorUserId?.trimmedNonEmptyValue,
              let authorUsername = image.naturebookAuthorUsername
        else {
            return
        }

        beginPresentation(.author(ExploreAuthorProfileRoute(
            authorUserId: authorUserId,
            authorName: authorUsername,
            authorUsername: authorUsername,
            authorAvatarUrl: nil
        )))
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
                    GeometryReader { geometry in
                        Color.clear
                            .onChange(
                                of: geometry.frame(
                                    in: .named(
                                        "SpeciesDictionaryScrollSpace"
                                    )
                                ).maxY,
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

    private func evaluateHeroScrollOffset(maxY: CGFloat) {
        guard let shouldHideEffect = DictionaryHeroEdgePolicy
            .shouldHideEffect(
                heroMaxY: maxY,
                isCurrentlyHidden: isTopScrollEdgeEffectHidden
            ), shouldHideEffect != isTopScrollEdgeEffectHidden
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isTopScrollEdgeEffectHidden = shouldHideEffect
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
        viewModel.loadedSpecies?.commonName
            ?? scientificName.trimmedNonEmptyValue
            ?? "Species"
    }

    private var toolbarBadgeTitle: String {
        viewModel.loadedSpecies?.commonName ?? ""
    }

    private var fieldChatSpeciesID: String? {
        SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(
            viewModel.loadedSpecies?.id
        )
    }

    private var effectiveExploreViewModel: ExploreFeedViewModel {
        suppliedExploreViewModel ?? fallbackExploreViewModel
    }

    private func speciesDictionaryRoute(
        for entry: SimilarSpeciesEntry
    ) -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId,
            entryPoint: .speciesDictionarySimilarSpecies
        )
    }

    private func openDictionaryFieldChat() {
        guard let species = viewModel.loadedSpecies,
              let canonicalSpeciesID = SpeciesDictionaryChatPresentationPolicy
                .canonicalSpeciesID(species.id),
              activePresentation == nil,
              pendingDictionaryChatSpeciesID == nil
        else {
            return
        }

        dependencies.presentation.feedback(.selection)
        let isProActive = dependencies.presentation.isProActive()
        dependencies.presentation.track(.fieldChatTapped(
            entryPoint: viewModel.entryPoint.rawValue,
            contentQuality: species.effectiveContentQuality.telemetryValue,
            isPro: isProActive
        ))

        guard SpeciesDictionaryChatPresentationPolicy.destination(
            isProActive: isProActive
        ) == .fieldChat else {
            beginPresentation(.paywall)
            return
        }

        pendingDictionaryChatSpeciesID = canonicalSpeciesID
    }

    @MainActor
    private func prepareDictionaryFieldChatIfNeeded() async {
        guard let speciesID = pendingDictionaryChatSpeciesID else { return }
        let canPresent = await dictionaryChatViewModel.prepareForPresentation(
            scanId: speciesID
        )
        guard pendingDictionaryChatSpeciesID == speciesID else { return }
        defer {
            if pendingDictionaryChatSpeciesID == speciesID {
                pendingDictionaryChatSpeciesID = nil
            }
        }
        guard SpeciesDictionaryChatPresentationPolicy
            .canCommitAsyncPresentation(
                requestedSpeciesID: speciesID,
                currentSpeciesID: fieldChatSpeciesID,
                hasActivePresentation: activePresentation != nil,
                isCancelled: Task.isCancelled
            ), let species = viewModel.loadedSpecies
        else {
            return
        }

        if canPresent {
            dependencies.presentation.feedback(.sheet)
            activePresentation = .fieldChat(
                SpeciesDictionaryChatPresentation(
                    id: speciesID,
                    displayName: species.commonName,
                    scientificName: species.scientificName,
                    alternativeScientificNames: species.similarSpecies.map(
                        \.scientificName
                    )
                )
            )
        } else {
            dependencies.presentation.feedback(.error)
            dictionaryChatToast = .error(
                dictionaryChatViewModel.errorMessage
                    ?? FieldChatSource.speciesDictionary.unavailableMessage
            )
        }
    }
}
