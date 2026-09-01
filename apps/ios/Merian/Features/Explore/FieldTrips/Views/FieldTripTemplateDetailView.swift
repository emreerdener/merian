import SwiftData
import SwiftUI

struct FieldTripTemplateDetailView: View {
    let reference: FieldTripTemplateReference
    let focusedChecklistItemId: String?
    let onOpenCompletedScan: (String) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Query private var localScans: [LocalScanRecord]
    @State private var viewModel: FieldTripTemplateDetailViewModel
    @State private var publishingTemplate: FieldTripTemplate?
    @State private var expandedGuideItemId: String?
    @State private var pendingGuideItemId: String?
    @State private var highlightedGuideItemId: String?
    @State private var pendingGoalItemId: String?
    @State private var highlightedGoalItemId: String?
    @State private var guideHighlightTask: Task<Void, Never>?
    @State private var goalHighlightTask: Task<Void, Never>?
    @State private var didApplyInitialFocus = false
    @State private var defaultGuideSelectionKey: String?
    @State private var lifecycleConfirmation: FieldTripLifecycleConfirmation?
    @State private var unavailableFeaturedMediaSourceIdentifiers: Set<String> = []
    @State private var featuredMediaGalleryPresentation: MediaGalleryPresentation?
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
        _viewModel = State(
            initialValue: FieldTripTemplateDetailViewModel(reference: reference)
        )
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
                if viewModel.isLoading && viewModel.template == nil {
                    FieldTripTemplateDetailSkeleton(
                        kind: .outing,
                        showsFeaturedMediaHero: showsFeaturedMediaLoadingSkeleton,
                        onFeaturedHeroMaxYChange: { maxY in
                            updateFeaturedHeroScrollEdgeEffect(maxY: maxY)
                        }
                    )
                    .padding(.horizontal, showsFeaturedMediaLoadingSkeleton ? 0 : 16)
                    .padding(.vertical, showsFeaturedMediaLoadingSkeleton ? 0 : 16)
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.template == nil {
                    FieldTripUnavailableCard(
                        title: "Field trip unavailable",
                        message: errorMessage
                    ) {
                        Task { await load(force: true) }
                    }
                    .padding(16)
                } else if let template = viewModel.template {
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
                goalHighlightTask?.cancel()
                goalHighlightTask = nil
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .fieldTripProgressInvalidated(let templateIds) = event,
                      let resolvedTemplateId = viewModel.template?.templateId,
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
                FullscreenMediaGallery(presentation: presentation)
            }
            .alert(item: $lifecycleConfirmation) { confirmation in
                lifecycleAlert(for: confirmation)
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
                    highlightedItemId: highlightedGoalItemId,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: { item in
                        openGuide(item, scrollProxy: scrollProxy)
                    }
                )
                .onAppear {
                    consumePendingGoalScroll(with: scrollProxy)
                    consumePendingGuideScroll(with: scrollProxy)
                }

                FieldTripCommunityPreviewSection(
                    publications: viewModel.communityPreview,
                    isLoading: viewModel.isLoadingCommunityPreview,
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
            featuredItemCount: viewModel.template.map {
                featuredMediaItems(for: $0).count
            } ?? 0
        )
    }

    private var showsFeaturedMediaLoadingSkeleton: Bool {
        FieldTripDetailLoadingPresentation.showsFeaturedMediaHero(
            isLoading: viewModel.isLoading,
            hasTemplate: viewModel.template != nil
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

    private func consumePendingGoalScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingGoalItemId else { return }
        pendingGoalItemId = nil
        highlightedGoalItemId = itemId

        goalHighlightTask?.cancel()
        goalHighlightTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, highlightedGoalItemId == itemId else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(itemId, anchor: .center)
            }
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            guard !Task.isCancelled, highlightedGoalItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedGoalItemId = nil
            }
            goalHighlightTask = nil
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
            pendingGoalItemId = item.id
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
        if let template = viewModel.template,
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
        .disabled(viewModel.isLifecycleMutating)
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
                isEnabled: !viewModel.isLifecycleMutating
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
                isLoading: viewModel.isStarting,
                isEnabled: !viewModel.isLifecycleMutating
            ) {
                Task { await viewModel.start(template) }
            }
        case .resume:
            FieldTripDetailPrimaryActionBar(
                title: "Resume",
                systemImage: "play.fill",
                isLoading: viewModel.isStarting,
                isEnabled: !viewModel.isLifecycleMutating
            ) {
                Task { await viewModel.start(template) }
            }
        case .publish:
            FieldTripDetailPrimaryActionBar(
                title: "Publish",
                systemImage: "square.and.arrow.up",
                isEnabled: !viewModel.isLifecycleMutating
            ) {
                publishingTemplate = template
            }
        case .scan:
            FieldTripDetailPrimaryActionBar(
                title: "Start scanning",
                systemImage: nil,
                isEnabled: !viewModel.isLifecycleMutating
            ) {
                openScanner()
            }
        }
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
                    guard let template = viewModel.template else { return }
                    Task { await viewModel.stop(template) }
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
                    guard let template = viewModel.template else { return }
                    Task { await viewModel.reset(template) }
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
        await viewModel.load(force: force) { loadedTemplate in
            applyInitialFocusIfNeeded(to: loadedTemplate)
            applyDefaultGuideSelectionIfNeeded(to: loadedTemplate)
        }
    }
}
