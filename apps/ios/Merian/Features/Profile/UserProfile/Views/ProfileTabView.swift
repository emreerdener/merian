import SwiftData
import SwiftUI

struct ProfileStatsRefreshKey: Equatable {
    let refreshToken: UUID
    let isAuthenticated: Bool
    let accountId: String?
}

enum ProfileTabPresentation: Identifiable, Equatable {
    case paywall
    case insight(ScanInsightRoute)
    case fieldTripAuthor(ExploreAuthorProfileRoute)

    var id: String {
        switch self {
        case .paywall:
            "paywall"
        case .insight(let route):
            "insight-\(route.id)"
        case .fieldTripAuthor(let route):
            "field-trip-author-\(route.id)"
        }
    }
}

/// The standalone layout hierarchy for the primary "Profile" tab.
/// This acts purely as a declarative composition module that groups all massive
/// visual data visualizations (Terrarium, Heatmap) and abstracts intense offline SQLite
/// hardware calculations completely away from the orchestrator logic natively.
struct ProfileTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    private var supabase: SupabaseManager { .shared }
    @Binding var showPaywall: Bool
    @Binding var isShowingAvatarPicker: Bool
    @Binding var isShowingDisplayNameEditor: Bool
    @Binding var isShowingUsernameEditor: Bool
    
    // Natively isolated State variables dynamically mapped back from the background Actor mathematically.
    @State private var uniqueSpeciesCount: Int = 0
    @State private var currentStreak: Int = 0
    @State private var totalCaptures: Int = 0
    @State private var heatmapData: ProfileHeatmapData?
    @State private var awards: [AwardPayload] = []
    @State private var exploreViewModel = ExploreFeedViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var selectedFieldTripTemplateRoute: FieldTripTemplateRoute?
    @State private var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
    @State private var activePresentation: ProfileTabPresentation?
    @State private var earnedFieldTripPatches: [EarnedFieldTripPatch] = []
    @State private var isLoadingEarnedFieldTripPatches = FeatureFlags.isEnabled(.fieldTrips)
    @State private var profileRefreshToken = UUID()
    
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
                        totalScans: totalCaptures,
                        completedAchievements: visibleAwards.completedCount,
                        earnedFieldTripPatches: earnedFieldTripPatches,
                        isLoadingEarnedFieldTripPatches: isLoadingEarnedFieldTripPatches,
                        onOpenFieldTrip: { templateId in
                            selectedFieldTripTemplateRoute = FieldTripTemplateRoute(
                                templateId: templateId
                            )
                        }
                    )

                    // MARK: - Stats
                    UserStats(speciesCount: uniqueSpeciesCount, streak: currentStreak)
                }

                // MARK: - Field trips
                if FeatureFlags.isEnabled(.fieldTrips) {
                    ActiveFieldTripsProfilePreview(
                        onOpenTemplate: { templateId in
                            selectedFieldTripTemplateRoute = FieldTripTemplateRoute(templateId: templateId)
                        },
                        onOpenCompletedScan: openFieldTripCompletedScan,
                        onViewAll: {
                            AppDIContainer.shared.appRouteCoordinator.request(
                                .fieldTrips,
                                source: .internalUserAction
                            )
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
                    Terrarium(uniqueSpeciesCount: uniqueSpeciesCount)
#if DEBUG
                        .onTapGesture {
                            let currentPersona = UserPersona(speciesCount: uniqueSpeciesCount)
                            if let nextThreshold = currentPersona.nextLevelThreshold {
                                uniqueSpeciesCount = nextThreshold
                            } else {
                                uniqueSpeciesCount = 0
                            }
                            HapticManager.shared.triggerSelectionPulse()
                        }
#endif
                    Persona(uniqueSpeciesCount: uniqueSpeciesCount)
                }
                .padding(.vertical, 16)

                // MARK: - Heatmap
                ScansHeatmap(heatmapData: heatmapData)

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
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .scanLibraryChanged = event else { return }
                profileRefreshToken = UUID()
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard FeatureFlags.isEnabled(.fieldTrips) else { return }
                switch event {
                case .fieldTripProgressInvalidated,
                     .fieldTripChallengeProgressInvalidated,
                     .captureGoalContextInvalidated(.fieldTrip):
                    profileRefreshToken = UUID()
                default:
                    break
                }
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
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry identical to SettingsTabView!
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
                .environment(RevenueCatManager.shared)

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
        // Decouples massive SwiftData queries explicitly into a `ModelActor` to completely
        // prevent dropping frames on the physical UI Thread during millions of array computations.
        let actor = ProfileDatabaseActor(modelContainer: modelContext.container)
        let stats = await actor.calculateAll()
        guard !Task.isCancelled else { return }

        uniqueSpeciesCount = stats.speciesCount
        currentStreak = stats.streak
        totalCaptures = stats.heatmap.totalCaptures
        heatmapData = stats.heatmap
        guard FeatureFlags.isEnabled(.fieldTrips),
              supabase.isAuthenticated,
              let accountId = supabase.currentUser?.id.uuidString else {
            awards = stats.awards
            return
        }

        var progress = FirstFieldTripAchievementProgressStore.load(accountId: accountId)
        awards = stats.awards.mergingFirstFieldTripAchievement(progress)
        do {
            if let refreshedProgress = try await MerianNetworkClient.shared
                .getFirstFieldTripAchievementProgress() {
                guard supabase.isAuthenticated,
                      supabase.currentUser?.id.uuidString == accountId else {
                    return
                }
                FirstFieldTripAchievementProgressStore.save(
                    refreshedProgress,
                    accountId: accountId
                )
                progress = refreshedProgress
                awards = stats.awards.mergingFirstFieldTripAchievement(progress)
            }
        } catch {
            MerianLog.network.debug(
                "First Field trip achievement refresh failed: \(error, privacy: .private)"
            )
        }
    }

    private var visibleAwards: [AwardPayload] {
        guard !FeatureFlags.isEnabled(.fieldTrips) else { return awards }
        return awards.filter { $0.type != .firstFieldTrip }
    }

    private var profileStatsRefreshKey: ProfileStatsRefreshKey {
        ProfileStatsRefreshKey(
            refreshToken: profileRefreshToken,
            isAuthenticated: supabase.isAuthenticated,
            accountId: supabase.currentUser?.id.uuidString
        )
    }

    private func openPublicScanPreview(_ post: ExplorePost) {
        HapticManager.shared.triggerSelectionPulse()
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
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = try? modelContext.fetch(descriptor).first else {
            return false
        }

        return beginPresentation(.insight(ScanInsightRoute(scanId: record.id)))
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        if openInsight(scanId: scanId) {
            HapticManager.shared.triggerSelectionPulse()
        } else {
            HapticManager.shared.triggerErrorThump()
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
        HapticManager.shared.triggerSelectionPulse()
    }
}

private extension [AwardPayload] {
    var completedCount: Int {
        filter(\.isCompleted).count
    }
}
