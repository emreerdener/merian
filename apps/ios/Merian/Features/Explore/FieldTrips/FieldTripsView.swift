import SwiftData
import SwiftUI

enum FieldTripTemplatePresentation {
    static let backyardSafariSlug = "backyard_safari"
    static let parkPollinatorsSlug = "park_pollinators"
    static let backyardSafariSubtitle = "Observe local species often found in your own backyard."

    static func title(_ title: String, slug: String) -> String {
        slug == backyardSafariSlug ? "Backyard Safari" : title
    }

    static func currentLevel(for template: FieldTripTemplate) -> FieldTripLevel? {
        if let levelNumber = template.viewerProgress?.currentLevelNumber {
            return template.levels.first(where: { $0.levelNumber == levelNumber })
        }

        return template.levels.min(by: { $0.levelNumber < $1.levelNumber })
    }

    static func previewLevel(for template: FieldTripTemplate) -> FieldTripLevel? {
        currentLevel(for: template)
            ?? template.levels.min(by: { $0.levelNumber < $1.levelNumber })
    }

    static func targetCount(for template: FieldTripTemplate) -> Int {
        if let targetCount = template.viewerProgress?.targetCount, targetCount > 0 {
            return targetCount
        }

        return previewLevel(for: template)?.items.count ?? 0
    }

    static func completedCount(for template: FieldTripTemplate) -> Int {
        max(0, template.viewerProgress?.completedCount ?? 0)
    }

    static func currentLevelTitle(for template: FieldTripTemplate) -> String {
        if let title = currentLevel(for: template)?.title
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        let levelNumber = template.viewerProgress?.currentLevelNumber
            ?? template.levels.map(\.levelNumber).min()
            ?? 1
        return "Level \(max(1, levelNumber))"
    }

    static func subtitle(for template: FieldTripTemplate) -> String? {
        guard template.slug == backyardSafariSlug else { return template.subtitle }

        let targetCount = targetCount(for: template)
        guard targetCount > 0 else { return backyardSafariSubtitle }
        return "Observe \(targetCount) local species often found in your own backyard."
    }

    static func status(for template: FieldTripTemplate) -> FieldTripTemplateStatusPresentation {
        if template.isStopped {
            return .init(kind: .stopped, title: "Stopped")
        }

        switch template.catalogState {
        case .completed:
            return .init(kind: .completed, title: "Completed")
        case .inProgress:
            return .init(kind: .active, title: "Active")
        case .incomplete:
            return .init(kind: .notStarted, title: "Not started")
        }
    }

    static func detailTags(
        for template: FieldTripTemplate,
        locationLabel: String?,
        sharingEnabled: Bool = FieldTripSharingAvailability.isEnabled
    ) -> [FieldTripTemplateTagPresentation] {
        var tags: [FieldTripTemplateTagPresentation] = []

        if sharingEnabled, let progress = template.viewerProgress {
            if progress.isPublished {
                tags.append(.init(kind: .visibility, title: "Published", systemImage: "eye.fill"))
            } else {
                tags.append(.init(kind: .visibility, title: "Private", systemImage: "eye.slash.fill"))
            }
        }

        if !template.viewerHasAccess,
           template.isProOnly || template.accessKind.lowercased() == "pro" {
            tags.append(.init(kind: .access, title: "Pro", systemImage: "lock.fill"))
        }

        tags.append(.init(kind: .difficulty, title: template.difficultyTitle))
        tags.append(.init(kind: .level, title: currentLevelTitle(for: template)))

        if let locationLabel = locationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !locationLabel.isEmpty {
            tags.append(.init(kind: .location, title: locationLabel))
        }

        return tags
    }

    static func bundledCoverImageName(for slug: String?) -> String? {
        slug == backyardSafariSlug ? "fieldtrip-backyard-safari" : nil
    }
}

struct FieldTripTemplateStatusPresentation: Equatable {
    enum Kind: String, Equatable {
        case notStarted
        case active
        case stopped
        case completed
        case locked
    }

    let kind: Kind
    let title: String

    var catalogActionTitle: String {
        kind == .notStarted ? "Get started" : "View field trip"
    }
}

struct FieldTripTemplateTagPresentation: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case access
        case difficulty
        case level
        case visibility
        case location
    }

    let kind: Kind
    let title: String
    var systemImage: String?

    var id: String { "\(kind.rawValue):\(title)" }
}

struct FieldTripsView: View {
    let userRegion: String?
    @Binding var selectedSection: FieldTripsSection
    let onOpenTemplate: (String) -> Void
    let onOpenCompletedScan: (String) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @Query private var localScans: [LocalScanRecord]
    @State private var viewModel = FieldTripsViewModel()
    @State private var filters = FieldTripCatalogFilters()
    @State private var isShowingFilterSheet = false

    var body: some View {
        VStack(spacing: 0) {
            switch selectedSection {
            case .fieldTrips:
                fieldTripsContent
            case .seasonal:
                seasonalTripsContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isShowingFilterSheet) {
            outingFilterSheet
        }
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            switch event {
            case .fieldTripProgressInvalidated:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            case .captureGoalContextInvalidated(let source) where source == .fieldTrip:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            case .fieldTripChallengeProgressInvalidated:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toast: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private var fieldTripsContent: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    filterBar

                    LazyVStack(spacing: 16) {
                        if viewModel.isLoading && viewModel.templates.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                FieldTripTemplateSkeletonCard()
                            }
                        } else if let errorMessage = viewModel.errorMessage, viewModel.templates.isEmpty {
                            FieldTripUnavailableCard(
                                title: "Field trips unavailable",
                                message: errorMessage
                            ) {
                                Task { await viewModel.refresh(userRegion: userRegion) }
                            }
                        } else if viewModel.templates.isEmpty {
                            fieldTripEmptyState(
                                title: "No outings yet",
                                message: "New field trips will appear here as soon as they’re ready."
                            )
                            .frame(
                                minHeight: max(440, geometry.size.height - 96)
                            )
                        } else if filteredTemplates.isEmpty {
                            filteredEmptyState
                                .frame(
                                    minHeight: max(440, geometry.size.height - 96)
                                )
                        } else {
                            ForEach(filteredTemplates) { template in
                                FieldTripTemplateCard(
                                    template: template,
                                    localScansById: localScansById,
                                    onOpenTemplate: {
                                        HapticManager.shared.triggerLightImpact(
                                            intensity: 0.45,
                                            source: "fieldTrips.catalog.template.open"
                                        )
                                        onOpenTemplate(template.templateId)
                                    },
                                    onOpenCompletedScan: onOpenCompletedScan
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .refreshable {
                await viewModel.refresh(userRegion: userRegion)
            }
        }
    }

    private var filteredTemplates: [FieldTripTemplate] {
        viewModel.templates.filtering(by: filters)
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: FieldTripDifficultyFilter.allCases,
            activeItem: filters.difficulty,
            title: { $0.title },
            leadingTitle: filters.hasActiveFilters
                ? "Filters \(filters.activeFilterCount.formatted())"
                : "Filters",
            leadingSystemImage: "line.3.horizontal.decrease",
            isLeadingSelected: filters.hasActiveFilters,
            onSelection: { filter in
                selectDifficulty(filter)
            },
            onLeadingSelection: {
                HapticManager.shared.triggerSelectionPulse()
                isShowingFilterSheet = true
            }
        )
        .accessibilityLabel("Field trip filters")
    }

    private var filteredEmptyState: some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: "No outings match these filters",
            message: "Try changing or resetting your filters."
        ) {
            Button {
                resetFilters()
            } label: {
                Text("Reset filters")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var outingFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    filterSectionTitle("Difficulty")

                    ForEach(FieldTripDifficultyFilter.allCases, id: \.self) { filter in
                        Button {
                            selectDifficulty(filter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: filter.title,
                                subtitle: difficultyFilterSubtitle(filter),
                                systemImage: difficultyFilterSymbol(filter),
                                isSelected: filters.difficulty == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filters.difficulty == filter ? .isSelected : [])
                    }

                    filterSectionTitle("Status")
                        .padding(.top, 8)

                    ForEach(FieldTripStateFilter.allCases, id: \.self) { filter in
                        Button {
                            selectState(filter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: filter.title,
                                subtitle: stateFilterSubtitle(filter),
                                systemImage: stateFilterSymbol(filter),
                                isSelected: filters.state == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filters.state == filter ? .isSelected : [])
                    }
                }
                .padding()
            }
            .navigationTitle("Outing filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .disabled(!filters.hasActiveFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.triggerSelectionPulse()
                        isShowingFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func selectDifficulty(_ filter: FieldTripDifficultyFilter) {
        guard filter != filters.difficulty else { return }
        filters.difficulty = filter
        HapticManager.shared.triggerSelectionPulse()
    }

    private func selectState(_ filter: FieldTripStateFilter) {
        guard filter != filters.state else { return }
        filters.state = filter
        HapticManager.shared.triggerSelectionPulse()
    }

    private func resetFilters() {
        guard filters.hasActiveFilters else { return }
        filters.reset()
        HapticManager.shared.triggerSelectionPulse()
    }

    private func difficultyFilterSubtitle(_ filter: FieldTripDifficultyFilter) -> String {
        switch filter {
        case .all:
            "Show every difficulty"
        case .starter:
            "Onboarding-friendly outings with familiar goals"
        case .easy:
            "Focused outings suited to one ordinary field trip"
        case .moderate:
            "Outings requiring more time or a specific habitat"
        case .hard:
            "Specialized or time-dependent outings"
        }
    }

    private func difficultyFilterSymbol(_ filter: FieldTripDifficultyFilter) -> String {
        switch filter {
        case .all:
            "circle.grid.2x2"
        case .starter:
            "sparkles"
        case .easy:
            "leaf"
        case .moderate:
            "figure.walk"
        case .hard:
            "mountain.2"
        }
    }

    private func stateFilterSubtitle(_ filter: FieldTripStateFilter) -> String {
        switch filter {
        case .all:
            "Show outings at every status"
        case .completed:
            "Outings with every goal completed"
        case .inProgress:
            "Started outings that are not complete"
        case .incomplete:
            "Outings you haven’t started"
        }
    }

    private func stateFilterSymbol(_ filter: FieldTripStateFilter) -> String {
        switch filter {
        case .all:
            "rectangle.stack"
        case .completed:
            "checkmark.circle"
        case .inProgress:
            "clock.arrow.circlepath"
        case .incomplete:
            "circle"
        }
    }

    private var seasonalTripsContent: some View {
        let visibleChallenges = viewModel.challenges
            .filter { $0.isLive || $0.isUpcoming }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.isLive
                }
                return lhs.startsAt < rhs.startsAt
        }

        return GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.challenges.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            FieldTripChallengeSkeletonCard()
                        }
                    } else if let challengeErrorMessage = viewModel.challengeErrorMessage, visibleChallenges.isEmpty {
                        FieldTripUnavailableCard(
                            title: "Events unavailable",
                            message: challengeErrorMessage
                        ) {
                            Task { await viewModel.refresh(userRegion: userRegion) }
                        }
                    } else if visibleChallenges.isEmpty {
                        fieldTripEmptyState(
                            title: "No events right now",
                            message: "Check back soon for upcoming seasonal field trips."
                        )
                        .frame(
                            minHeight: max(440, geometry.size.height - 40)
                        )
                    } else {
                        ForEach(visibleChallenges) { challenge in
                            NavigationLink(value: FieldTripChallengeRoute(challengeId: challenge.challengeId)) {
                                FieldTripChallengeCard(challenge: challenge)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    HapticManager.shared.triggerLightImpact(
                                        intensity: 0.45,
                                        source: "fieldTrips.catalog.challenge.open"
                                    )
                                }
                            )
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable {
                await viewModel.refresh(userRegion: userRegion)
            }
        }
    }

    private func fieldTripEmptyState(title: String, message: String) -> some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: title,
            message: message
        )
    }
}

private enum FieldTripLifecycleConfirmation: String, Identifiable {
    case stop
    case reset

    var id: String { rawValue }
}

enum FieldTripDetailLoadingPresentation {
    static func showsFeaturedMediaHero(
        isLoading: Bool,
        hasTemplate: Bool
    ) -> Bool {
        isLoading && !hasTemplate
    }
}

struct FieldTripTemplateDetailView: View {
    let reference: FieldTripTemplateReference
    let focusedChecklistItemId: String?
    let onOpenCompletedScan: (String) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Query private var localScans: [LocalScanRecord]
    @State private var template: FieldTripTemplate?
    @State private var communityPreview: [FieldTripRecentPublication] = []
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var isResetting = false
    @State private var isLoadingCommunityPreview = false
    @State private var errorMessage: String?
    @State private var publishingTemplate: FieldTripTemplate?
    @State private var toastMessage: ToastPayload?
    @State private var expandedGuideItemId: String?
    @State private var pendingGuideItemId: String?
    @State private var highlightedGuideItemId: String?
    @State private var pendingObjectiveItemId: String?
    @State private var highlightedObjectiveItemId: String?
    @State private var guideHighlightTask: Task<Void, Never>?
    @State private var objectiveHighlightTask: Task<Void, Never>?
    @State private var didApplyInitialFocus = false
    @State private var defaultGuideSelectionKey: String?
    @State private var lifecycleConfirmation: FieldTripLifecycleConfirmation?
    @State private var unavailableFeaturedMediaSourceIdentifiers: Set<String> = []
    @State private var featuredMediaGalleryPresentation: InsightImageGalleryPresentation?
    @State private var isFeaturedHeroTopScrollEdgeEffectHidden = true
    @State private var detailLocationLabel: String?

    init(
        reference: FieldTripTemplateReference,
        focusedChecklistItemId: String? = nil,
        onOpenCompletedScan: @escaping (String) -> Void,
        onOpenPublication: @escaping (String) -> Void,
        onOpenAuthorProfile: @escaping (FieldTripRecentPublication) -> Void
    ) {
        self.reference = reference
        self.focusedChecklistItemId = focusedChecklistItemId
        self.onOpenCompletedScan = onOpenCompletedScan
        self.onOpenPublication = onOpenPublication
        self.onOpenAuthorProfile = onOpenAuthorProfile
    }

    init(
        templateId: String,
        focusedChecklistItemId: String? = nil,
        onOpenCompletedScan: @escaping (String) -> Void,
        onOpenPublication: @escaping (String) -> Void,
        onOpenAuthorProfile: @escaping (FieldTripRecentPublication) -> Void
    ) {
        self.init(
            reference: .id(templateId),
            focusedChecklistItemId: focusedChecklistItemId,
            onOpenCompletedScan: onOpenCompletedScan,
            onOpenPublication: onOpenPublication,
            onOpenAuthorProfile: onOpenAuthorProfile
        )
    }

    var body: some View {
        let underlapsNavigationBar = featuredHeroUnderlapsNavigationBar

        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                if isLoading && template == nil {
                    FieldTripTemplateDetailSkeleton(
                        kind: .outing,
                        showsFeaturedMediaHero: showsFeaturedMediaLoadingSkeleton,
                        onFeaturedHeroMaxYChange: { maxY in
                            updateFeaturedHeroScrollEdgeEffect(maxY: maxY)
                        }
                    )
                    .padding(.horizontal, showsFeaturedMediaLoadingSkeleton ? 0 : 16)
                    .padding(.vertical, showsFeaturedMediaLoadingSkeleton ? 0 : 16)
                } else if let errorMessage, template == nil {
                    FieldTripUnavailableCard(
                        title: "Field trip unavailable",
                        message: errorMessage
                    ) {
                        Task { await load(force: true) }
                    }
                    .padding(16)
                } else if let template {
                    detailContent(template, scrollProxy: scrollProxy)
                        .padding(.bottom, 32)
                }
            }
            .coordinateSpace(name: FieldTripFeaturedMediaLayout.scrollCoordinateSpace)
            .modifier(MediaHeroTopScrollEdgeEffectModifier(
                isHidden: underlapsNavigationBar && isFeaturedHeroTopScrollEdgeEffectHidden
            ))
            .ignoresSafeArea(
                .container,
                edges: underlapsNavigationBar ? .top : []
            )
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
            .toolbarBackground(
                underlapsNavigationBar ? Visibility.hidden : Visibility.automatic,
                for: .navigationBar
            )
            .task {
                await load(force: false)
            }
            .task(id: environmentContextManager.locationAuthorizationStatus) {
                let locationName = await environmentContextManager.currentAuthorizedLocationName()
                guard !Task.isCancelled else { return }
                detailLocationLabel = locationName
            }
            .onDisappear {
                guideHighlightTask?.cancel()
                guideHighlightTask = nil
                objectiveHighlightTask?.cancel()
                objectiveHighlightTask = nil
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .fieldTripProgressInvalidated(let templateIds) = event,
                      let resolvedTemplateId = template?.templateId,
                      templateIds.contains(resolvedTemplateId) else {
                    return
                }
                Task { await load(force: true) }
            }
            .onChange(of: offlineQueueManager.isOnline) { _, isOnline in
                if isOnline {
                    unavailableFeaturedMediaSourceIdentifiers.removeAll()
                }
            }
            .onChange(of: underlapsNavigationBar) { _, isUnderlapping in
                if isUnderlapping {
                    isFeaturedHeroTopScrollEdgeEffectHidden = true
                }
            }
            .sheet(item: $publishingTemplate) { template in
                FieldTripPublishSheet(template: template) { publication in
                    publishingTemplate = nil
                    onOpenPublication(publication.publicationId)
                    Task { await load(force: true) }
                }
            }
            .fullScreenCover(item: $featuredMediaGalleryPresentation) { presentation in
                InsightFullscreenImageCarousel(presentation: presentation)
            }
            .alert(item: $lifecycleConfirmation) { confirmation in
                lifecycleAlert(for: confirmation)
            }
            .merianSystemFeedback(
                toast: Binding(
                    get: { toastMessage },
                    set: { toastMessage = $0 }
                ),
                toastAlignment: .top
            )
        }
    }

    @ViewBuilder
    private func detailContent(
        _ template: FieldTripTemplate,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let featuredMediaItems = featuredMediaItems(for: template)

        VStack(alignment: .leading, spacing: 0) {
            if !featuredMediaItems.isEmpty {
                FieldTripFeaturedMediaCarousel(
                    items: featuredMediaItems,
                    onMediaLoadFailed: { sourceIdentifier in
                        unavailableFeaturedMediaSourceIdentifiers.insert(sourceIdentifier)
                    },
                    onOpenViewer: { selectedItemId in
                        featuredMediaGalleryPresentation =
                            FieldTripFeaturedMediaPresentation.galleryPresentation(
                                for: featuredMediaItems,
                                selectedItemId: selectedItemId
                            )
                    }
                )
                .containerRelativeFrame(.horizontal)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(
                                of: proxy.frame(
                                    in: .named(FieldTripFeaturedMediaLayout.scrollCoordinateSpace)
                                ).maxY,
                                initial: true
                            ) { _, newMaxY in
                                updateFeaturedHeroScrollEdgeEffect(maxY: newMaxY)
                            }
                    }
                }
                .ignoresSafeArea(.all, edges: .top)
            }

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    FieldTripLifecycleStatusBadge(
                        status: FieldTripTemplatePresentation.status(for: template)
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text(FieldTripTemplatePresentation.title(template.title, slug: template.slug))
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = template.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FieldTripTemplateDetailTagRow(
                        tags: FieldTripTemplatePresentation.detailTags(
                            for: template,
                            locationLabel: detailLocationLabel
                        )
                    )

                    if let primaryAction = FieldTripDetailLifecyclePresentation.primaryAction(
                        for: template
                    ) {
                        primaryActionBar(template, action: primaryAction)
                            .padding(.top, 12)
                    }
                }
                .padding(.vertical, 16)

                FieldTripLevelsSection(
                    template: template,
                    currentLevelNumber: template.viewerProgress?.currentLevelNumber ?? 1,
                    isTripComplete: template.viewerProgress?.isComplete ?? false,
                    status: FieldTripTemplatePresentation.status(for: template),
                    progress: template.viewerProgress.map(FieldTripLevelProgressPresentation.init),
                    progressPlacement: .headerRing,
                    expandedGuideItemId: $expandedGuideItemId,
                    highlightedGuideItemId: highlightedGuideItemId,
                    highlightedItemId: highlightedObjectiveItemId,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: { item in
                        openGuide(item, scrollProxy: scrollProxy)
                    }
                )
                .onAppear {
                    consumePendingObjectiveScroll(with: scrollProxy)
                    consumePendingGuideScroll(with: scrollProxy)
                }

                FieldTripCommunityPreviewSection(
                    publications: communityPreview,
                    isLoading: isLoadingCommunityPreview,
                    onOpenPublication: onOpenPublication,
                    onOpenAuthorProfile: onOpenAuthorProfile
                )

                FieldTripAboutOutingSection(template: template)
            }
            .padding(.horizontal, 16)
            .padding(.top, featuredMediaItems.isEmpty ? 16 : 0)
            .modifier(FieldTripHeroContentSheetModifier(
                isEnabled: !featuredMediaItems.isEmpty
            ))
        }
    }

    private func openGuide(
        _ item: FieldTripChecklistItem,
        scrollProxy: ScrollViewProxy
    ) {
        guard item.hasGuide else { return }
        HapticManager.shared.triggerSelectionPulse()
        let nextSelection = FieldTripGoalTipSelection.toggledSelection(
            currentItemId: expandedGuideItemId,
            tappedItemId: item.id,
            hasGuide: item.hasGuide
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedGuideItemId = nextSelection
        }
        guard nextSelection == item.id else {
            pendingGuideItemId = nil
            guideHighlightTask?.cancel()
            guideHighlightTask = nil
            highlightedGuideItemId = nil
            return
        }
        pendingGuideItemId = item.id
        consumePendingGuideScroll(with: scrollProxy)
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    private var featuredHeroUnderlapsNavigationBar: Bool {
        if showsFeaturedMediaLoadingSkeleton {
            return true
        }

        return FieldTripFeaturedMediaLayout.underlapsNavigationBar(
            featuredItemCount: template.map { featuredMediaItems(for: $0).count } ?? 0
        )
    }

    private var showsFeaturedMediaLoadingSkeleton: Bool {
        FieldTripDetailLoadingPresentation.showsFeaturedMediaHero(
            isLoading: isLoading,
            hasTemplate: template != nil
        )
    }

    private func featuredMediaItems(
        for template: FieldTripTemplate
    ) -> [FieldTripFeaturedMediaItem] {
        FieldTripFeaturedMediaSelection.items(
            from: FieldTripFeaturedMediaBuilder.candidates(
                for: template,
                localScansById: localScansById,
                excluding: unavailableFeaturedMediaSourceIdentifiers
            ),
            activeLevelId: FieldTripTemplatePresentation.currentLevel(for: template)?.id
        )
    }

    private func updateFeaturedHeroScrollEdgeEffect(maxY: CGFloat) {
        let shouldHide = MediaHeroTopScrollEdgeEffectPolicy.isHidden(
            heroMaxY: maxY,
            currentlyHidden: isFeaturedHeroTopScrollEdgeEffectHidden
        )
        guard shouldHide != isFeaturedHeroTopScrollEdgeEffectHidden else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isFeaturedHeroTopScrollEdgeEffectHidden = shouldHide
        }
    }

    private func consumePendingGuideScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingGuideItemId else { return }
        pendingGuideItemId = nil
        highlightedGuideItemId = itemId

        guideHighlightTask?.cancel()
        guideHighlightTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, highlightedGuideItemId == itemId else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(
                    FieldTripGuideScrollTarget(itemId: itemId),
                    anchor: .center
                )
            }
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            guard !Task.isCancelled, highlightedGuideItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedGuideItemId = nil
            }
            guideHighlightTask = nil
        }
    }

    private func consumePendingObjectiveScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingObjectiveItemId else { return }
        pendingObjectiveItemId = nil
        highlightedObjectiveItemId = itemId

        objectiveHighlightTask?.cancel()
        objectiveHighlightTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, highlightedObjectiveItemId == itemId else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(itemId, anchor: .center)
            }
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            guard !Task.isCancelled, highlightedObjectiveItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedObjectiveItemId = nil
            }
            objectiveHighlightTask = nil
        }
    }

    private func applyInitialFocusIfNeeded(to template: FieldTripTemplate) {
        guard !didApplyInitialFocus,
              let focusedChecklistItemId,
              let level = template.levels.first(where: { level in
                  level.items.contains(where: { $0.id == focusedChecklistItemId })
              }),
              let item = level.items.first(where: { $0.id == focusedChecklistItemId }) else {
            return
        }
        didApplyInitialFocus = true

        let currentLevelNumber = template.viewerProgress?.currentLevelNumber
            ?? template.levels.map(\.levelNumber).min()
            ?? 1
        let showsInlineTips = FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: level.levelNumber,
            currentLevelNumber: currentLevelNumber,
            isTripComplete: template.viewerProgress?.isComplete ?? false,
            hasGuide: item.hasGuide
        ) && !item.isCompleted

        if showsInlineTips {
            expandedGuideItemId = item.id
            pendingGuideItemId = item.id
        } else {
            pendingObjectiveItemId = item.id
        }
    }

    private func applyDefaultGuideSelectionIfNeeded(to template: FieldTripTemplate) {
        guard focusedChecklistItemId == nil,
              !(template.viewerProgress?.isComplete ?? false),
              let level = FieldTripTemplatePresentation.currentLevel(for: template) else {
            return
        }

        let selectionKey = "\(template.templateId):\(level.id)"
        guard defaultGuideSelectionKey != selectionKey else { return }
        defaultGuideSelectionKey = selectionKey
        expandedGuideItemId = FieldTripGoalTipSelection.defaultItemId(in: level.items)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if let template,
           FieldTripDetailLifecyclePresentation.showsOptionsMenu(template) {
            ToolbarItem(placement: .topBarTrailing) {
                lifecycleOptionsMenu(template)
            }
        }
    }

    private func lifecycleOptionsMenu(_ template: FieldTripTemplate) -> some View {
        Menu {
            if FieldTripDetailLifecyclePresentation.canStop(template) {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    lifecycleConfirmation = .stop
                } label: {
                    Label("Stop field trip", systemImage: "stop.circle")
                }
            }

            if FieldTripDetailLifecyclePresentation.canReset(template) {
                Button(role: .destructive) {
                    HapticManager.shared.triggerSelectionPulse()
                    lifecycleConfirmation = .reset
                } label: {
                    Label("Reset field trip", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
        }
        .disabled(isLifecycleMutating)
        .accessibilityLabel("Field trip options")
        .accessibilityIdentifier("FieldTripDetailOptions")
    }

    @ViewBuilder
    private func primaryActionBar(
        _ template: FieldTripTemplate,
        action: FieldTripDetailPrimaryAction
    ) -> some View {
        switch action {
        case .unlock:
            FieldTripDetailPrimaryActionBar(
                title: "Unlock with Pro",
                systemImage: "lock.fill",
                isEnabled: !isLifecycleMutating
            ) {
                AppDIContainer.shared.appRouteCoordinator.request(
                    .proAccessRequired,
                    source: .internalUserAction
                )
            }
        case .start:
            FieldTripDetailPrimaryActionBar(
                title: "Start",
                systemImage: "play.fill",
                isLoading: isStarting,
                isEnabled: !isLifecycleMutating
            ) {
                Task { await start(template) }
            }
        case .resume:
            FieldTripDetailPrimaryActionBar(
                title: "Resume",
                systemImage: "play.fill",
                isLoading: isStarting,
                isEnabled: !isLifecycleMutating
            ) {
                Task { await start(template) }
            }
        case .publish:
            FieldTripDetailPrimaryActionBar(
                title: "Publish",
                systemImage: "square.and.arrow.up",
                isEnabled: !isLifecycleMutating
            ) {
                publishingTemplate = template
            }
        case .scan:
            FieldTripDetailPrimaryActionBar(
                title: "Start scanning",
                systemImage: nil,
                isEnabled: !isLifecycleMutating
            ) {
                openScanner()
            }
        }
    }

    private var isLifecycleMutating: Bool {
        isStarting || isStopping || isResetting
    }

    private func lifecycleAlert(for confirmation: FieldTripLifecycleConfirmation) -> Alert {
        switch confirmation {
        case .stop:
            Alert(
                title: Text("Stop this field trip?"),
                message: Text(
                    "Your progress will be saved. Scans taken before you stop can still count if you approve their identification later, and you can resume anytime."
                ),
                primaryButton: .default(Text("Stop field trip")) {
                    guard let template else { return }
                    Task { await stop(template) }
                },
                secondaryButton: .cancel()
            )
        case .reset:
            Alert(
                title: Text("Reset this field trip?"),
                message: Text(
                    "This clears all goal progress for this unfinished field trip and returns it to its initial state. This can’t be undone."
                ),
                primaryButton: .destructive(Text("Reset field trip")) {
                    guard let template else { return }
                    Task { await reset(template) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func openScanner() {
        HapticManager.shared.triggerLightImpact(
            intensity: 0.45,
            source: "fieldTrips.outing.goScan"
        )
        AppDIContainer.shared.appRouteCoordinator.request(
            .openScanner,
            source: .internalUserAction
        )
    }

    private func load(force: Bool) async {
        guard force || template == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedTemplate: FieldTripTemplate
            switch reference {
            case .id(let templateId):
                loadedTemplate = try await MerianNetworkClient.shared.getFieldTripTemplate(
                    templateId: templateId
                )
            case .slug(let slug):
                loadedTemplate = try await MerianNetworkClient.shared.getFieldTripTemplate(slug: slug)
            }
            template = loadedTemplate
            applyInitialFocusIfNeeded(to: loadedTemplate)
            applyDefaultGuideSelectionIfNeeded(to: loadedTemplate)
            await loadCommunityPreview(templateId: loadedTemplate.templateId)
        } catch {
            errorMessage = ExploreErrorFormatter.fieldTripDetailMessage(for: error)
        }
    }

    private func start(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating else { return }
        let wasStopped = template.isStopped
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            self.template = try await MerianNetworkClient.shared.startFieldTrip(templateId: template.templateId)
            HapticManager.shared.triggerSuccessPulse()
            if wasStopped {
                toastMessage = .success("Field trip resumed.")
            }
            AppDIContainer.shared.appEventPublisher.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    private func stop(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating,
              let progress = template.activeProgress,
              !progress.isComplete else { return }
        isStopping = true
        defer { isStopping = false }

        do {
            self.template = try await MerianNetworkClient.shared.stopFieldTrip(
                userFieldTripId: progress.userFieldTripId
            )
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = .success("Field trip stopped. Your progress is saved.")
            AppDIContainer.shared.appEventPublisher.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    private func reset(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating,
              let progress = template.viewerProgress,
              !progress.isComplete,
              progress.publicationId == nil else { return }
        isResetting = true
        defer { isResetting = false }

        do {
            self.template = try await MerianNetworkClient.shared.resetFieldTrip(
                userFieldTripId: progress.userFieldTripId
            )
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = .success("Field trip reset.")
            AppDIContainer.shared.appEventPublisher.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    private func loadCommunityPreview(templateId: String) async {
        isLoadingCommunityPreview = true
        defer { isLoadingCommunityPreview = false }

        communityPreview = (try? await MerianNetworkClient.shared.getFieldTripCommunityPublications(
            mode: .smart,
            templateId: templateId,
            userRegion: nil,
            limit: 3
        )) ?? []
    }
}

struct FieldTripChallengeDetailView: View {
    let challengeId: String
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void

    @State private var viewModel: FieldTripChallengeDetailViewModel
    @State private var publishingChallenge: FieldTripChallenge?
    @State private var expandedGuideItemId: String?
    @State private var pendingGuideItemId: String?
    @State private var highlightedGuideItemId: String?
    @State private var guideHighlightTask: Task<Void, Never>?

    init(
        challengeId: String,
        onOpenEntry: @escaping (String) -> Void,
        onOpenAuthorProfile: @escaping (FieldTripChallengeEntry) -> Void
    ) {
        self.challengeId = challengeId
        self.onOpenEntry = onOpenEntry
        self.onOpenAuthorProfile = onOpenAuthorProfile
        _viewModel = State(initialValue: FieldTripChallengeDetailViewModel(challengeId: challengeId))
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                if viewModel.isLoading && viewModel.challenge == nil {
                    FieldTripTemplateDetailSkeleton(kind: .event)
                        .padding(16)
                } else if let errorMessage = viewModel.errorMessage, viewModel.challenge == nil {
                    FieldTripUnavailableCard(
                        title: "Event unavailable",
                        message: errorMessage
                    ) {
                        Task { await viewModel.refresh() }
                    }
                    .padding(16)
                } else if let challenge = viewModel.challenge {
                    detailContent(challenge, scrollProxy: scrollProxy)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(viewModel.challenge?.title ?? (viewModel.isLoading ? "Loading..." : "Challenge"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let challenge = viewModel.challenge {
                    primaryActionBar(challenge)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(.bar)
                }
            }
            .task {
                await viewModel.load()
            }
            .onDisappear {
                guideHighlightTask?.cancel()
                guideHighlightTask = nil
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .fieldTripChallengeProgressInvalidated(let challengeIds) = event,
                      challengeIds.contains(challengeId) else {
                    return
                }
                Task { await viewModel.refresh() }
            }
            .sheet(item: $publishingChallenge) { challenge in
                FieldTripChallengePublishSheet(challenge: challenge) { entry in
                    publishingChallenge = nil
                    onOpenEntry(entry.entryId)
                    Task { await viewModel.refresh() }
                }
            }
            .merianSystemFeedback(
                toast: Binding(
                    get: { viewModel.toastMessage },
                    set: { viewModel.toastMessage = $0 }
                ),
                toastAlignment: .top
            )
        }
    }

    @ViewBuilder
    private func detailContent(
        _ challenge: FieldTripChallenge,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        if let template = challenge.template {
            VStack(alignment: .leading, spacing: 24) {
                challengeOverview(challenge)

                FieldTripLevelsSection(
                    template: template,
                    currentLevelNumber: challenge.viewerParticipation?.currentLevelNumber ?? 1,
                    isTripComplete: challenge.viewerParticipation?.isComplete ?? false,
                    status: nil,
                    progress: challenge.viewerParticipation.map(FieldTripLevelProgressPresentation.init),
                    progressPlacement: .bar,
                    expandedGuideItemId: $expandedGuideItemId,
                    highlightedGuideItemId: highlightedGuideItemId,
                    highlightedItemId: nil,
                    localScansById: [:],
                    onOpenCompletedScan: { _ in },
                    onOpenGuide: { item in
                        openGuide(item, scrollProxy: scrollProxy)
                    }
                )

                challengeEntriesSection

                FieldTripAboutOutingSection(template: template)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                challengeOverview(challenge)
                challengeEntriesSection
            }
        }
    }

    private func openGuide(
        _ item: FieldTripChecklistItem,
        scrollProxy: ScrollViewProxy
    ) {
        guard item.hasGuide else { return }
        HapticManager.shared.triggerSelectionPulse()
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedGuideItemId = item.id
        }
        pendingGuideItemId = item.id
        consumePendingGuideScroll(with: scrollProxy)
    }

    private func consumePendingGuideScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingGuideItemId else { return }
        pendingGuideItemId = nil
        highlightedGuideItemId = itemId

        guideHighlightTask?.cancel()
        guideHighlightTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, highlightedGuideItemId == itemId else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(
                    FieldTripGuideScrollTarget(itemId: itemId),
                    anchor: .center
                )
            }
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            guard !Task.isCancelled, highlightedGuideItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedGuideItemId = nil
            }
            guideHighlightTask = nil
        }
    }

    private func challengeOverview(_ challenge: FieldTripChallenge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldTripCoverImage(
                urlString: challenge.coverImageUrl,
                templateSlug: challenge.templateSlug
            )
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .top, spacing: 10) {
                Text(challenge.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                FieldTripChallengeStatusBadge(status: challenge.status)
            }

            if let description = challenge.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FieldTripChallengeStatsRow(challenge: challenge)

            if challenge.template == nil,
               let participation = challenge.viewerParticipation {
                FieldTripChallengeProgressBar(participation: participation)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }

        }
    }

    private var challengeEntriesSection: some View {
        FieldTripChallengeEntriesSection(
            entries: viewModel.entries,
            hasMoreEntries: viewModel.hasMoreEntries,
            isLoadingMore: viewModel.isLoadingMoreEntries,
            onOpenEntry: onOpenEntry,
            onOpenAuthorProfile: onOpenAuthorProfile,
            onLoadMore: {
                Task { await viewModel.loadMoreEntries() }
            }
        )
    }

    @ViewBuilder
    private func primaryActionBar(_ challenge: FieldTripChallenge) -> some View {
        if !challenge.viewerHasAccess {
            FieldTripDetailPrimaryActionBar(
                title: "Unlock with Pro",
                systemImage: "lock.fill"
            ) {
                AppDIContainer.shared.appRouteCoordinator.request(
                    .proAccessRequired,
                    source: .internalUserAction
                )
            }
        } else if let participation = challenge.viewerParticipation, participation.isComplete {
            FieldTripDetailPrimaryActionBar(
                title: "Publish event entry",
                systemImage: "square.and.arrow.up"
            ) {
                publishingChallenge = challenge
            }
        } else if challenge.isUpcoming {
            FieldTripDetailPrimaryActionBar(
                title: "Starts \(FieldTripDisplayDate.shortDate(challenge.startsAt))",
                systemImage: "calendar",
                isEnabled: false,
                style: .status
            ) {}
        } else if challenge.isEnded {
            FieldTripDetailPrimaryActionBar(
                title: "Event ended",
                systemImage: "clock.fill",
                isEnabled: false,
                style: .status
            ) {}
        } else if challenge.viewerParticipation == nil {
            FieldTripDetailPrimaryActionBar(
                title: "Join event",
                systemImage: "plus.circle.fill",
                isLoading: viewModel.isJoining,
                isEnabled: !viewModel.isJoining
            ) {
                Task { await viewModel.join() }
            }
        } else {
            FieldTripDetailPrimaryActionBar(
                title: "Start scanning",
                systemImage: nil
            ) {
                openScanner()
            }
        }
    }

    private func openScanner() {
        HapticManager.shared.triggerLightImpact(
            intensity: 0.45,
            source: "fieldTrips.event.goScan"
        )
        AppDIContainer.shared.appRouteCoordinator.request(
            .openScanner,
            source: .internalUserAction
        )
    }
}

private struct FieldTripDetailPrimaryActionBar: View {
    enum Style {
        case primary
        case status
    }

    let title: String
    let systemImage: String?
    var isLoading = false
    var isEnabled = true
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(foregroundColor)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                    }

                    Text(title)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)
            }
            .font(.headline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(backgroundColor)
        .frame(maxWidth: .infinity)
        .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "In progress" : "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            .white
        case .status:
            .secondary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            .accentColor
        case .status:
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary:
            .black.opacity(0.24)
        case .status:
            .clear
        }
    }
}

enum FieldTripInlineTipsPresentation {
    static func shouldShow(
        levelNumber: Int,
        currentLevelNumber: Int,
        isTripComplete: Bool,
        hasGuide: Bool
    ) -> Bool {
        hasGuide && !isTripComplete && levelNumber == currentLevelNumber
    }
}

private struct FieldTripGuideScrollTarget: Hashable {
    let itemId: String
}

enum FieldTripsSection: String, CaseIterable, Identifiable {
    case fieldTrips
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldTrips:
            "Outings"
        case .seasonal:
            "Events"
        }
    }
}

private enum FieldTripScanPreviewLayout {
    static let tileSize: CGFloat = 96
    static let cornerRadius: CGFloat = 14
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 16
}

enum FieldTripScanPreviewResolvedLayout: Equatable {
    case fixedScrollable
    case equalWidthTwoUp
}

enum FieldTripScanPreviewPresentationMode: Equatable {
    case compactScrollable
    case responsiveCatalog

    func resolvedLayout(forTargetCount targetCount: Int) -> FieldTripScanPreviewResolvedLayout {
        if self == .responsiveCatalog, max(0, targetCount) == 2 {
            return .equalWidthTwoUp
        }
        return .fixedScrollable
    }
}

private enum FieldTripTemplateCardLayout {
    static let previewTileSize = FieldTripScanPreviewLayout.tileSize
    static let cornerRadius: CGFloat = 24
    static let outerHorizontalInset: CGFloat = 16
}

private enum FieldTripLevelHeaderLayout {
    static let accessorySize: CGFloat = 64
    static let ringLineWidth: CGFloat = 5.5
    static let ringLabelFontSize: CGFloat = 16
    static let artworkScale: CGFloat = 1.1
}

// Bundled objective artwork. Capture surfaces intentionally use only exact
// template mappings; richer Field trip grids may use semantic fallback art.
enum FieldTripObjectiveArtwork {
    static let imageNames = [
        "butterfly-monarch",
        "bird-cardinal",
        "cat",
        "spider",
        "frog",
        "mushroom"
    ]

    private static let backyardSafariImageNames = [
        "butterfly": "fieldtrip-backyard-butterfly",
        "bird": "fieldtrip-backyard-cardinal",
        "cat": "fieldtrip-backyard-cat",
        "spider": "fieldtrip-backyard-spider",
        "flowering plant": "fieldtrip-backyard-flowers",
        "fungus": "fieldtrip-backyard-mushrooms",
        "dog": "fieldtrip-backyard-dog",
        "domesticated animal": "fieldtrip-backyard-dog",
        "insect": "fieldtrip-backyard-bee",
        "urban wild animal": "fieldtrip-backyard-squirrel",
        "moss or lichen": "fieldtrip-backyard-moss"
    ]

    private static let parkPollinatorsImageNames = [
        "flowering plant": "fieldtrip-park-flowering-plant",
        "butterfly or moth": "fieldtrip-park-butterfly",
        "bee or wasp": "fieldtrip-park-bee",
        "fly": "fieldtrip-park-fly",
        "beetle": "fieldtrip-park-beetle",
        "spider": "fieldtrip-park-spider",
        "spider near flowers": "fieldtrip-park-spider",
        "seed or fruiting plant": "fieldtrip-park-seedpod",
        "bird": "fieldtrip-park-hummingbird",
        "bird near flowers": "fieldtrip-park-hummingbird",
        "wild plant": "fieldtrip-park-dandelion",
        "meadow plant": "fieldtrip-park-habitat",
        "pollinator habitat": "fieldtrip-park-habitat"
    ]

    static func imageName(
        for prompt: String,
        templateSlug: String?,
        fallbackIndex: Int
    ) -> String {
        let normalizedPrompt = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let exactImageName = exactImageName(for: prompt, templateSlug: templateSlug) {
            return exactImageName
        }

        if normalizedPrompt.contains("butterfly") { return "butterfly-monarch" }
        if normalizedPrompt.contains("bird") { return "bird-cardinal" }
        if normalizedPrompt.contains("cat") { return "cat" }
        if normalizedPrompt.contains("spider") { return "spider" }
        if normalizedPrompt.contains("frog") { return "frog" }
        if normalizedPrompt.contains("fungus") || normalizedPrompt.contains("mushroom") {
            return "mushroom"
        }

        return imageNames[fallbackIndex % imageNames.count]
    }

    static func exactImageName(for prompt: String, templateSlug: String?) -> String? {
        let normalizedPrompt = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if templateSlug == FieldTripTemplatePresentation.backyardSafariSlug {
            return backyardSafariImageNames[normalizedPrompt]
        }
        if templateSlug == FieldTripTemplatePresentation.parkPollinatorsSlug {
            return parkPollinatorsImageNames[normalizedPrompt]
        }
        return nil
    }
}

enum FieldTripLevelArtwork {
    static func imageName(templateSlug: String?, levelNumber: Int) -> String? {
        switch (templateSlug, levelNumber) {
        case (FieldTripTemplatePresentation.backyardSafariSlug, 1):
            "fieldtrip-backyard-level-1-patch"
        case (FieldTripTemplatePresentation.backyardSafariSlug, 2):
            "fieldtrip-backyard-level-2-patch"
        case (FieldTripTemplatePresentation.backyardSafariSlug, 3):
            "fieldtrip-backyard-level-3-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 1):
            "fieldtrip-park-level-1-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 2):
            "fieldtrip-park-level-2-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 3):
            "fieldtrip-park-level-3-patch"
        default:
            nil
        }
    }
}

struct FieldTripLevelArtworkGalleryItem: Identifiable, Equatable {
    let id: String
    let imageName: String
    let title: String
}

private struct FieldTripTemplateCard: View {
    let template: FieldTripTemplate
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void

    private var previewTargetCount: Int {
        FieldTripTemplatePresentation.targetCount(for: template)
    }

    private var previewItems: [FieldTripChecklistItem] {
        FieldTripTemplatePresentation.previewLevel(for: template)?.items ?? []
    }

    private var showsScanPreview: Bool {
        previewTargetCount > 0
    }

    private var status: FieldTripTemplateStatusPresentation {
        FieldTripTemplatePresentation.status(for: template)
    }

    private var title: String {
        FieldTripTemplatePresentation.title(template.title, slug: template.slug)
    }

    private var subtitle: String? {
        FieldTripTemplatePresentation.subtitle(for: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsScanPreview {
                FieldTripScanPreviewStrip(
                    targetCount: previewTargetCount,
                    templateSlug: template.slug,
                    items: previewItems,
                    localScansById: localScansById,
                    onOpenTemplate: onOpenTemplate,
                    onOpenCompletedScan: onOpenCompletedScan,
                    tileSize: FieldTripTemplateCardLayout.previewTileSize,
                    presentationMode: .responsiveCatalog
                )
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            Button(action: onOpenTemplate) {
                VStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, showsScanPreview ? 0 : 24)
            .padding(.bottom, 16)

            Button(action: onOpenTemplate) {
                Text(status.catalogActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(
                cornerRadius: FieldTripTemplateCardLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, FieldTripTemplateCardLayout.outerHorizontalInset)
    }
}

struct FieldTripLifecycleStatusBadge: View {
    let status: FieldTripTemplateStatusPresentation
    let accessibilityIdentifier: String

    init(
        status: FieldTripTemplateStatusPresentation,
        accessibilityIdentifier: String = "FieldTripDetailStatus"
    ) {
        self.status = status
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var indicatorColor: Color {
        switch status.kind {
        case .active, .completed:
            .green
        case .stopped:
            .orange
        case .notStarted, .locked:
            .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(status.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Field trip status")
        .accessibilityValue(status.title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct FieldTripTemplateDetailTagRow: View {
    let tags: [FieldTripTemplateTagPresentation]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 8, lineAlignment: .center) {
                ForEach(tags) { tag in
                    FieldTripTemplateTagPill(tag: tag)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FieldTripTemplateTagPill: View {
    let tag: FieldTripTemplateTagPresentation

    private var tint: Color {
        switch tag.kind {
        case .visibility where tag.title == "Published":
            .green
        case .access:
            .primary
        default:
            .secondary
        }
    }

    private var usesTintedSurface: Bool {
        tag.kind == .visibility
    }

    private var accessibilityLabel: String {
        switch tag.kind {
        case .access:
            "Access, \(tag.title)"
        case .difficulty:
            "Difficulty, \(tag.title)"
        case .level:
            "Current level, \(tag.title)"
        case .visibility:
            "Publication status, \(tag.title)"
        case .location:
            "Location, \(tag.title)"
        }
    }

    private var accessibilityHint: String {
        guard tag.kind == .visibility else { return "" }
        return tag.title == "Published"
            ? "A public snapshot of this outing is published."
            : "This outing has not been published."
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = tag.systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }

            Text(tag.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    usesTintedSurface
                        ? tint.opacity(tag.title == "Published" ? 0.16 : 0.12)
                        : Color(uiColor: .tertiarySystemGroupedBackground)
                )
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    usesTintedSurface ? tint.opacity(0.28) : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

enum FieldTripScanPreviewAction: Equatable {
    case openTemplate
    case openCompletedScan(String)

    static func resolve(completedScanId: String?, hasLocalScan: Bool) -> Self {
        guard let completedScanId, hasLocalScan else { return .openTemplate }
        return .openCompletedScan(completedScanId)
    }
}

struct FieldTripScanPreviewStrip: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let targetCount: Int
    let templateSlug: String
    let items: [FieldTripChecklistItem]
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void
    let tileSize: CGFloat
    let presentationMode: FieldTripScanPreviewPresentationMode

    init(
        targetCount: Int,
        templateSlug: String,
        items: [FieldTripChecklistItem],
        localScansById: [String: LocalScanRecord],
        onOpenTemplate: @escaping () -> Void,
        onOpenCompletedScan: @escaping (String) -> Void,
        tileSize: CGFloat = 96,
        presentationMode: FieldTripScanPreviewPresentationMode = .compactScrollable
    ) {
        self.targetCount = targetCount
        self.templateSlug = templateSlug
        self.items = items
        self.localScansById = localScansById
        self.onOpenTemplate = onOpenTemplate
        self.onOpenCompletedScan = onOpenCompletedScan
        self.tileSize = tileSize
        self.presentationMode = presentationMode
    }

    private var visibleTargetCount: Int {
        max(0, targetCount)
    }

    @ViewBuilder
    var body: some View {
        switch presentationMode.resolvedLayout(forTargetCount: visibleTargetCount) {
        case .fixedScrollable:
            fixedWidthStrip
        case .equalWidthTwoUp:
            equalWidthTwoUpStrip
        }
    }

    private var fixedWidthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(0..<visibleTargetCount, id: \.self) { index in
                    scanSlot(at: index)
                        .frame(width: tileSize, height: tileSize)
                }
            }
            .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
        }
        .frame(height: tileSize)
    }

    private var equalWidthTwoUpStrip: some View {
        HStack(spacing: FieldTripScanPreviewLayout.spacing) {
            ForEach(0..<visibleTargetCount, id: \.self) { index in
                scanSlot(at: index)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
    }

    private func scanSlot(at index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )
        let item = items.indices.contains(index) ? items[index] : nil
        let completedScan = item?.completedScanId.flatMap { localScansById[$0] }
        let action = FieldTripScanPreviewAction.resolve(
            completedScanId: item?.completedScanId,
            hasLocalScan: completedScan != nil
        )

        return Button {
            switch action {
            case .openTemplate:
                onOpenTemplate()
            case .openCompletedScan(let scanId):
                onOpenCompletedScan(scanId)
            }
        } label: {
            Group {
                if let completedScan {
                    ZStack {
                        Color(uiColor: .tertiarySystemGroupedBackground)

                        ScanThumbnail(
                            record: completedScan,
                            isOnline: offlineQueueManager.isOnline,
                            maxDimension: 300,
                            mediaBadgeAlignment: .topTrailing
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                } else {
                    Image(
                        FieldTripObjectiveArtwork.imageName(
                            for: item?.prompt ?? "",
                            templateSlug: templateSlug,
                            fallbackIndex: index
                        )
                    )
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(FieldTripObjectiveTipButtonStyle())
        .accessibilityLabel(item?.prompt ?? "Field trip goal")
        .accessibilityValue(item?.isCompleted == true ? "Completed" : "Not completed")
        .accessibilityHint(completedScan == nil ? "Open this field trip." : "Open this scan's insight.")
    }
}

private struct FieldTripChallengeCard: View {
    let challenge: FieldTripChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(1.3, contentMode: .fit)
                    .overlay {
                        FieldTripCoverImage(
                            urlString: challenge.coverImageUrl,
                            templateSlug: challenge.templateSlug
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                FieldTripChallengeStatusBadge(status: challenge.status)
                    .padding(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(challenge.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let subtitle = challenge.subtitle?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Label(
                            FieldTripTemplatePresentation.title(
                                challenge.templateTitle,
                                slug: challenge.templateSlug
                            ),
                            systemImage: "map"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }

                FieldTripTagRow(tags: Array((challenge.regionTags + challenge.seasonTags + challenge.habitatTags).prefix(4)))

                VStack(alignment: .leading, spacing: 8) {
                    Label(FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt), systemImage: "calendar")

                    HStack(spacing: 16) {
                        Label("\(challenge.participantCount.formatted()) joined", systemImage: "person.2")
                        Label("\(challenge.completionCount.formatted()) completed", systemImage: "rosette")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, challenge.viewerParticipation == nil ? 16 : 12)

            if let participation = challenge.viewerParticipation {
                FieldTripChallengeProgressBar(participation: participation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

private struct FieldTripChallengeStatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == "live" ? Color(uiColor: .systemBackground) : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(status == "live" ? Color.primary : Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private var label: String {
        switch status {
        case "live":
            "Live"
        case "upcoming":
            "Upcoming"
        case "ended":
            "Ended"
        default:
            status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct FieldTripChallengeStatsRow: View {
    let challenge: FieldTripChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt),
                    systemImage: "calendar",
                    tint: .blue
                )
                FieldTripMetadataPill(
                    title: "\(challenge.participantCount.formatted()) joined",
                    systemImage: "person.2",
                    tint: .cyan
                )
            }

            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: "\(challenge.completionCount.formatted()) completed",
                    systemImage: "rosette",
                    tint: .green
                )
                FieldTripMetadataPill(
                    title: "\(challenge.publishedEntryCount.formatted()) entries",
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
        }
    }
}

enum FieldTripLevelPresentationState: Equatable {
    case current
    case completed
    case locked

    static func resolve(
        levelNumber: Int,
        currentLevelNumber: Int,
        isTripComplete: Bool
    ) -> Self {
        if isTripComplete || levelNumber < currentLevelNumber {
            return .completed
        }
        if levelNumber == currentLevelNumber {
            return .current
        }
        return .locked
    }
}

enum FieldTripLevelStatusPresentation {
    static func status(
        for presentationState: FieldTripLevelPresentationState,
        currentStatus: FieldTripTemplateStatusPresentation
    ) -> FieldTripTemplateStatusPresentation {
        switch presentationState {
        case .current:
            currentStatus
        case .completed:
            .init(kind: .completed, title: "Completed")
        case .locked:
            .init(kind: .locked, title: "Locked")
        }
    }
}

enum FieldTripLevelGoalResolvedLayout: Equatable {
    case equalWidthGrid
    case fixedScrollable
}

enum FieldTripLevelGoalLayoutPresentation {
    static func resolvedLayout(forItemCount itemCount: Int) -> FieldTripLevelGoalResolvedLayout {
        max(0, itemCount) <= 2 ? .equalWidthGrid : .fixedScrollable
    }
}

enum FieldTripGoalTipSelection {
    static func defaultItemId(in items: [FieldTripChecklistItem]) -> String? {
        items.first(where: { !$0.isCompleted && $0.hasGuide })?.id
    }

    static func toggledSelection(
        currentItemId: String?,
        tappedItemId: String,
        hasGuide: Bool
    ) -> String? {
        guard hasGuide else { return currentItemId }
        return currentItemId == tappedItemId ? nil : tappedItemId
    }
}

struct FieldTripLevelProgressPresentation {
    let completedCount: Int
    let targetCount: Int
    let fractionComplete: Double
    let completionLabel: String?

    init(_ progress: FieldTripProgress) {
        completedCount = progress.completedCount
        targetCount = progress.targetCount
        fractionComplete = progress.fractionComplete
        completionLabel = nil
    }

    init(_ participation: FieldTripChallengeParticipation) {
        completedCount = participation.completedCount
        targetCount = participation.targetCount
        fractionComplete = participation.fractionComplete
        completionLabel = participation.isComplete ? "Badge earned" : nil
    }

    init(completedCount: Int, targetCount: Int) {
        self.completedCount = completedCount
        self.targetCount = targetCount
        if targetCount > 0 {
            fractionComplete = min(1, max(0, Double(completedCount) / Double(targetCount)))
        } else {
            fractionComplete = 0
        }
        completionLabel = nil
    }
}

enum FieldTripLevelProgressResolver {
    static func resolve(
        presentationState: FieldTripLevelPresentationState,
        currentProgress: FieldTripLevelProgressPresentation?,
        itemCount: Int,
        usesNumericRing: Bool
    ) -> FieldTripLevelProgressPresentation? {
        switch presentationState {
        case .current:
            if let currentProgress {
                return currentProgress
            }
            guard usesNumericRing else { return nil }
            return FieldTripLevelProgressPresentation(
                completedCount: 0,
                targetCount: max(0, itemCount)
            )
        case .completed:
            guard usesNumericRing else { return nil }
            let targetCount = max(0, itemCount)
            return FieldTripLevelProgressPresentation(
                completedCount: targetCount,
                targetCount: targetCount
            )
        case .locked:
            return nil
        }
    }
}

private enum FieldTripLevelProgressPlacement {
    case headerRing
    case bar
}

private struct FieldTripLevelsSection: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int
    let isTripComplete: Bool
    let status: FieldTripTemplateStatusPresentation?
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
    @Binding var expandedGuideItemId: String?
    let highlightedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(template.levels) { level in
                FieldTripLevelSection(
                    level: level,
                    templateSlug: template.slug,
                    presentationState: .resolve(
                        levelNumber: level.levelNumber,
                        currentLevelNumber: currentLevelNumber,
                        isTripComplete: isTripComplete
                    ),
                    templateStatus: status,
                    progress: progress(for: level),
                    progressPlacement: progressPlacement,
                    showsInlineTips: FieldTripInlineTipsPresentation.shouldShow(
                        levelNumber: level.levelNumber,
                        currentLevelNumber: currentLevelNumber,
                        isTripComplete: isTripComplete,
                        hasGuide: level.items.contains(where: \.hasGuide)
                    ),
                    expandedGuideItemId: $expandedGuideItemId,
                    highlightedGuideItemId: highlightedGuideItemId,
                    highlightedItemId: highlightedItemId,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: onOpenGuide
                )
            }
        }
    }

    private func progress(for level: FieldTripLevel) -> FieldTripLevelProgressPresentation? {
        let presentationState = FieldTripLevelPresentationState.resolve(
            levelNumber: level.levelNumber,
            currentLevelNumber: currentLevelNumber,
            isTripComplete: isTripComplete
        )

        return FieldTripLevelProgressResolver.resolve(
            presentationState: presentationState,
            currentProgress: progress,
            itemCount: level.items.count,
            usesNumericRing: progressPlacement == .headerRing
        )
    }
}

private struct FieldTripChallengeEntriesSection: View {
    let entries: [FieldTripChallengeEntry]
    let hasMoreEntries: Bool
    let isLoadingMore: Bool
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Challenge entries")
                .font(.headline.weight(.bold))

            if entries.isEmpty {
                Text("No published entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                ForEach(entries) { entry in
                    FieldTripChallengeEntryCard(
                        entry: entry,
                        onOpenEntry: onOpenEntry,
                        onOpenAuthorProfile: onOpenAuthorProfile
                    )
                }

                if hasMoreEntries {
                    Button(action: onLoadMore) {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text("Load more")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMore)
                }
            }
        }
    }
}

private struct FieldTripChallengeEntryCard: View {
    let entry: FieldTripChallengeEntry
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenEntry(entry.entryId)
            } label: {
                FieldTripCoverImage(
                    urlString: entry.coverImageUrl,
                    templateSlug: entry.templateSlug
                )
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Label("Field trip", systemImage: "map")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Button {
                    onOpenEntry(entry.entryId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(entry.challengeTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(entry)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(entry.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((entry.regionTags + entry.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(entry.itemCount)", systemImage: "leaf")
                    Label(entry.likeCount.formatted(), systemImage: "heart")
                    Label(entry.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenEntry(entry.entryId)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FieldTripCommunityPublicationCard: View {
    let publication: FieldTripRecentPublication
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                FieldTripCoverImage(
                    urlString: publication.coverImageUrl,
                    templateSlug: publication.slug
                )
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Button {
                    onOpenPublication(publication.publicationId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(publication.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(
                            FieldTripTemplatePresentation.title(
                                publication.templateTitle,
                                slug: publication.slug
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(publication)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(publication.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((publication.regionTags + publication.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(publication.itemCount)", systemImage: "leaf")
                    Label(publication.likeCount.formatted(), systemImage: "heart")
                    Label(publication.commentCount.formatted(), systemImage: "bubble.left")
                    if let reason = publication.communityReasonLabel {
                        Label(reason, systemImage: reason == "Following" ? "person.fill.checkmark" : "sparkle")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripCommunityPreviewSection: View {
    let publications: [FieldTripRecentPublication]
    let isLoading: Bool
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        if isLoading || !publications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Community")
                    .font(.headline.weight(.bold))

                if isLoading && publications.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        FieldTripRecentSkeletonCard()
                    }
                } else {
                    ForEach(publications) { publication in
                        FieldTripCommunityPublicationCard(
                            publication: publication,
                            onOpenPublication: onOpenPublication,
                            onOpenAuthorProfile: onOpenAuthorProfile
                        )
                    }
                }
            }
        }
    }
}

private struct FieldTripAboutOutingSection: View {
    let template: FieldTripTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldTripGuideRow(
                title: "How scans count",
                systemImage: "clock.arrow.circlepath",
                bodyText: """
                Only scans made once this outing starts count toward its goals. \
                Older scans—including anything already in your library when it starts—don’t qualify.
                """
            )

            if let whereToLook = template.guideWhereToLook {
                FieldTripGuideRow(
                    title: "Where to look",
                    systemImage: "binoculars",
                    bodyText: whereToLook
                )
            }

            if let whyItMatters = template.guideWhyItMatters {
                FieldTripGuideRow(
                    title: "Why it matters",
                    systemImage: "leaf",
                    bodyText: whyItMatters
                )
            }

            if let safety = template.guideSafetyEthics {
                FieldTripGuideRow(
                    title: "Safety",
                    systemImage: "hand.raised",
                    bodyText: safety
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldTripSelectedGoalTipsSection: View {
    let item: FieldTripChecklistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.prompt)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            ForEach(FieldTripObjectiveGuidePresentation.sections(for: item)) { section in
                FieldTripObjectiveGuideContentRow(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tips for \(item.prompt)")
    }
}

private struct FieldTripActiveLevelTipsSection: View {
    let level: FieldTripLevel
    let templateSlug: String
    @Binding var expandedItemId: String?
    let highlightedItemId: String?

    var body: some View {
        let guidedItems = Array(level.items.enumerated()).filter { $0.element.hasGuide }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(guidedItems, id: \.element.id) { index, item in
                FieldTripObjectiveGuideCard(
                    item: item,
                    imageName: FieldTripObjectiveArtwork.imageName(
                        for: item.prompt,
                        templateSlug: templateSlug,
                        fallbackIndex: index
                    ),
                    isExpanded: expandedItemId == item.id,
                    isHighlighted: highlightedItemId == item.id,
                    onToggle: {
                        HapticManager.shared.triggerSelectionPulse()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedItemId = expandedItemId == item.id ? nil : item.id
                        }
                    }
                )
                .id(FieldTripGuideScrollTarget(itemId: item.id))
            }
        }
    }
}

private struct FieldTripObjectiveGuideCard: View {
    let item: FieldTripChecklistItem
    let imageName: String
    let isExpanded: Bool
    let isHighlighted: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    FieldTripGuideArtworkContainer {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.prompt)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if let preview = item.guidePreview {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.prompt)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse tips." : "Expand tips.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    ForEach(guideSections) { section in
                        FieldTripObjectiveGuideContentRow(section: section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isHighlighted ? 2 : 1
                )
        }
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
    }

    private var guideSections: [FieldTripObjectiveGuideContentSection] {
        FieldTripObjectiveGuidePresentation.sections(for: item)
    }
}

private enum FieldTripObjectiveGuidePresentation {
    static func sections(
        for item: FieldTripChecklistItem
    ) -> [FieldTripObjectiveGuideContentSection] {
        if let guide = item.guide {
            let sections = [
                FieldTripObjectiveGuideContentSection(
                    title: "Where to look",
                    systemImage: "binoculars",
                    bodyText: guide.whereToLook
                ),
                FieldTripObjectiveGuideContentSection(
                    title: "Best conditions",
                    systemImage: "cloud.sun",
                    bodyText: guide.bestConditions
                ),
                FieldTripObjectiveGuideContentSection(
                    title: "What to notice",
                    systemImage: "eye",
                    bodyText: guide.whatToNotice
                ),
                FieldTripObjectiveGuideContentSection(
                    title: "Scan safely",
                    systemImage: "hand.raised",
                    bodyText: guide.scanSafely
                )
            ].compactMap { $0.nonEmpty }

            if !sections.isEmpty {
                return sections
            }
        }

        return [
            FieldTripObjectiveGuideContentSection(
                title: "Tip",
                systemImage: "lightbulb",
                bodyText: item.guideTip
            )
        ].compactMap { $0.nonEmpty }
    }
}

private struct FieldTripObjectiveGuideContentSection: Identifiable {
    let title: String
    let systemImage: String
    let bodyText: String?

    var id: String { title }

    var nonEmpty: Self? {
        guard let bodyText,
              !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return self
    }
}

private struct FieldTripObjectiveGuideContentRow: View {
    let section: FieldTripObjectiveGuideContentSection

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                if let bodyText = section.bodyText {
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FieldTripGuideRow: View {
    let title: String
    let systemImage: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(bodyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private enum FieldTripGuideArtworkContainerLayout {
    static let size: CGFloat = 58
    static let cornerRadius: CGFloat = 10
}

private struct FieldTripGuideArtworkContainer<Artwork: View>: View {
    let artwork: Artwork

    init(@ViewBuilder artwork: () -> Artwork) {
        self.artwork = artwork()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: FieldTripGuideArtworkContainerLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))

            artwork
        }
        .frame(
            width: FieldTripGuideArtworkContainerLayout.size,
            height: FieldTripGuideArtworkContainerLayout.size
        )
    }
}

private struct FieldTripLevelSection: View {
    let level: FieldTripLevel
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let templateStatus: FieldTripTemplateStatusPresentation?
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
    let showsInlineTips: Bool
    @Binding var expandedGuideItemId: String?
    let highlightedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @State private var isLevelArtworkExpanded = false

    private var rowStartIndices: [Int] {
        Array(stride(from: 0, to: level.items.count, by: 2))
    }

    private var levelArtworkImageName: String? {
        FieldTripLevelArtwork.imageName(
            templateSlug: templateSlug,
            levelNumber: level.levelNumber
        )
    }

    private var usesOutingPresentation: Bool {
        templateStatus != nil && progressPlacement == .headerRing
    }

    private var selectedGuideItem: FieldTripChecklistItem? {
        guard presentationState == .current,
              showsInlineTips,
              let expandedGuideItemId else {
            return nil
        }
        return level.items.first(where: { item in
            item.id == expandedGuideItemId && !item.isCompleted && item.hasGuide
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            levelHeader

            if progressPlacement == .bar, let progress {
                FieldTripLevelProgressBar(progress: progress)
            }

            if usesOutingPresentation {
                outingLevelContent
            } else {
                legacyLevelContent
            }
        }
        .padding(usesOutingPresentation ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var levelHeader: some View {
        if usesOutingPresentation {
            outingLevelHeader
        } else {
            legacyLevelHeader
        }
    }

    private var outingLevelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            levelPatchAccessory(reservesSpace: true)

            Spacer(minLength: 0)

            Text(level.title)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .layoutPriority(1)

            Spacer(minLength: 0)

            switch presentationState {
            case .current, .completed:
                if let progress {
                    progressRing(progress)
                } else {
                    trailingAccessorySpacer
                }
            case .locked:
                lockedIndicator
            }
        }
    }

    private var legacyLevelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            levelPatchAccessory(reservesSpace: false)

            VStack(alignment: .center, spacing: 8) {
                Text(level.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let description = level.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .layoutPriority(1)

            switch presentationState {
            case .current:
                if progressPlacement == .headerRing, let progress {
                    progressRing(progress)
                } else if levelArtworkImageName != nil {
                    trailingAccessorySpacer
                }
            case .completed:
                if progressPlacement == .headerRing, let progress {
                    progressRing(progress)
                } else {
                    Text("Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: FieldTripLevelHeaderLayout.accessorySize,
                            height: FieldTripLevelHeaderLayout.accessorySize
                        )
                }
            case .locked:
                lockedIndicator
            }
        }
    }

    private var outingLevelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldTripLevelGoalCollection(
                items: level.items,
                templateSlug: templateSlug,
                presentationState: presentationState,
                selectedGuideItemId: presentationState == .current
                    ? expandedGuideItemId
                    : nil,
                highlightedItemId: highlightedItemId,
                localScansById: localScansById,
                onOpenCompletedScan: onOpenCompletedScan,
                onOpenGuide: onOpenGuide
            )

            if let selectedGuideItem {
                FieldTripSelectedGoalTipsSection(item: selectedGuideItem)
                .id(FieldTripGuideScrollTarget(itemId: selectedGuideItem.id))
            }
        }
    }

    @ViewBuilder
    private var legacyLevelContent: some View {
        switch presentationState {
        case .current:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rowStartIndices, id: \.self) { startIndex in
                    FieldTripChecklistGridRow(
                        items: Array(
                            level.items[
                                startIndex..<min(startIndex + 2, level.items.count)
                            ]
                        ),
                        templateSlug: templateSlug,
                        fallbackStartIndex: startIndex,
                        highlightedItemId: highlightedItemId,
                        localScansById: localScansById,
                        onOpenCompletedScan: onOpenCompletedScan,
                        onOpenGuide: onOpenGuide
                    )
                }

                if showsInlineTips {
                    FieldTripActiveLevelTipsSection(
                        level: level,
                        templateSlug: templateSlug,
                        expandedItemId: $expandedGuideItemId,
                        highlightedItemId: highlightedGuideItemId
                    )
                }
            }
        case .completed, .locked:
            FieldTripCompactLevelStrip(
                items: level.items,
                templateSlug: templateSlug,
                presentationState: presentationState,
                localScansById: localScansById,
                onOpenCompletedScan: onOpenCompletedScan
            )
        }
    }

    @ViewBuilder
    private func levelPatchAccessory(reservesSpace: Bool) -> some View {
        if let levelArtworkImageName {
            Button {
                HapticManager.shared.triggerSelectionPulse()
                isLevelArtworkExpanded = true
            } label: {
                Image(levelArtworkImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: FieldTripLevelHeaderLayout.accessorySize,
                        height: FieldTripLevelHeaderLayout.accessorySize
                    )
                    .scaleEffect(FieldTripLevelHeaderLayout.artworkScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(level.title) patch")
            .accessibilityHint("Opens a larger, zoomable image")
            .fullScreenCover(isPresented: $isLevelArtworkExpanded) {
                FieldTripLevelArtworkExpandedView(
                    items: [
                        FieldTripLevelArtworkGalleryItem(
                            id: levelArtworkImageName,
                            imageName: levelArtworkImageName,
                            title: level.title
                        )
                    ],
                    initialItemID: levelArtworkImageName
                )
            }
        } else if reservesSpace {
            trailingAccessorySpacer
        }
    }

    private func progressRing(_ progress: FieldTripLevelProgressPresentation) -> some View {
        GoalProgressRing(
            completedCount: progress.completedCount,
            targetCount: progress.targetCount,
            lineWidth: FieldTripLevelHeaderLayout.ringLineWidth,
            labelFontSize: FieldTripLevelHeaderLayout.ringLabelFontSize,
            tint: usesOutingPresentation
                ? (progress.completedCount > 0 ? .green : .secondary)
                : .accentColor,
            showsCompletionCheckmark: !usesOutingPresentation
        )
        .frame(
            width: FieldTripLevelHeaderLayout.accessorySize,
            height: FieldTripLevelHeaderLayout.accessorySize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level progress")
        .accessibilityValue(
            "\(progress.completedCount) of \(progress.targetCount) goals complete"
        )
    }

    private var lockedIndicator: some View {
        ZStack {
            Circle()
                .stroke(
                    .secondary.opacity(0.28),
                    lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                )

            Image(systemName: "lock")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(2)
        .frame(
            width: FieldTripLevelHeaderLayout.accessorySize,
            height: FieldTripLevelHeaderLayout.accessorySize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked")
    }

    private var trailingAccessorySpacer: some View {
        Color.clear
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
            .accessibilityHidden(true)
    }
}

struct FieldTripLevelArtworkExpandedView: View {
    let items: [FieldTripLevelArtworkGalleryItem]
    let initialItemID: String
    let onOpenFieldTrip: ((FieldTripLevelArtworkGalleryItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?

    init(
        items: [FieldTripLevelArtworkGalleryItem],
        initialItemID: String,
        onOpenFieldTrip: ((FieldTripLevelArtworkGalleryItem) -> Void)? = nil
    ) {
        self.items = items
        self.initialItemID = initialItemID
        self.onOpenFieldTrip = onOpenFieldTrip
        _selectedItemID = State(initialValue: initialItemID)
    }

    private var selectedItem: FieldTripLevelArtworkGalleryItem? {
        items.first(where: { $0.id == selectedItemID })
            ?? items.first(where: { $0.id == initialItemID })
            ?? items.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(items) { item in
                            ZoomableScrollView(onSwipeDown: { dismiss() }) {
                                Image(item.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(24)
                                    .accessibilityLabel("\(item.title) patch")
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedItemID)
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 10) {
                        if let selectedItem {
                            Text(selectedItem.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }

                        if items.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(items) { item in
                                    Circle()
                                        .fill(
                                            item.id == selectedItem?.id
                                                ? Color.white
                                                : Color.white.opacity(0.35)
                                        )
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Patch \(selectedPageNumber) of \(items.count)")
                        }

                        Text(viewerHint)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { viewerToolbar }
            .onAppear {
                if !items.contains(where: { $0.id == selectedItemID }) {
                    selectedItemID = items.first?.id
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var viewerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .imageOverlayToolbarIconChrome(
                        isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                    )
            }
            .imageOverlayToolbarButtonChrome(
                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
            )
            .accessibilityLabel("Close patch viewer")
            .accessibilityIdentifier("FieldTripPatchViewerClose")
        }

        if onOpenFieldTrip != nil, selectedItem != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: openSelectedFieldTrip) {
                        Label("View field trip", systemImage: "binoculars")
                    }
                    .accessibilityIdentifier("FieldTripPatchViewerOpenFieldTrip")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                        )
                }
                .imageOverlayToolbarButtonChrome(
                    isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                )
                .accessibilityLabel("Patch options")
                .accessibilityIdentifier("FieldTripPatchViewerOptions")
            }
        }
    }

    private func openSelectedFieldTrip() {
        guard let selectedItem, let onOpenFieldTrip else { return }
        HapticManager.shared.triggerSelectionPulse()
        onOpenFieldTrip(selectedItem)
        dismiss()
    }

    private var selectedPageNumber: Int {
        guard let selectedItem,
              let index = items.firstIndex(where: { $0.id == selectedItem.id }) else {
            return items.isEmpty ? 0 : 1
        }
        return index + 1
    }

    private var viewerHint: String {
        if items.count > 1 {
            return "Swipe for more · Pinch or double-tap to zoom"
        }
        return "Pinch or double-tap to zoom"
    }
}

private enum FieldTripLevelGoalCollectionLayout {
    static let equalWidthSpacing: CGFloat = 16
    static let scrollSpacing = FieldTripScanPreviewLayout.spacing
    static let scrollTileSize: CGFloat = 120
}

private struct FieldTripLevelGoalCollection: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let selectedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    private var resolvedLayout: FieldTripLevelGoalResolvedLayout {
        FieldTripLevelGoalLayoutPresentation.resolvedLayout(forItemCount: items.count)
    }

    var body: some View {
        switch resolvedLayout {
        case .equalWidthGrid:
            HStack(alignment: .top, spacing: FieldTripLevelGoalCollectionLayout.equalWidthSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    goalTile(item: item, index: index)
                }

                if items.count == 1 {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        case .fixedScrollable:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: FieldTripLevelGoalCollectionLayout.scrollSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        goalTile(item: item, index: index)
                            .frame(
                                width: FieldTripLevelGoalCollectionLayout.scrollTileSize,
                                height: FieldTripLevelGoalCollectionLayout.scrollTileSize
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: FieldTripLevelGoalCollectionLayout.scrollTileSize)
            .padding(.horizontal, -16)
        }
    }

    private func goalTile(
        item: FieldTripChecklistItem,
        index: Int
    ) -> some View {
        FieldTripChecklistGridTile(
            item: item,
            imageName: FieldTripObjectiveArtwork.imageName(
                for: item.prompt,
                templateSlug: templateSlug,
                fallbackIndex: index
            ),
            presentationState: presentationState,
            isSelected: selectedGuideItemId == item.id,
            isHighlighted: highlightedItemId == item.id,
            showsInlineTitle: false,
            completedScan: item.completedScanId.flatMap { localScansById[$0] },
            onOpenCompletedScan: onOpenCompletedScan,
            onOpenGuide: onOpenGuide
        )
        .id(item.id)
    }
}

private struct FieldTripChecklistGridRow: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let fallbackStartIndex: Int
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                FieldTripChecklistGridTile(
                    item: item,
                    imageName: FieldTripObjectiveArtwork.imageName(
                        for: item.prompt,
                        templateSlug: templateSlug,
                        fallbackIndex: fallbackStartIndex + offset
                    ),
                    presentationState: .current,
                    isSelected: false,
                    isHighlighted: highlightedItemId == item.id,
                    showsInlineTitle: true,
                    completedScan: item.completedScanId.flatMap { localScansById[$0] },
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: onOpenGuide
                )
                .id(item.id)
            }

            if items.count == 1 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct FieldTripChecklistGridTile: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let item: FieldTripChecklistItem
    let imageName: String
    let presentationState: FieldTripLevelPresentationState
    let isSelected: Bool
    let isHighlighted: Bool
    let showsInlineTitle: Bool
    let completedScan: LocalScanRecord?
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @ViewBuilder
    var body: some View {
        if presentationState != .locked,
           let completedScanId = item.completedScanId,
           completedScan != nil {
            Button {
                onOpenCompletedScan(completedScanId)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open this scan's insight.")
        } else if presentationState == .current, !item.isCompleted, item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isSelected ? "Hide tips for this goal." : "Show tips for this goal.")
        } else {
            tileContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if presentationState != .locked, item.isCompleted, let completedScan {
            ZStack(alignment: .bottom) {
                ScanThumbnail(
                    record: completedScan,
                    isOnline: offlineQueueManager.isOnline,
                    maxDimension: 600,
                    mediaBadgeAlignment: .topTrailing
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInlineTitle {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(spacing: 2) {
                        Text(item.prompt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if let completedName = item.completedCommonName,
                           completedName.caseInsensitiveCompare(item.prompt) != .orderedSame {
                            Text(completedName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground)))
            .clipShape(tileShape)
            .overlay {
                tileShape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
        } else {
            VStack(alignment: .center, spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInlineTitle, presentationState != .locked, !isSelected {
                    Text(item.prompt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let completedName = item.completedCommonName {
                        Text(completedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground))
                }
            }
            .overlay {
                if isHighlighted {
                    tileShape.strokeBorder(Color.accentColor, lineWidth: 2)
                } else if isSelected {
                    tileShape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
            }
            .shadow(color: highlightShadowColor, radius: 8)
        }
    }

    private var usesHighlight: Bool {
        (isHighlighted || isSelected) && !item.isCompleted
    }

    private var highlightShadowColor: Color {
        isHighlighted && usesHighlight ? Color.accentColor.opacity(0.28) : .clear
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var accessibilityLabel: String {
        if presentationState == .locked {
            return "Locked goal"
        }
        if let completedName = item.completedCommonName {
            return "\(item.prompt), \(completedName)"
        }
        return item.prompt
    }

    private var accessibilityValue: String {
        if presentationState == .locked { return "Locked" }
        let completion = item.isCompleted ? "Completed" : "Not completed"
        return isSelected ? "\(completion), tips shown" : completion
    }

    private var accessibilityHint: String {
        presentationState == .locked
            ? "Complete the current level to unlock."
            : ""
    }
}

private struct FieldTripCompactLevelStrip: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    compactTile(item: item, index: index)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: FieldTripScanPreviewLayout.tileSize)
        .padding(.horizontal, -12)
    }

    @ViewBuilder
    private func compactTile(item: FieldTripChecklistItem, index: Int) -> some View {
        if presentationState == .completed,
           let completedScanId = item.completedScanId,
           localScansById[completedScanId] != nil {
            Button {
                onOpenCompletedScan(completedScanId)
            } label: {
                compactTileContent(item: item, index: index)
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: item))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open this scan's insight.")
        } else {
            compactTileContent(item: item, index: index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    @ViewBuilder
    private func compactTileContent(item: FieldTripChecklistItem, index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )

        if presentationState == .completed,
           let completedScanId = item.completedScanId,
           let completedScan = localScansById[completedScanId] {
            ZStack {
                Color(uiColor: .tertiarySystemGroupedBackground)

                ScanThumbnail(
                    record: completedScan,
                    isOnline: offlineQueueManager.isOnline,
                    maxDimension: 300,
                    mediaBadgeAlignment: .topTrailing
                )
            }
            .frame(
                width: FieldTripScanPreviewLayout.tileSize,
                height: FieldTripScanPreviewLayout.tileSize
            )
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            Image(
                FieldTripObjectiveArtwork.imageName(
                    for: item.prompt,
                    templateSlug: templateSlug,
                    fallbackIndex: index
                )
            )
                .resizable()
                .scaledToFit()
                .frame(
                    width: FieldTripScanPreviewLayout.tileSize,
                    height: FieldTripScanPreviewLayout.tileSize
                )
        }
    }

    private func accessibilityLabel(for item: FieldTripChecklistItem) -> String {
        if presentationState == .locked {
            return "Locked objective"
        }
        if let completedName = item.completedCommonName {
            return "\(item.prompt), \(completedName)"
        }
        return item.prompt
    }

    private var accessibilityValue: String {
        presentationState == .locked ? "Locked" : "Completed"
    }

    private var accessibilityHint: String {
        presentationState == .locked
            ? "Complete the current level to unlock."
            : ""
    }
}

private struct FieldTripObjectiveTipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FieldTripMetadataPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
            }
    }
}

private struct FieldTripTagRow: View {
    let tags: [String]

    private var displayTags: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    var body: some View {
        if !displayTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        Text(tag.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

struct FieldTripCoverImage: View {
    let urlString: String?
    let templateSlug: String?

    init(urlString: String?, templateSlug: String? = nil) {
        self.urlString = urlString
        self.templateSlug = templateSlug
    }

    var body: some View {
        if let imageName = FieldTripTemplatePresentation.bundledCoverImageName(for: templateSlug) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let url = SecureTransportPolicy.httpsURL(from: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "map")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldTripChallengeProgressBar: View {
    let participation: FieldTripChallengeParticipation

    var body: some View {
        FieldTripLevelProgressBar(
            progress: FieldTripLevelProgressPresentation(participation)
        )
    }
}

struct FieldTripLevelProgressBar: View {
    let progress: FieldTripLevelProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let completionLabel = progress.completionLabel {
                    Label(completionLabel, systemImage: "rosette")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(progress.completedCount)/\(max(progress.targetCount, 0))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * progress.fractionComplete))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct FieldTripChecklistRow: View {
    let item: FieldTripChecklistItem
    var showsGuide = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary.opacity(0.7))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let completedName = item.completedCommonName {
                    Text(completedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if showsGuide, let guideTip = item.guideTip {
                    Text(guideTip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct FieldTripPublishSheet: View {
    let template: FieldTripTemplate
    let onPublished: (FieldTripPublicationDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(template: FieldTripTemplate, onPublished: @escaping (FieldTripPublicationDetail) -> Void) {
        self.template = template
        self.onPublished = onPublished
        _title = State(
            initialValue: FieldTripTemplatePresentation.title(template.title, slug: template.slug)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Publish outing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func publish() async {
        guard let progress = template.viewerProgress else { return }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let publication = try await MerianNetworkClient.shared.publishFieldTrip(
                userFieldTripId: progress.userFieldTripId,
                title: title,
                description: description
            )
            HapticManager.shared.triggerSuccessPulse()
            onPublished(publication)
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct FieldTripChallengePublishSheet: View {
    let challenge: FieldTripChallenge
    let onPublished: (FieldTripChallengeEntryDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(challenge: FieldTripChallenge, onPublished: @escaping (FieldTripChallengeEntryDetail) -> Void) {
        self.challenge = challenge
        self.onPublished = onPublished
        _title = State(initialValue: challenge.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Publish Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func publish() async {
        guard let participation = challenge.viewerParticipation else { return }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let entry = try await MerianNetworkClient.shared.publishFieldTripChallengeEntry(
                participationId: participation.participationId,
                title: title,
                description: description
            )
            HapticManager.shared.triggerSuccessPulse()
            onPublished(entry)
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct FieldTripUnavailableCard: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: title,
            message: message
        ) {
            Button("Retry", action: retry)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
    }
}

private struct FieldTripTemplateSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(
                        cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                        style: .continuous
                    )
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
            .padding(.top, 24)
            .padding(.bottom, 16)

            VStack(alignment: .center, spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 220)
                    .frame(height: 34)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 15)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: 190)
                    .frame(height: 15)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(
                cornerRadius: FieldTripTemplateCardLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, FieldTripTemplateCardLayout.outerHorizontalInset)
        .redacted(reason: .placeholder)
    }
}

private struct FieldTripChallengeSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(1.3, contentMode: .fit)

                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 64, height: 25)
                    .padding(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 180, height: 20)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 132, height: 11)
                    }

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 8, height: 22)
                }

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 18)
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 58, height: 18)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 156, height: 11)

                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 82, height: 11)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 96, height: 11)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .redacted(reason: .placeholder)
    }
}

private struct FieldTripRecentSkeletonCard: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 160, height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 110, height: 11)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 90, height: 11)

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 18)
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 58, height: 18)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 138, height: 9)
            }

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 7, height: 13)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
    }
}

private enum FieldTripDetailSkeletonKind {
    case outing
    case event

    var isOuting: Bool {
        switch self {
        case .outing:
            true
        case .event:
            false
        }
    }

    var progressPlacement: FieldTripLevelProgressPlacement {
        switch self {
        case .outing:
            .headerRing
        case .event:
            .bar
        }
    }
}

private struct FieldTripTemplateDetailSkeleton: View {
    let kind: FieldTripDetailSkeletonKind
    var showsFeaturedMediaHero = false
    var onFeaturedHeroMaxYChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsFeaturedMediaHero {
                FieldTripFeaturedMediaSkeleton()
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(
                                    of: proxy.frame(
                                        in: .named(FieldTripFeaturedMediaLayout.scrollCoordinateSpace)
                                    ).maxY,
                                    initial: true
                                ) { _, newMaxY in
                                    onFeaturedHeroMaxYChange?(newMaxY)
                                }
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 24) {
                overview

                FieldTripExpandedLevelSkeleton(
                    progressPlacement: kind.progressPlacement,
                    showsSelectedGoalTips: kind.isOuting
                )
                FieldTripCompactLevelSkeleton(
                    progressPlacement: kind.progressPlacement
                )

                if kind.isOuting {
                    FieldTripCompactLevelSkeleton(
                        progressPlacement: kind.progressPlacement
                    )
                    FieldTripAboutOutingSkeleton()
                }
            }
            .padding(.horizontal, showsFeaturedMediaHero ? 16 : 0)
            .modifier(FieldTripHeroContentSheetModifier(
                isEnabled: showsFeaturedMediaHero
            ))
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var overview: some View {
        switch kind {
        case .outing:
            FieldTripOutingOverviewSkeleton()
        case .event:
            FieldTripEventOverviewSkeleton()
        }
    }
}

private struct FieldTripOutingOverviewSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            FieldTripDetailStatusSkeletonBadge()

            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 250, height: 34)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: 300)
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 230, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 76, height: 27)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 68, height: 27)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 82, height: 27)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            FieldTripDetailPrimaryActionSkeleton()
                .padding(.top, 12)
        }
        .padding(.vertical, 16)
    }
}

private struct FieldTripEventOverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(16 / 9, contentMode: .fit)

            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 220)
                    .frame(height: 30)

                Spacer(minLength: 8)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 58, height: 23)
            }

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 250, height: 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    metadataPill(width: 132)
                    metadataPill(width: 108)
                }

                HStack(spacing: 8) {
                    metadataPill(width: 124)
                    metadataPill(width: 96)
                }
            }
        }
    }

    private func metadataPill(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: width, height: 27)
    }
}

private struct FieldTripFeaturedMediaSkeleton: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            GlowPulsingSkeletonView(cornerRadius: 0)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                Circle()
                    .fill(Color.white.opacity(0.4))
                Circle()
                    .fill(Color.white.opacity(0.4))
            }
            .frame(width: 34, height: 6)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, FieldTripFeaturedMediaLayout.overlayBottomInset)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct FieldTripDetailStatusSkeletonBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 7, height: 7)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 54, height: 11)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FieldTripDetailPrimaryActionSkeleton: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.14))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct FieldTripHeroContentSheetModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(.top, FieldTripFeaturedMediaLayout.contentTopSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: FieldTripFeaturedMediaLayout.contentOverlap,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: FieldTripFeaturedMediaLayout.contentOverlap
                    )
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                    .padding(.bottom, -1000)
                )
                .offset(y: -FieldTripFeaturedMediaLayout.contentOverlap)
                .padding(.bottom, -FieldTripFeaturedMediaLayout.contentOverlap)
                .zIndex(1)
        } else {
            content
        }
    }
}

private struct FieldTripExpandedLevelSkeleton: View {
    let progressPlacement: FieldTripLevelProgressPlacement
    let showsSelectedGoalTips: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch progressPlacement {
            case .headerRing:
                FieldTripOutingLevelHeaderSkeleton(trailingAccessory: .progressRing)
            case .bar:
                FieldTripLevelHeaderSkeleton(
                    trailingAccessory: expandedHeaderAccessory
                )
            }

            if case .bar = progressPlacement {
                progressBar
            }

            switch progressPlacement {
            case .headerRing:
                HStack(spacing: FieldTripLevelGoalCollectionLayout.equalWidthSpacing) {
                    FieldTripGoalTileSkeleton(
                        isSelected: showsSelectedGoalTips,
                        showsInlineTitle: false
                    )
                    FieldTripGoalTileSkeleton(showsInlineTitle: false)
                }
            case .bar:
                VStack(spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 16) {
                            ForEach(0..<2, id: \.self) { _ in
                                FieldTripGoalTileSkeleton()
                            }
                        }
                    }
                }
            }

            if showsSelectedGoalTips {
                FieldTripSelectedGoalTipsSkeleton()
            }
        }
        .padding(cardPadding)
        .background(
            levelCardShape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var expandedHeaderAccessory: FieldTripLevelHeaderSkeleton.TrailingAccessory {
        switch progressPlacement {
        case .headerRing:
            .progressRing
        case .bar:
            .balancedSpacer
        }
    }

    private var cardPadding: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 52, height: 11)

                Spacer()

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 28, height: 11)
            }

            Capsule()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 7)
        }
    }

    private var levelCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

private struct FieldTripGoalTileSkeleton: View {
    var isSelected = false
    var showsInlineTitle = true

    var body: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .padding(8)
            } else if showsInlineTitle {
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 72, height: 14)
                }
                .padding(10)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct FieldTripSelectedGoalTipsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 118, height: 24)

            ForEach(0..<4, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: index.isMultiple(of: 2) ? 112 : 128, height: 13)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: index.isMultiple(of: 2) ? 206 : 174, height: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct FieldTripAboutOutingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: index == 0 ? 132 : 104, height: 14)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: index == 1 ? 184 : 224, height: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }
}

private struct FieldTripCompactLevelSkeleton: View {
    let progressPlacement: FieldTripLevelProgressPlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch progressPlacement {
            case .headerRing:
                FieldTripOutingLevelHeaderSkeleton(trailingAccessory: .lockedRing)
            case .bar:
                FieldTripLevelHeaderSkeleton(
                    trailingAccessory: compactHeaderAccessory
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(
                            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                            style: .continuous
                        )
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(
                            width: tileSize,
                            height: tileSize
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                                style: .continuous
                            )
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .scrollDisabled(true)
            .frame(height: tileSize)
            .padding(.horizontal, -horizontalInset)
        }
        .padding(cardPadding)
        .background(
            levelCardShape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var compactHeaderAccessory: FieldTripLevelHeaderSkeleton.TrailingAccessory {
        switch progressPlacement {
        case .headerRing:
            .lockedRing
        case .bar:
            .completionLabel
        }
    }

    private var tileSize: CGFloat {
        switch progressPlacement {
        case .headerRing:
            FieldTripLevelGoalCollectionLayout.scrollTileSize
        case .bar:
            FieldTripScanPreviewLayout.tileSize
        }
    }

    private var horizontalInset: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var cardPadding: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var levelCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

private struct FieldTripOutingLevelHeaderSkeleton: View {
    enum TrailingAccessory {
        case progressRing
        case lockedRing
    }

    let trailingAccessory: TrailingAccessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 112, height: 28)

            Spacer(minLength: 0)

            trailingAccessoryView
        }
    }

    @ViewBuilder
    private var trailingAccessoryView: some View {
        switch trailingAccessory {
        case .progressRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 30, height: 14)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
        case .lockedRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 14, height: 18)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
        }
    }
}

private struct FieldTripLevelHeaderSkeleton: View {
    enum TrailingAccessory {
        case progressRing
        case lockedRing
        case balancedSpacer
        case completionLabel
    }

    let trailingAccessory: TrailingAccessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

            VStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 112, height: 20)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: 164)
                    .frame(height: 11)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            trailingAccessoryView
        }
    }

    @ViewBuilder
    private var trailingAccessoryView: some View {
        switch trailingAccessory {
        case .progressRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 30, height: 14)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )

        case .lockedRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 14, height: 18)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )

        case .balancedSpacer:
            Color.clear
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

        case .completionLabel:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 48, height: 12)
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )
        }
    }
}

private enum FieldTripDisplayDate {
    static func shortDate(_ rawValue: String) -> String {
        guard let date = date(from: rawValue) else { return rawValue }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func shortRange(start: String, end: String) -> String {
        guard let startDate = date(from: start),
              let endDate = date(from: end) else {
            return "\(start) - \(end)"
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)
        let formatter = DateFormatter()
        formatter.timeStyle = .none

        if startComponents.year == endComponents.year,
           startComponents.month == endComponents.month {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: startDate))-\(calendar.component(.day, from: endDate))"
        }

        formatter.dateFormat = "MMM d"
        let startLabel = formatter.string(from: startDate)
        let endLabel = formatter.string(from: endDate)
        return "\(startLabel)-\(endLabel)"
    }

    private static func date(from rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
