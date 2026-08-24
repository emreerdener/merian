import SwiftUI

struct SpeciesDictionaryPageView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint

    @Environment(\.dismiss) private var dismiss
    @State private var exploreViewModel = ExploreFeedViewModel()

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
                exploreViewModel: exploreViewModel,
                onClose: { dismiss() }
            )
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: exploreViewModel
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
    private let suppliedExploreViewModel: ExploreFeedViewModel?

    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @State private var viewModel: SpeciesDictionaryPageViewModel
    @State private var fallbackExploreViewModel = ExploreFeedViewModel()
    @State private var isCommonNameScrolledPast = false
    @State private var isTopScrollEdgeEffectHidden = true
    @State private var fullscreenGalleryPresentation: InsightImageGalleryPresentation?
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var dictionaryChatViewModel = InsightChatViewModel(
        source: .speciesDictionary
    )
    @State private var pendingDictionaryChatSpeciesID: String?
    @State private var dictionaryChatPresentation: SpeciesDictionaryChatPresentation?
    @State private var isDictionaryChatPaywallPresented = false
    @State private var dictionaryChatToast: ToastPayload?

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint,
        showsCloseButton: Bool,
        exploreViewModel: ExploreFeedViewModel? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.scientificName = scientificName
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        self.entryPoint = entryPoint
        self.showsCloseButton = showsCloseButton
        suppliedExploreViewModel = exploreViewModel
        self.onClose = onClose
        _viewModel = State(initialValue: SpeciesDictionaryPageViewModel(
            scientificName: scientificName,
            speciesId: speciesId,
            entryPoint: entryPoint
        ))
    }

    var body: some View {
        content
            .modifier(DictionaryTopEdgeModifier(
                isHidden: isTopScrollEdgeEffectHidden
            ))
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
                            message: Text(SpeciesDictionaryShareContent.message(commonName: species.commonName))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 32)
                                .imageOverlayToolbarIconChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                        }
                        .buttonStyle(.plain)
                        .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
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
            .task(id: speciesId ?? scientificName) {
                isCommonNameScrolledPast = false
                isTopScrollEdgeEffectHidden = true
                await viewModel.load()
            }
            .toolbar(
                fieldChatSpeciesID == nil ? .hidden : .visible,
                for: .bottomBar
            )
            .onChange(of: offlineQueueManager.isOnline, initial: true) { _, isOnline in
                dictionaryChatViewModel.updateConnectivity(isOnline: isOnline)
            }
            .task(id: pendingDictionaryChatSpeciesID) {
                await prepareDictionaryFieldChatIfNeeded()
            }
            .fullScreenCover(item: $fullscreenGalleryPresentation) { presentation in
                InsightFullscreenImageCarousel(presentation: presentation)
            }
            .sheet(item: $selectedAuthorProfileRoute) { route in
                ExploreAuthorProfileSheet(viewModel: effectiveExploreViewModel, route: route)
            }
            .sheet(item: $dictionaryChatPresentation) { presentation in
                InsightChatSheet(
                    viewModel: dictionaryChatViewModel,
                    scanId: presentation.id,
                    speciesData: nil,
                    displayName: presentation.displayName,
                    timestamp: nil,
                    publicScientificName: presentation.scientificName,
                    publicAlternativeNames: presentation.alternativeScientificNames,
                    allowsOwnerActions: false,
                    prepareForInitialLoad: nil,
                    onToast: { dictionaryChatToast = $0 },
                    onAppendToFieldNotes: { _, _ in },
                    onReviewAlternatives: nil,
                    onReanalyzeSpecies: nil,
                    onClose: { dictionaryChatPresentation = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $isDictionaryChatPaywallPresented) {
                PaywallView()
            }
            .merianSystemFeedback(toast: $dictionaryChatToast)
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
            VStack(alignment: .leading, spacing: 0) {
                SpeciesDictionaryReferenceGallery(
                    scientificName: species.scientificName,
                    images: species.referenceImages,
                    onImageLoadFailed: { image in
                        AppTelemetry.trackSpeciesDictionaryImageFallback(
                            entryPoint: viewModel.entryPoint.rawValue,
                            source: image.source.rawValue
                        )
                    },
                    onHeroBottomChange: evaluateHeroScrollOffset,
                    onImageTap: { presentation in
                        fullscreenGalleryPresentation = presentation
                    },
                    onAuthorTap: { image in
                        presentAuthorProfile(for: image)
                    }
                )

                VStack(alignment: .leading, spacing: 24) {
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

                        SpeciesCommunitySightingsSection(
                            speciesId: species.id,
                            exploreViewModel: effectiveExploreViewModel
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

    private func presentAuthorProfile(for image: SpeciesDictionaryReferenceImage) {
        guard image.source == .merian,
              let authorUserId = image.authorUserId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmedNonEmpty,
              let authorUsername = image.naturebookAuthorUsername else { return }

        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(
            authorUserId: authorUserId,
            authorName: authorUsername,
            authorUsername: authorUsername,
            authorAvatarUrl: nil
        )
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

    private func evaluateHeroScrollOffset(maxY: CGFloat) {
        guard let shouldHideEffect = DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: maxY,
            isCurrentlyHidden: isTopScrollEdgeEffectHidden
        ), shouldHideEffect != isTopScrollEdgeEffectHidden else {
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
        viewModel.loadedSpecies?.commonName ?? scientificName.trimmedNonEmpty ?? "Species"
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

    private func speciesDictionaryRoute(for entry: SimilarSpeciesEntry) -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId,
            entryPoint: .speciesDictionarySimilarSpecies
        )
    }

    private func openDictionaryFieldChat() {
        guard let species = viewModel.loadedSpecies,
              let canonicalSpeciesID = SpeciesDictionaryChatPresentationPolicy
                .canonicalSpeciesID(species.id) else {
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        let isProActive = RevenueCatManager.shared.isProActive
        AppTelemetry.trackSpeciesDictionaryFieldChatTapped(
            entryPoint: viewModel.entryPoint.rawValue,
            contentQuality: species.effectiveContentQuality.telemetryValue,
            isPro: isProActive
        )

        guard SpeciesDictionaryChatPresentationPolicy.destination(
            isProActive: isProActive
        ) == .fieldChat else {
            isDictionaryChatPaywallPresented = true
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
        guard !Task.isCancelled,
              pendingDictionaryChatSpeciesID == speciesID,
              fieldChatSpeciesID == speciesID,
              let species = viewModel.loadedSpecies else {
            return
        }

        if canPresent {
            HapticManager.shared.triggerSheetSpring()
            dictionaryChatPresentation = SpeciesDictionaryChatPresentation(
                id: speciesID,
                displayName: species.commonName,
                scientificName: species.scientificName,
                alternativeScientificNames: species.similarSpecies.map(\.scientificName)
            )
        } else {
            HapticManager.shared.triggerErrorThump()
            dictionaryChatToast = .error(
                dictionaryChatViewModel.errorMessage
                    ?? FieldChatSource.speciesDictionary.unavailableMessage
            )
        }
        pendingDictionaryChatSpeciesID = nil
    }
}

private struct SpeciesDictionaryChatPresentation: Identifiable {
    let id: String
    let displayName: String
    let scientificName: String
    let alternativeScientificNames: [String]
}

enum SpeciesDictionaryChatPresentationPolicy {
    enum Destination: Equatable {
        case fieldChat
        case paywall
    }

    static func canonicalSpeciesID(_ value: String?) -> String? {
        guard let value,
              let uuid = UUID(
                uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    static func destination(isProActive: Bool) -> Destination {
        isProActive ? .fieldChat : .paywall
    }
}

enum SpeciesDictionaryShareContent {
    private static let slugMaximumLength = 80

    static func url(
        speciesId: String,
        commonName: String,
        scientificName: String
    ) -> URL? {
        guard let uuid = UUID(uuidString: speciesId.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let slug = slug(commonName: commonName, scientificName: scientificName)
        return PublicBrand.websiteURL(path: "species/\(uuid.uuidString.lowercased())/\(slug)")
    }

    static func slug(commonName: String, scientificName: String) -> String {
        for candidate in [commonName, scientificName] {
            if let slug = slugCandidate(candidate) {
                return slug
            }
        }
        return "species"
    }

    private static func slugCandidate(_ value: String) -> String? {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .decomposedStringWithCompatibilityMapping
            .lowercased()

        var result = ""
        var needsSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.nonBaseCharacters.contains(scalar) {
                continue
            }

            let value = scalar.value
            let isASCIILetter = (97...122).contains(value)
            let isASCIIDigit = (48...57).contains(value)
            guard isASCIILetter || isASCIIDigit else {
                needsSeparator = !result.isEmpty
                continue
            }

            let requiredCharacters = needsSeparator && !result.isEmpty ? 2 : 1
            guard result.count + requiredCharacters <= slugMaximumLength else {
                break
            }
            if needsSeparator && !result.isEmpty {
                result.append("-")
            }
            result.unicodeScalars.append(scalar)
            needsSeparator = false
        }

        return result.isEmpty ? nil : result
    }

    static func message(commonName: String) -> String {
        let name = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "this species" : name
        return "Learn about \(displayName) on Naturebook."
    }
}

enum DictionaryHeroEdgePolicy {
    static let toolbarLowerBoundary: CGFloat = 44
    static let returnHysteresis: CGFloat = 4

    static func shouldHideEffect(
        heroMaxY: CGFloat,
        isCurrentlyHidden: Bool
    ) -> Bool? {
        guard heroMaxY.isFinite else { return nil }

        if isCurrentlyHidden {
            return heroMaxY > toolbarLowerBoundary
        }

        return heroMaxY >= toolbarLowerBoundary + returnHysteresis
    }
}

private struct DictionaryTopEdgeModifier: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(isHidden, for: .top)
        } else {
            content
        }
    }
}

private struct SpeciesDictionaryDetailLoadingSkeleton: View {
    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)
            let contentWidth = max(pageWidth - 32, 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero(width: pageWidth)

                    VStack(alignment: .leading, spacing: 24) {
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
                    .modifier(DictionaryHeroContentSheetModifier())
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
            .padding(.bottom, SpeciesDictionaryHeroLayout.overlayBottomInset)
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

private struct DictionaryHeroContentSheetModifier: ViewModifier {
    private let contentTopSpacing: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(.top, contentTopSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: SpeciesDictionaryHeroLayout.contentOverlap,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: SpeciesDictionaryHeroLayout.contentOverlap
                )
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                .padding(.bottom, -1000)
            )
            .offset(y: -SpeciesDictionaryHeroLayout.contentOverlap)
            .padding(.bottom, -SpeciesDictionaryHeroLayout.contentOverlap)
            .zIndex(1)
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
