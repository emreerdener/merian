import SwiftUI

enum FieldTripTemplatePresentation {
    static let backyardSafariSlug = "backyard_safari"
    static let parkPollinatorsSlug = "park_pollinators"

    static func title(_ title: String, slug: String) -> String {
        guard slug == backyardSafariSlug, title == "Backyard Safari" else {
            return title
        }
        return "Backyard safari"
    }

    static func bundledCoverImageName(for slug: String?) -> String? {
        slug == backyardSafariSlug ? "fieldtrip-backyard-safari" : nil
    }

    static func outingCopy(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Field Trips", with: "Outings")
            .replacingOccurrences(of: "Field Trip", with: "Outing")
            .replacingOccurrences(of: "field trips", with: "outings")
            .replacingOccurrences(of: "field trip", with: "outing")
            .replacingOccurrences(of: " trips", with: " outings")
            .replacingOccurrences(of: " trip", with: " outing")
    }
}

struct FieldTripsView: View {
    let userRegion: String?
    @Binding var selectedSection: FieldTripsSection
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @State private var viewModel = FieldTripsViewModel()
    @State private var selectedDifficultyFilter: FieldTripDifficultyFilter = .all

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
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .fieldTripProgressUpdated(let updates):
                viewModel.applyProgressToast(updates)
                Task { await viewModel.refresh(userRegion: userRegion) }
            case .fieldTripChallengeProgressUpdated(let updates):
                viewModel.applyChallengeProgressToast(updates)
                Task { await viewModel.refresh(userRegion: userRegion) }
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
                    difficultyFilterBar

                    LazyVStack(spacing: 16) {
                        if viewModel.isLoading && viewModel.templates.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                FieldTripTemplateSkeletonCard()
                            }
                        } else if let errorMessage = viewModel.errorMessage, viewModel.templates.isEmpty {
                            FieldTripUnavailableCard(
                                title: "Outings unavailable",
                                message: errorMessage
                            ) {
                                Task { await viewModel.refresh(userRegion: userRegion) }
                            }
                        } else if viewModel.templates.isEmpty {
                            FieldTripUnavailableCard(
                                title: "Outings unavailable",
                                message: "Challenges are not available right now."
                            ) {
                                Task { await viewModel.refresh(userRegion: userRegion) }
                            }
                        } else if filteredTemplates.isEmpty {
                            filteredEmptyState
                                .frame(
                                    minHeight: max(360, geometry.size.height - 96)
                                )
                        } else {
                            ForEach(filteredTemplates) { template in
                                NavigationLink(value: FieldTripTemplateRoute(templateId: template.templateId)) {
                                    FieldTripTemplateCard(template: template)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        HapticManager.shared.triggerLightImpact(
                                            intensity: 0.45,
                                            source: "fieldTrips.catalog.template.open"
                                        )
                                    }
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
        viewModel.templates.filtering(by: selectedDifficultyFilter.difficulty)
    }

    private var difficultyFilterBar: some View {
        CategoryFilterBar(
            items: FieldTripDifficultyFilter.allCases,
            activeItem: selectedDifficultyFilter,
            title: { $0.title },
            onSelection: { filter in
                guard filter != selectedDifficultyFilter else { return }
                selectedDifficultyFilter = filter
                HapticManager.shared.triggerSelectionPulse()
            }
        )
        .accessibilityLabel("Outing difficulty")
    }

    private var filteredEmptyState: some View {
        EmptyStateView(
            imageName: "fireflies",
            title: "No \(selectedDifficultyFilter.title) challenges yet",
            message: "Try another difficulty to find your next challenge."
        ) {
            Button {
                selectedDifficultyFilter = .all
                HapticManager.shared.triggerSelectionPulse()
            } label: {
                Text("Show all")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
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

        return ScrollView(showsIndicators: false) {
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
                    FieldTripUnavailableCard(
                        title: "Events unavailable",
                        message: "Events are not available right now."
                    ) {
                        Task { await viewModel.refresh(userRegion: userRegion) }
                    }
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

struct FieldTripTemplateDetailView: View {
    let templateId: String
    let focusedChecklistItemId: String?
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @State private var template: FieldTripTemplate?
    @State private var communityPreview: [FieldTripRecentPublication] = []
    @State private var isLoading = false
    @State private var isStarting = false
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

    init(
        templateId: String,
        focusedChecklistItemId: String? = nil,
        onOpenPublication: @escaping (String) -> Void,
        onOpenAuthorProfile: @escaping (FieldTripRecentPublication) -> Void
    ) {
        self.templateId = templateId
        self.focusedChecklistItemId = focusedChecklistItemId
        self.onOpenPublication = onOpenPublication
        self.onOpenAuthorProfile = onOpenAuthorProfile
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                if isLoading && template == nil {
                    FieldTripTemplateDetailSkeleton(showsCoverImage: false)
                        .padding(16)
                } else if let errorMessage, template == nil {
                    FieldTripUnavailableCard(
                        title: "Outing unavailable",
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
                    ?? "Outing"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
            .task {
                await load(force: false)
            }
            .refreshable {
                await load(force: true)
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                guard case .fieldTripProgressUpdated(let updates) = event,
                      updates.contains(where: { $0.templateId == templateId }) else {
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
                    Text(FieldTripTemplatePresentation.title(template.title, slug: template.slug))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = template.description {
                        Text(FieldTripTemplatePresentation.outingCopy(description))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FieldTripLevelsSection(
                    template: template,
                    currentLevelNumber: template.activeProgress?.currentLevelNumber ?? 1,
                    isTripComplete: template.activeProgress?.isComplete ?? false,
                    progress: template.activeProgress.map(FieldTripLevelProgressPresentation.init),
                    highlightedItemId: highlightedObjectiveItemId,
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
                currentLevelNumber: template.activeProgress?.currentLevelNumber ?? 1,
                isTripComplete: template.activeProgress?.isComplete ?? false,
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
                    label: "Outing details",
                    selection: $selectedDetailSection
                )
            }
        }

        if let template {
            ToolbarItem(placement: .bottomBar) {
                primaryActionBar(template)
            }
        }
    }

    @ViewBuilder
    private func primaryActionBar(_ template: FieldTripTemplate) -> some View {
        if !template.viewerHasAccess {
            FieldTripDetailPrimaryActionBar(
                title: "Unlock with Pro",
                systemImage: "lock.fill"
            ) {
                AppEventPublisher.shared.send(.triggerPaywall)
            }
        } else if template.activeProgress == nil {
            FieldTripDetailPrimaryActionBar(
                title: "Start challenge",
                systemImage: "play.fill",
                isLoading: isStarting,
                isEnabled: !isStarting
            ) {
                Task { await start(template) }
            }
        } else if let progress = template.activeProgress, progress.isComplete {
            FieldTripDetailPrimaryActionBar(
                title: "Publish challenge",
                systemImage: "square.and.arrow.up"
            ) {
                publishingTemplate = template
            }
        } else {
            FieldTripDetailPrimaryActionBar(
                title: "Go scan",
                systemImage: nil
            ) {
                openScanner()
            }
        }
    }

    private func openScanner() {
        HapticManager.shared.triggerLightImpact(
            intensity: 0.45,
            source: "fieldTrips.challenge.goScan"
        )
        AppEventPublisher.shared.send(.requestOpenScanner)
    }

    private func load(force: Bool) async {
        guard force || template == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedTemplate = try await MerianNetworkClient.shared.getFieldTripTemplate(templateId: templateId)
            template = loadedTemplate
            applyInitialFocusIfNeeded(to: loadedTemplate)
            await loadCommunityPreview(templateId: loadedTemplate.templateId)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func start(_ template: FieldTripTemplate) async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            self.template = try await MerianNetworkClient.shared.startFieldTrip(templateId: template.templateId)
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Outing started."
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
            .navigationTitle(viewModel.challenge?.title ?? "Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
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
                        highlightedItemId: nil,
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
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                FieldTripChallengeStatusBadge(status: challenge.status)
            }

            if let description = challenge.description {
                Text(FieldTripTemplatePresentation.outingCopy(description))
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

        if let challenge = viewModel.challenge {
            ToolbarItem(placement: .bottomBar) {
                primaryActionBar(challenge)
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
                title: "Go scan",
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
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
            }
            .font(.headline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
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
            "Objectives"
        case .tips:
            "Tips"
        }
    }
}

private enum FieldTripDifficultyFilter: String, CaseIterable, Identifiable {
    case all
    case starter
    case easy
    case moderate
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var difficulty: FieldTripDifficulty? {
        guard self != .all else { return nil }
        return FieldTripDifficulty(rawValue: rawValue)
    }
}

enum FieldTripsSection: String, CaseIterable, Identifiable {
    case fieldTrips
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldTrips:
            "Challenges"
        case .seasonal:
            "Events"
        }
    }
}

private enum FieldTripScanPreviewLayout {
    static let tileSize: CGFloat = 96
    static let cornerRadius: CGFloat = 14
    static let spacing: CGFloat = 10
    static let imagePadding: CGFloat = 12
}

// Bundled objective artwork. Capture surfaces intentionally use only exact
// template mappings; richer Field Trip grids may use semantic fallback art.
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
        "spider near flowers": "fieldtrip-park-spider",
        "seed or fruiting plant": "fieldtrip-park-seedpod",
        "bird near flowers": "fieldtrip-park-hummingbird",
        "wild plant": "fieldtrip-park-dandelion",
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

private struct FieldTripTemplateCard: View {
    let template: FieldTripTemplate

    private var previewTargetCount: Int {
        if let activeProgress = template.activeProgress {
            return max(0, activeProgress.targetCount)
        }

        return template.levels
            .min(by: { $0.levelNumber < $1.levelNumber })?
            .items.count ?? 0
    }

    private var previewCompletedCount: Int {
        max(0, template.activeProgress?.completedCount ?? 0)
    }

    private var previewItems: [FieldTripChecklistItem] {
        if let activeLevelNumber = template.activeProgress?.currentLevelNumber,
           let activeLevel = template.levels.first(where: { $0.levelNumber == activeLevelNumber }) {
            return activeLevel.items
        }

        return template.levels
            .min(by: { $0.levelNumber < $1.levelNumber })?
            .items ?? []
    }

    private var showsScanPreview: Bool {
        previewTargetCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    FieldTripAccessBadge(template: template)

                    Spacer(minLength: 16)

                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }

                Text(FieldTripTemplatePresentation.title(template.title, slug: template.slug))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle = template.subtitle {
                    Text(FieldTripTemplatePresentation.outingCopy(subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, showsScanPreview || template.activeProgress != nil ? 12 : 16)

            if showsScanPreview {
                FieldTripScanPreviewStrip(
                    completedCount: previewCompletedCount,
                    targetCount: previewTargetCount,
                    templateSlug: template.slug,
                    items: previewItems
                )
                .padding(.bottom, template.activeProgress == nil ? 16 : 12)
            }

            if let activeProgress = template.activeProgress {
                FieldTripProgressBar(progress: activeProgress)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

private struct FieldTripScanPreviewStrip: View {
    let completedCount: Int
    let targetCount: Int
    let templateSlug: String
    let items: [FieldTripChecklistItem]

    private var visibleTargetCount: Int {
        max(0, targetCount)
    }

    private var visibleCompletedCount: Int {
        min(visibleTargetCount, max(0, completedCount))
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
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scanSlot(at index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )
        let isCompleted = index < visibleCompletedCount

        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)

            Image(
                FieldTripObjectiveArtwork.imageName(
                    for: items.indices.contains(index) ? items[index].prompt : "",
                    templateSlug: templateSlug,
                    fallbackIndex: index
                )
            )
                .resizable()
                .scaledToFit()
                .padding(FieldTripScanPreviewLayout.imagePadding)
        }
        .frame(
            width: FieldTripScanPreviewLayout.tileSize,
            height: FieldTripScanPreviewLayout.tileSize
        )
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isCompleted ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.35),
                lineWidth: 1
            )
        }
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
                            Text(FieldTripTemplatePresentation.outingCopy(subtitle))
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

private struct FieldTripLevelProgressPresentation {
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
}

private struct FieldTripLevelsSection: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int
    let isTripComplete: Bool
    let progress: FieldTripLevelProgressPresentation?
    let highlightedItemId: String?
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
                    progress: level.levelNumber == currentLevelNumber ? progress : nil,
                    highlightedItemId: highlightedItemId,
                    onOpenGuide: onOpenGuide
                )
            }
        }
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
                Label("Outing", systemImage: "map")
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

            if hasAboutGuidance {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About this outing")
                        .font(.title3.weight(.bold))

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

    private var hasAboutGuidance: Bool {
        template.guideWhereToLook != nil
            || template.guideWhyItMatters != nil
            || template.guideSafetyEthics != nil
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
    let highlightedItemId: String?
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    private var rowStartIndices: [Int] {
        Array(stride(from: 0, to: level.items.count, by: 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(level.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 12)

                    switch presentationState {
                    case .current:
                        EmptyView()
                    case .completed:
                        Text("Completed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    case .locked:
                        Image(systemName: "lock")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                }

                if let description = level.description {
                    Text(FieldTripTemplatePresentation.outingCopy(description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let progress {
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
                            onOpenGuide: onOpenGuide
                        )
                    }
                }
            case .completed, .locked:
                FieldTripCompactLevelStrip(
                    items: level.items,
                    templateSlug: templateSlug,
                    presentationState: presentationState,
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

}

private struct FieldTripChecklistGridRow: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let fallbackStartIndex: Int
    let highlightedItemId: String?
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
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @ViewBuilder
    var body: some View {
        if item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("View tips for this objective.")
        } else {
            tileContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
        }
    }

    private var tileContent: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if item.hasGuide {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
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
        .background(
            tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay {
            tileShape.strokeBorder(
                isHighlighted
                    ? Color.accentColor
                    : item.isCompleted
                        ? Color.accentColor.opacity(0.65)
                        : Color.secondary.opacity(0.35),
                lineWidth: isHighlighted || item.isCompleted ? 2 : 1
            )
        }
        .shadow(
            color: isHighlighted ? Color.accentColor.opacity(0.28) : .clear,
            radius: 8
        )
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
        if presentationState == .completed, item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                compactTileContent(item: item, index: index)
            }
            .buttonStyle(FieldTripObjectiveTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: item))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("View tips for this objective.")
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

private struct FieldTripAccessBadge: View {
    let template: FieldTripTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if template.viewerHasAccess {
                Text(template.difficultyTitle)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text("Pro")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
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

private struct FieldTripProgressBar: View {
    let progress: FieldTripProgress

    var body: some View {
        FieldTripLevelProgressBar(
            progress: FieldTripLevelProgressPresentation(progress)
        )
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

private struct FieldTripLevelProgressBar: View {
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
            .navigationTitle("Publish Outing")
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
        guard let progress = template.activeProgress else { return }
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
            imageName: "fireflies",
            imageHeight: 160,
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 68, height: 25)

                    Spacer(minLength: 16)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 8, height: 22)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 180, height: 20)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
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

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 48, height: 12)

                    Spacer()

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 30, height: 12)
                }

                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 7)
            }
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
