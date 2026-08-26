import SwiftUI

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
