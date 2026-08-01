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

    static func statusTitle(for template: FieldTripTemplate) -> String {
        if template.isStopped {
            return "Stopped"
        }

        switch template.catalogState {
        case .completed:
            return "Completed"
        case .inProgress:
            return "Active"
        case .incomplete:
            return "Not started"
        }
    }

    static func cardTags(
        for template: FieldTripTemplate,
        locationLabel: String?,
        sharingEnabled: Bool = FieldTripSharingAvailability.isEnabled
    ) -> [FieldTripTemplateTagPresentation] {
        var tags: [FieldTripTemplateTagPresentation] = []

        tags.append(.init(
            kind: .status,
            title: statusTitle(for: template)
        ))

        if sharingEnabled, let progress = template.viewerProgress {
            if progress.isPublished {
                tags.append(.init(kind: .visibility, title: "Public", systemImage: "eye.fill"))
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

struct FieldTripTemplateTagPresentation: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case status
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

    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Query private var localScans: [LocalScanRecord]
    @State private var viewModel = FieldTripsViewModel()
    @State private var filters = FieldTripCatalogFilters()
    @State private var isShowingFilterSheet = false
    @State private var cardLocationLabel: String?

    private var eventsEnabled: Bool {
        FieldTripEventsAvailability.isEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            switch eventsEnabled ? selectedSection : .fieldTrips {
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
        .task(id: eventsEnabled) {
            if !eventsEnabled, selectedSection == .seasonal {
                selectedSection = .fieldTrips
            }
            await viewModel.load(userRegion: userRegion, eventsEnabled: eventsEnabled)
        }
        .task(id: environmentContextManager.locationAuthorizationStatus) {
            let locationName = await environmentContextManager.currentAuthorizedLocationName()
            guard !Task.isCancelled else { return }
            cardLocationLabel = locationName
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .fieldTripProgressUpdated:
                Task {
                    await viewModel.refresh(userRegion: userRegion, eventsEnabled: eventsEnabled)
                }
            case .captureGoalContextInvalidated(let source) where source == .fieldTrip:
                Task {
                    await viewModel.refresh(userRegion: userRegion, eventsEnabled: eventsEnabled)
                }
            case .fieldTripChallengeProgressUpdated where eventsEnabled:
                Task {
                    await viewModel.refresh(userRegion: userRegion, eventsEnabled: true)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
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
                                    locationLabel: cardLocationLabel,
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

struct FieldTripTemplateDetailView: View {
    let reference: FieldTripTemplateReference
    let focusedChecklistItemId: String?
    let onOpenCompletedScan: (String) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

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
    @State private var toastMessage: String?
    @State private var selectedDetailSection: FieldTripDetailSection = .objectives
    @State private var expandedGuideItemId: String?
    @State private var pendingGuideItemId: String?
    @State private var highlightedGuideItemId: String?
    @State private var pendingObjectiveItemId: String?
    @State private var highlightedObjectiveItemId: String?
    @State private var didApplyInitialFocus = false
    @State private var lifecycleConfirmation: FieldTripLifecycleConfirmation?

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
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                if isLoading && template == nil {
                    FieldTripTemplateDetailSkeleton(showsCoverImage: false)
                        .padding(16)
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
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(
                template.map { FieldTripTemplatePresentation.title($0.title, slug: $0.slug) }
                    ?? (isLoading ? "Loading..." : "Field trip")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let template,
                   let primaryAction = FieldTripDetailLifecyclePresentation.primaryAction(
                       for: template
                   ) {
                    primaryActionBar(template, action: primaryAction)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(.bar)
                }
            }
            .task {
                await load(force: false)
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                guard case .fieldTripProgressUpdated(let updates) = event,
                      let resolvedTemplateId = template?.templateId,
                      updates.contains(where: { $0.templateId == resolvedTemplateId }) else {
                    return
                }
                Task { await load(force: true) }
            }
            .sheet(item: $publishingTemplate) { template in
                FieldTripPublishSheet(template: template) { publication in
                    publishingTemplate = nil
                    onOpenPublication(publication.publicationId)
                    Task { await load(force: true) }
                }
            }
            .alert(item: $lifecycleConfirmation) { confirmation in
                lifecycleAlert(for: confirmation)
            }
            .merianSystemFeedback(
                toastMessage: Binding(
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
        switch selectedDetailSection {
        case .objectives:
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    if FieldTripSharingAvailability.isEnabled,
                       let progress = template.viewerProgress {
                        FieldTripPublicationStatusBadge(isPublished: progress.isPublished)
                    }

                    Text(FieldTripTemplatePresentation.title(template.title, slug: template.slug))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = template.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FieldTripLevelsSection(
                    template: template,
                    currentLevelNumber: template.viewerProgress?.currentLevelNumber ?? 1,
                    isTripComplete: template.viewerProgress?.isComplete ?? false,
                    progress: template.viewerProgress.map(FieldTripLevelProgressPresentation.init),
                    progressPlacement: .headerRing,
                    highlightedItemId: highlightedObjectiveItemId,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: openGuide
                )
                .onAppear {
                    consumePendingObjectiveScroll(with: scrollProxy)
                }

                FieldTripCommunityPreviewSection(
                    publications: communityPreview,
                    isLoading: isLoadingCommunityPreview,
                    onOpenPublication: onOpenPublication,
                    onOpenAuthorProfile: onOpenAuthorProfile
                )
            }
        case .tips:
            FieldTripGuideSections(
                template: template,
                currentLevelNumber: template.viewerProgress?.currentLevelNumber ?? 1,
                isTripComplete: template.viewerProgress?.isComplete ?? false,
                expandedItemId: $expandedGuideItemId,
                highlightedItemId: highlightedGuideItemId
            )
            .onAppear {
                consumePendingGuideScroll(with: scrollProxy)
            }
        }
    }

    private func openGuide(_ item: FieldTripChecklistItem) {
        guard item.hasGuide else { return }
        HapticManager.shared.triggerSelectionPulse()
        expandedGuideItemId = item.id
        pendingGuideItemId = item.id
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDetailSection = .tips
        }
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    private func consumePendingGuideScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingGuideItemId else { return }
        pendingGuideItemId = nil
        highlightedGuideItemId = itemId

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(itemId, anchor: .top)
            }
            try? await Task.sleep(for: .seconds(1.2))
            guard highlightedGuideItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedGuideItemId = nil
            }
        }
    }

    private func consumePendingObjectiveScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingObjectiveItemId else { return }
        pendingObjectiveItemId = nil
        highlightedObjectiveItemId = itemId

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(itemId, anchor: .center)
            }
            try? await Task.sleep(for: .seconds(1.2))
            guard highlightedObjectiveItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedObjectiveItemId = nil
            }
        }
    }

    private func applyInitialFocusIfNeeded(to template: FieldTripTemplate) {
        guard !didApplyInitialFocus,
              let focusedChecklistItemId,
              let item = template.levels
                .flatMap(\.items)
                .first(where: { $0.id == focusedChecklistItemId }) else {
            return
        }
        didApplyInitialFocus = true

        switch FieldTripFocusedTargetPresentation.resolve(hasGuide: item.hasGuide) {
        case .tips:
            expandedGuideItemId = item.id
            pendingGuideItemId = item.id
            selectedDetailSection = .tips
        case .objectives:
            pendingObjectiveItemId = item.id
            selectedDetailSection = .objectives
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if template != nil {
            ToolbarItem(placement: .principal) {
                FieldTripDetailToolbarPicker(
                    label: "Field trip details",
                    selection: $selectedDetailSection
                )
            }
        }

        if let template {
            if FieldTripDetailLifecyclePresentation.showsOptionsMenu(template) {
                ToolbarItem(placement: .topBarTrailing) {
                    lifecycleOptionsMenu(template)
                }
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

            if FieldTripDetailLifecyclePresentation.canStop(template),
               FieldTripDetailLifecyclePresentation.canReset(template) {
                Divider()
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
                AppEventPublisher.shared.send(.triggerPaywall)
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
        AppEventPublisher.shared.send(.requestOpenScanner)
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
                toastMessage = "Field trip resumed."
            }
            AppEventPublisher.shared.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
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
            toastMessage = "Field trip stopped. Your progress is saved."
            AppEventPublisher.shared.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
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
            toastMessage = "Field trip reset."
            AppEventPublisher.shared.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
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
    @State private var selectedDetailSection: FieldTripDetailSection = .objectives
    @State private var expandedGuideItemId: String?
    @State private var pendingGuideItemId: String?
    @State private var highlightedGuideItemId: String?

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
                    FieldTripTemplateDetailSkeleton(showsCoverImage: true)
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
            .toolbar { detailToolbar }
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
            .refreshable {
                await viewModel.refresh()
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                guard case .fieldTripChallengeProgressUpdated(let updates) = event,
                      updates.contains(where: { $0.challengeId == challengeId }) else {
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
                toastMessage: Binding(
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
            switch selectedDetailSection {
            case .objectives:
                VStack(alignment: .leading, spacing: 24) {
                    challengeOverview(challenge)

                    FieldTripLevelsSection(
                        template: template,
                        currentLevelNumber: challenge.viewerParticipation?.currentLevelNumber ?? 1,
                        isTripComplete: challenge.viewerParticipation?.isComplete ?? false,
                        progress: challenge.viewerParticipation.map(FieldTripLevelProgressPresentation.init),
                        progressPlacement: .bar,
                        highlightedItemId: nil,
                        localScansById: [:],
                        onOpenCompletedScan: { _ in },
                        onOpenGuide: openGuide
                    )

                    challengeEntriesSection
                }
            case .tips:
                FieldTripGuideSections(
                    template: template,
                    currentLevelNumber: challenge.viewerParticipation?.currentLevelNumber ?? 1,
                    isTripComplete: challenge.viewerParticipation?.isComplete ?? false,
                    expandedItemId: $expandedGuideItemId,
                    highlightedItemId: highlightedGuideItemId
                )
                .onAppear {
                    consumePendingGuideScroll(with: scrollProxy)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                challengeOverview(challenge)
                challengeEntriesSection
            }
        }
    }

    private func openGuide(_ item: FieldTripChecklistItem) {
        guard item.hasGuide else { return }
        HapticManager.shared.triggerSelectionPulse()
        expandedGuideItemId = item.id
        pendingGuideItemId = item.id
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDetailSection = .tips
        }
    }

    private func consumePendingGuideScroll(with scrollProxy: ScrollViewProxy) {
        guard let itemId = pendingGuideItemId else { return }
        pendingGuideItemId = nil
        highlightedGuideItemId = itemId

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(itemId, anchor: .top)
            }
            try? await Task.sleep(for: .seconds(1.2))
            guard highlightedGuideItemId == itemId else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedGuideItemId = nil
            }
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

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if viewModel.challenge?.template != nil {
            ToolbarItem(placement: .principal) {
                FieldTripDetailToolbarPicker(
                    label: "Challenge details",
                    selection: $selectedDetailSection
                )
            }
        }

    }

    @ViewBuilder
    private func primaryActionBar(_ challenge: FieldTripChallenge) -> some View {
        if !challenge.viewerHasAccess {
            FieldTripDetailPrimaryActionBar(
                title: "Unlock with Pro",
                systemImage: "lock.fill"
            ) {
                AppEventPublisher.shared.send(.triggerPaywall)
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
        AppEventPublisher.shared.send(.requestOpenScanner)
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
}

private struct FieldTripDetailToolbarPicker: View {
    let label: String
    @Binding var selection: FieldTripDetailSection

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(FieldTripDetailSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 1)
        .background(Capsule().fill(.regularMaterial))
        .clipShape(Capsule())
        .frame(width: 200)
        .onChange(of: selection) { _, _ in
            HapticManager.shared.triggerSelectionPulse(
                source: "fieldTrips.detail.section"
            )
        }
    }
}

enum FieldTripFocusedTargetPresentation: Equatable {
    case tips
    case objectives

    static func resolve(hasGuide: Bool) -> Self {
        hasGuide ? .tips : .objectives
    }
}

private enum FieldTripDetailSection: String, CaseIterable, Identifiable {
    case objectives
    case tips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .objectives:
            "Goals"
        case .tips:
            "Tips"
        }
    }
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

    static func availableSections(eventsEnabled: Bool) -> [Self] {
        eventsEnabled ? allCases : [.fieldTrips]
    }
}

private enum FieldTripScanPreviewLayout {
    static let tileSize: CGFloat = 96
    static let cornerRadius: CGFloat = 14
    static let spacing: CGFloat = 10
    static let imagePadding: CGFloat = 12
}

private enum FieldTripLevelHeaderLayout {
    static let accessorySize: CGFloat = 52
    static let ringLineWidth: CGFloat = 4.5
    static let ringLabelFontSize: CGFloat = 11
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
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 1):
            "fieldtrip-park-level-1-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 2):
            "fieldtrip-park-level-2-patch"
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
    let locationLabel: String?
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

    private var currentLevelPatchImageName: String? {
        guard let currentLevel = FieldTripTemplatePresentation.currentLevel(for: template) else { return nil }
        return FieldTripLevelArtwork.imageName(
            templateSlug: template.slug,
            levelNumber: currentLevel.levelNumber
        )
    }

    private var tags: [FieldTripTemplateTagPresentation] {
        FieldTripTemplatePresentation.cardTags(
            for: template,
            locationLabel: locationLabel
        )
    }

    private var ctaTitle: String {
        switch template.catalogState {
        case .completed:
            "View field trip"
        case .inProgress:
            "Continue field trip"
        case .incomplete:
            "View field trip"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenTemplate) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(FieldTripTemplatePresentation.title(template.title, slug: template.slug))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let subtitle = FieldTripTemplatePresentation.subtitle(for: template) {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if let currentLevelPatchImageName {
                        Image(currentLevelPatchImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .scaleEffect(1.08)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if showsScanPreview {
                FieldTripScanPreviewStrip(
                    targetCount: previewTargetCount,
                    templateSlug: template.slug,
                    items: previewItems,
                    localScansById: localScansById,
                    onOpenTemplate: onOpenTemplate,
                    onOpenCompletedScan: onOpenCompletedScan
                )
                .padding(.bottom, 12)
            }

            FieldTripTemplateTagRow(tags: tags)
                .padding(.bottom, 12)

            if template.catalogState == .incomplete {
                Button(action: onOpenTemplate) {
                    Text(ctaTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Button(action: onOpenTemplate) {
                    Text(ctaTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            Color(uiColor: .secondarySystemGroupedBackground)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
    }
}

private struct FieldTripTemplateTagRow: View {
    let tags: [FieldTripTemplateTagPresentation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        if let systemImage = tag.systemImage {
                            Image(systemName: systemImage)
                                .font(.caption2.weight(.bold))
                        }

                        Text(tag.title)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tag.kind == .access ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
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
    let targetCount: Int
    let templateSlug: String
    let items: [FieldTripChecklistItem]
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void

    private var visibleTargetCount: Int {
        max(0, targetCount)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(0..<visibleTargetCount, id: \.self) { index in
                    scanSlot(at: index)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: FieldTripScanPreviewLayout.tileSize)
    }

    @ViewBuilder
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

        Button {
            switch action {
            case .openTemplate:
                onOpenTemplate()
            case .openCompletedScan(let scanId):
                onOpenCompletedScan(scanId)
            }
        } label: {
            ZStack {
                Color(uiColor: .tertiarySystemGroupedBackground)

                if let completedScan {
                    ScanThumbnail(
                        record: completedScan,
                        maxDimension: 300,
                        mediaBadgeAlignment: .topTrailing
                    )
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
                        .padding(FieldTripScanPreviewLayout.imagePadding)
                }
            }
            .frame(
                width: FieldTripScanPreviewLayout.tileSize,
                height: FieldTripScanPreviewLayout.tileSize
            )
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
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

private enum FieldTripLevelPresentationState: Equatable {
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

private enum FieldTripLevelProgressPlacement {
    case headerRing
    case bar
}

private struct FieldTripLevelsSection: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int
    let isTripComplete: Bool
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
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
                    progress: progress(for: level),
                    progressPlacement: progressPlacement,
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

        if presentationState == .current, let progress {
            return progress
        }

        guard progressPlacement == .headerRing, presentationState != .locked else {
            return nil
        }

        let completedCount = presentationState == .completed
            ? level.items.count
            : level.items.filter(\.isCompleted).count

        return FieldTripLevelProgressPresentation(
            completedCount: completedCount,
            targetCount: level.items.count
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

private struct FieldTripGuideSections: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int
    let isTripComplete: Bool
    @Binding var expandedItemId: String?
    let highlightedItemId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasAvailableObjectiveGuides {
                ForEach(template.levels) { level in
                    if isLevelAvailable(level), !guidedItems(in: level).isEmpty {
                        objectiveGuideLevel(level)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("About this outing")
                    .font(.title3.weight(.bold))

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func objectiveGuideLevel(_ level: FieldTripLevel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(level.title)
                    .font(.headline.weight(.bold))

                if presentationState(for: level) == .completed {
                    Text("Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(level.items.enumerated()), id: \.element.id) { index, item in
                if item.hasGuide {
                    FieldTripObjectiveGuideCard(
                        item: item,
                        imageName: FieldTripObjectiveArtwork.imageName(
                            for: item.prompt,
                            templateSlug: template.slug,
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
                    .id(item.id)
                }
            }
        }
    }

    private var hasAvailableObjectiveGuides: Bool {
        template.levels.contains { level in
            isLevelAvailable(level) && !guidedItems(in: level).isEmpty
        }
    }

    private func guidedItems(in level: FieldTripLevel) -> [FieldTripChecklistItem] {
        level.items.filter(\.hasGuide)
    }

    private func isLevelAvailable(_ level: FieldTripLevel) -> Bool {
        presentationState(for: level) != .locked
    }

    private func presentationState(for level: FieldTripLevel) -> FieldTripLevelPresentationState {
        .resolve(
            levelNumber: level.levelNumber,
            currentLevelNumber: currentLevelNumber,
            isTripComplete: isTripComplete
        )
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
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .frame(width: 58, height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

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

private struct FieldTripLevelSection: View {
    let level: FieldTripLevel
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
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
                }

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

            if progressPlacement == .bar, let progress {
                FieldTripLevelProgressBar(progress: progress)
            }

            switch presentationState {
            case .current:
                VStack(spacing: 16) {
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
                }
            case .completed, .locked:
                FieldTripCompactLevelStrip(
                    items: level.items,
                    templateSlug: templateSlug,
                    presentationState: presentationState,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: onOpenGuide
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func progressRing(_ progress: FieldTripLevelProgressPresentation) -> some View {
        GoalProgressRing(
            completedCount: progress.completedCount,
            targetCount: progress.targetCount,
            lineWidth: FieldTripLevelHeaderLayout.ringLineWidth,
            labelFontSize: FieldTripLevelHeaderLayout.ringLabelFontSize,
            tint: .accentColor,
            showsCompletionCheckmark: true
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

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?

    init(items: [FieldTripLevelArtworkGalleryItem], initialItemID: String) {
        self.items = items
        self.initialItemID = initialItemID
        _selectedItemID = State(initialValue: initialItemID)
    }

    private var selectedItem: FieldTripLevelArtworkGalleryItem? {
        items.first(where: { $0.id == selectedItemID })
            ?? items.first(where: { $0.id == initialItemID })
            ?? items.first
    }

    var body: some View {
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
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Circle().fill(.white.opacity(0.14)))
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close patch viewer")

                    Spacer()
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)

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
        }
        .onAppear {
            if !items.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = items.first?.id
            }
        }
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
                    isHighlighted: highlightedItemId == item.id,
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
    let item: FieldTripChecklistItem
    let imageName: String
    let isHighlighted: Bool
    let completedScan: LocalScanRecord?
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @ViewBuilder
    var body: some View {
        if let completedScanId = item.completedScanId, completedScan != nil {
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
        } else if item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("View tips for this goal.")
        } else {
            tileContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if item.isCompleted, let completedScan {
            ZStack(alignment: .bottom) {
                ScanThumbnail(
                    record: completedScan,
                    maxDimension: 600,
                    mediaBadgeAlignment: .topTrailing
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground)))
            .clipShape(tileShape)
            .overlay {
                tileShape.strokeBorder(borderColor, lineWidth: borderLineWidth)
            }
        } else {
            VStack(alignment: .center, spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)

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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
            .aspectRatio(1, contentMode: .fit)
            .background(tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground)))
            .overlay {
                tileShape.strokeBorder(borderColor, lineWidth: borderLineWidth)
            }
            .shadow(color: highlightShadowColor, radius: 8)
        }
    }

    private var usesHighlight: Bool {
        isHighlighted && !item.isCompleted
    }

    private var borderColor: Color {
        usesHighlight ? Color.accentColor : Color.secondary.opacity(0.35)
    }

    private var borderLineWidth: CGFloat {
        usesHighlight ? 2 : 1
    }

    private var highlightShadowColor: Color {
        usesHighlight ? Color.accentColor.opacity(0.28) : .clear
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var accessibilityLabel: String {
        if let completedName = item.completedCommonName {
            return "\(item.prompt), \(completedName)"
        }
        return item.prompt
    }

    private var accessibilityValue: String {
        if item.isCompleted { return "Completed" }
        return "Not completed"
    }
}

private struct FieldTripCompactLevelStrip: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

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
        } else if presentationState == .completed, item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                compactTileContent(item: item, index: index)
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: item))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("View tips for this goal.")
        } else {
            compactTileContent(item: item, index: index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    private func compactTileContent(item: FieldTripChecklistItem, index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )

        return ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)

            if presentationState == .completed,
               let completedScanId = item.completedScanId,
               let completedScan = localScansById[completedScanId] {
                ScanThumbnail(
                    record: completedScan,
                    maxDimension: 300,
                    mediaBadgeAlignment: .topTrailing
                )
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
                    .padding(FieldTripScanPreviewLayout.imagePadding)
            }
        }
        .frame(
            width: FieldTripScanPreviewLayout.tileSize,
            height: FieldTripScanPreviewLayout.tileSize
        )
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(compactBorderColor, lineWidth: 1)
        }
    }

    private var compactBorderColor: Color {
        presentationState == .locked
            ? Color.secondary.opacity(0.35)
            : Color.primary.opacity(0.08)
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
        } else if let urlString, let url = URL(string: urlString) {
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

private struct FieldTripPublicationStatusBadge: View {
    let isPublished: Bool

    private var tint: Color {
        isPublished ? .green : .secondary
    }

    var body: some View {
        Label(
            isPublished ? "Published" : "Private",
            systemImage: isPublished ? "eye.fill" : "eye.slash.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(isPublished ? 0.16 : 0.12))
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPublished ? "Published publicly" : "Private outing")
        .accessibilityHint(
            isPublished
                ? "A public snapshot of this outing is published."
                : "This outing has not been published."
        )
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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 172, height: 19)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 140, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 64, height: 64)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(
                            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                            style: .continuous
                        )
                        .fill(Color.secondary.opacity(0.12))
                        .frame(
                            width: FieldTripScanPreviewLayout.tileSize,
                            height: FieldTripScanPreviewLayout.tileSize
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                                style: .continuous
                            )
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: FieldTripScanPreviewLayout.tileSize)
            .scrollDisabled(true)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([CGFloat(58), CGFloat(64), CGFloat(88), CGFloat(72)], id: \.self) { width in
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: width, height: 27)
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDisabled(true)
            .padding(.bottom, 12)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
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

private struct FieldTripTemplateDetailSkeleton: View {
    let showsCoverImage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showsCoverImage {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 220, height: 24)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 16)
            FieldTripExpandedLevelSkeleton()
            FieldTripCompactLevelSkeleton()
        }
        .redacted(reason: .placeholder)
    }
}

private struct FieldTripExpandedLevelSkeleton: View {
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            levelHeader
            progressBar

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Capsule()
                            .fill(Color.secondary.opacity(0.14))
                            .frame(width: 72, height: 12)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
            }
        }
        .padding(12)
        .background(levelCardShape.fill(Color.secondary.opacity(0.06)))
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var levelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 92, height: 20)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 188, height: 11)
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

private struct FieldTripCompactLevelSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 72, height: 16)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 188, height: 11)
                }

                Spacer(minLength: 8)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 12, height: 15)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(
                            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                            style: .continuous
                        )
                        .fill(Color.secondary.opacity(0.1))
                        .frame(
                            width: FieldTripScanPreviewLayout.tileSize,
                            height: FieldTripScanPreviewLayout.tileSize
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
                .padding(.horizontal, 12)
            }
            .scrollDisabled(true)
            .frame(height: FieldTripScanPreviewLayout.tileSize)
            .padding(.horizontal, -12)
        }
        .padding(12)
        .background(levelCardShape.fill(Color.secondary.opacity(0.06)))
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var levelCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
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
