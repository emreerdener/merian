import SwiftUI

/// Composes the primary Profile tab from prepared feature state.
struct ProfileTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(SupabaseManager.self) private var supabase
    @Binding var showPaywall: Bool
    @Binding var isShowingAvatarPicker: Bool
    @Binding var isShowingDisplayNameEditor: Bool
    @Binding var isShowingUsernameEditor: Bool

    @State private var profileState: ProfileTabViewModel
    @State private var exploreViewModel = ExploreFeedViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var selectedFieldTripTemplateRoute: FieldTripTemplateRoute?
    @State private var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
    @State private var activePresentation: ProfileTabPresentation?
    @State private var earnedFieldTripPatches: [EarnedFieldTripPatch] = []
    @State private var isLoadingEarnedFieldTripPatches = FeatureFlags.isEnabled(.fieldTrips)

    init(
        showPaywall: Binding<Bool>,
        isShowingAvatarPicker: Binding<Bool>,
        isShowingDisplayNameEditor: Binding<Bool>,
        isShowingUsernameEditor: Binding<Bool>,
        dependencies: ProfileTabDependencies? = nil
    ) {
        _showPaywall = showPaywall
        _isShowingAvatarPicker = isShowingAvatarPicker
        _isShowingDisplayNameEditor = isShowingDisplayNameEditor
        _isShowingUsernameEditor = isShowingUsernameEditor
        _profileState = State(
            initialValue: ProfileTabViewModel(
                dependencies: dependencies ?? .live
            )
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // MARK: - Core Profile Content
            VStack(spacing: 24) {
                VStack(spacing: 24) {
                    // MARK: - User Profile
                    UserProfile(
                        isShowingAvatarPicker: $isShowingAvatarPicker,
                        isShowingDisplayNameEditor: $isShowingDisplayNameEditor,
                        isShowingUsernameEditor: $isShowingUsernameEditor,
                        totalScans: profileState.totalCaptures,
                        completedAchievements: profileState.completedAwardCount(
                            fieldTripsEnabled: fieldTripsEnabled
                        ),
                        earnedFieldTripPatches: earnedFieldTripPatches,
                        isLoadingEarnedFieldTripPatches: isLoadingEarnedFieldTripPatches,
                        onOpenFieldTrip: { templateId in
                            selectedFieldTripTemplateRoute = FieldTripTemplateRoute(
                                templateId: templateId
                            )
                        }
                    )

                    // MARK: - Stats
                    UserStats(
                        speciesCount: profileState.uniqueSpeciesCount,
                        streak: profileState.currentStreak
                    )
                }

                // MARK: - Field trips
                if fieldTripsEnabled {
                    ActiveFieldTripsProfilePreview(
                        onOpenTemplate: { templateId in
                            selectedFieldTripTemplateRoute = FieldTripTemplateRoute(templateId: templateId)
                        },
                        onOpenCompletedScan: openFieldTripCompletedScan,
                        onViewAll: {
                            profileState.openFieldTrips()
                        },
                        onEarnedPatchesChange: { patches in
                            earnedFieldTripPatches = patches
                        },
                        onEarnedPatchesLoadingChange: { isLoading in
                            isLoadingEarnedFieldTripPatches = isLoading
                        }
                    )
                }

                // MARK: - Public Explore Scans
                ProfilePublicScansPreview(
                    viewModel: exploreViewModel,
                    onOpenPost: openPublicScanPreview
                )

                // MARK: - Paywall & Subscriptions
                if !revenueCatManager.isProActive {
                    PlanCard(showPaywall: $showPaywall)
                }

                // MARK: - Terrarium & Persona
                VStack(spacing: 16) {
                    Terrarium(uniqueSpeciesCount: profileState.uniqueSpeciesCount)
#if DEBUG
                        .onTapGesture {
                            let currentPersona = UserPersona(
                                speciesCount: profileState.uniqueSpeciesCount
                            )
                            if let nextThreshold = currentPersona.nextLevelThreshold {
                                profileState.setDebugSpeciesCount(nextThreshold)
                            } else {
                                profileState.setDebugSpeciesCount(0)
                            }
                            profileState.selectionFeedback()
                        }
#endif
                    Persona(uniqueSpeciesCount: profileState.uniqueSpeciesCount)
                }
                .padding(.vertical, 16)

                // MARK: - Heatmap
                ScansHeatmap(heatmapData: profileState.heatmapData)

                // MARK: - Gamification Awards
                if !visibleAwards.isEmpty {
                    Achievements(awards: visibleAwards)
                }

                // MARK: - Share Naturebook
                ShareNaturebookCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedPostRoute != nil },
                    set: { if !$0 { selectedPostRoute = nil } }
                )
            ) {
                if let selectedPostRoute {
                    ExplorePostDetailView(
                        viewModel: exploreViewModel,
                        postId: selectedPostRoute.postId,
                        shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                        shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                        targetCommentId: selectedPostRoute.targetCommentId,
                        targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                        allowsInsightPresentation: false,
                        onOpenOwnedPostInsight: openInsight
                    )
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripTemplateRoute != nil },
                    set: { if !$0 { selectedFieldTripTemplateRoute = nil } }
                )
            ) {
                if let selectedFieldTripTemplateRoute {
                    FieldTripTemplateDetailView(
                        reference: selectedFieldTripTemplateRoute.reference,
                        focusedChecklistItemId: selectedFieldTripTemplateRoute.focusedChecklistItemId,
                        onOpenCompletedScan: openFieldTripCompletedScan,
                        onOpenPublication: { publicationId in
                            selectedFieldTripPublicationRoute = FieldTripPublicationRoute(
                                publicationId: publicationId
                            )
                        },
                        onOpenAuthorProfile: openFieldTripAuthorProfile
                    )
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripPublicationRoute != nil },
                    set: { if !$0 { selectedFieldTripPublicationRoute = nil } }
                )
            ) {
                if let selectedFieldTripPublicationRoute {
                    FieldTripPublicationDetailView(publicationId: selectedFieldTripPublicationRoute.publicationId)
                }
            }
            .sheet(item: activePresentationBinding) { presentation in
                profileSheetContent(presentation)
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: exploreViewModel
                )
            }
            .task(id: profileStatsRefreshKey) {
                await refreshProfileStats()
            }
            .onReceive(profileState.appEvents) { event in
                profileState.handle(
                    event: event,
                    fieldTripsEnabled: fieldTripsEnabled
                )
            }
            .onChange(of: showPaywall, initial: true) { _, isRequested in
                if isRequested {
                    guard beginPresentation(.paywall) else {
                        showPaywall = false
                        return
                    }
                } else if activePresentation == .paywall {
                    activePresentation = nil
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Match the Profile shell's horizontal paging width.
        .containerRelativeFrame(.horizontal)
    }

    private var activePresentationBinding: Binding<ProfileTabPresentation?> {
        Binding(
            get: { activePresentation },
            set: { presentation in
                guard presentation == nil else { return }
                if activePresentation == .paywall {
                    showPaywall = false
                }
                activePresentation = nil
            }
        )
    }

    @ViewBuilder
    private func profileSheetContent(
        _ presentation: ProfileTabPresentation
    ) -> some View {
        switch presentation {
        case .paywall:
            PaywallView()
                .environment(revenueCatManager)

        case .insight(let route):
            LocalScanInsightLoader(scanId: route.scanId) {
                InsightSheetView(
                    isPresented: presentationBinding(for: presentation),
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine,
                    allowsExplorePresentation: false
                )
            }

        case .fieldTripAuthor(let route):
            ExploreAuthorProfileSheet(viewModel: exploreViewModel, route: route)
        }
    }

    private func presentationBinding(
        for presentation: ProfileTabPresentation
    ) -> Binding<Bool> {
        Binding(
            get: { activePresentation?.id == presentation.id },
            set: { isPresented in
                guard !isPresented,
                      activePresentation?.id == presentation.id else { return }
                activePresentation = nil
            }
        )
    }

    @discardableResult
    private func beginPresentation(
        _ presentation: ProfileTabPresentation
    ) -> Bool {
        guard activePresentation == nil else { return false }
        activePresentation = presentation
        return true
    }

    @MainActor
    private func refreshProfileStats() async {
        await profileState.refresh(
            key: profileStatsRefreshKey,
            modelContainer: modelContext.container,
            fieldTripsEnabled: fieldTripsEnabled
        )
    }

    private var visibleAwards: [AwardPayload] {
        profileState.visibleAwards(fieldTripsEnabled: fieldTripsEnabled)
    }

    private var profileStatsRefreshKey: ProfileStatsRefreshKey {
        profileState.refreshKey(
            isAuthenticated: supabase.isAuthenticated,
            accountID: supabase.currentUser?.id.uuidString
        )
    }

    private var fieldTripsEnabled: Bool {
        FeatureFlags.isEnabled(.fieldTrips)
    }

    private func openPublicScanPreview(_ post: ExplorePost) {
        profileState.selectionFeedback()
        exploreViewModel.upsertPost(post)
        exploreViewModel.refreshPreferredSpeciesNames(
            for: [post.speciesScientificName],
            modelContext: modelContext
        )
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        )
    }

    private func openInsight(scanId: String) -> Bool {
        guard let route = profileState.insightRoute(
            scanID: scanId,
            modelContext: modelContext
        ) else { return false }
        return beginPresentation(.insight(route))
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        if openInsight(scanId: scanId) {
            profileState.selectionFeedback()
        } else {
            profileState.errorFeedback()
        }
    }

    private func openFieldTripAuthorProfile(_ publication: FieldTripRecentPublication) {
        let presentation = ProfileTabPresentation.fieldTripAuthor(
            ExploreAuthorProfileRoute(
                authorUserId: publication.authorUserId,
                authorName: publication.authorName,
                authorUsername: publication.authorUsername,
                authorAvatarUrl: publication.authorAvatarUrl
            )
        )
        guard beginPresentation(presentation) else { return }
        profileState.selectionFeedback()
    }
}
