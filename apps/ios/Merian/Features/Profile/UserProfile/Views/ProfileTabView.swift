import SwiftData
import SwiftUI

/// The standalone layout hierarchy for the primary "Profile" tab.
/// This acts purely as a declarative composition module that groups all massive
/// visual data visualizations (Terrarium, Heatmap) and abstracts intense offline SQLite
/// hardware calculations completely away from the orchestrator logic natively.
struct ProfileTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
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
    @State private var selectedFieldTripAuthorRoute: ExploreAuthorProfileRoute?
    @State private var selectedInsightRoute: ScanInsightRoute?
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
                        completedAchievements: visibleAwards.completedCount
                    )

                    // MARK: - Stats
                    UserStats(speciesCount: uniqueSpeciesCount, streak: currentStreak)
                }

                // MARK: - Field trips
                if FieldTripsAvailability.isEnabled {
                    ActiveFieldTripsProfilePreview(
                        onOpenTemplate: { templateId in
                            selectedFieldTripTemplateRoute = FieldTripTemplateRoute(templateId: templateId)
                        },
                        onOpenCompletedScan: openFieldTripCompletedScan,
                        onViewAll: {
                            AppEventPublisher.shared.send(.requestOpenFieldTrips)
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

                // MARK: - Refer a Friend
                ReferFriendCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environment(RevenueCatManager.shared)
            }
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
            .sheet(item: $selectedInsightRoute) { route in
                InsightSheetView(
                    isPresented: Binding(
                        get: { selectedInsightRoute != nil },
                        set: { if !$0 { selectedInsightRoute = nil } }
                    ),
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine,
                    allowsExplorePresentation: false
                )
            }
            .sheet(item: $selectedFieldTripAuthorRoute) { route in
                ExploreAuthorProfileSheet(viewModel: exploreViewModel, route: route)
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
            .task(id: profileRefreshToken) {
                await refreshProfileStats()
            }
            .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
                profileRefreshToken = UUID()
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                guard FieldTripsAvailability.isEnabled else { return }
                switch event {
                case .fieldTripProgressUpdated,
                     .fieldTripChallengeProgressUpdated,
                     .captureGoalContextInvalidated(.fieldTrip):
                    profileRefreshToken = UUID()
                default:
                    break
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry identical to SettingsTabView!
        .containerRelativeFrame(.horizontal)
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
        guard FieldTripsAvailability.isEnabled,
              let accountId = SupabaseManager.shared.currentUser?.id.uuidString else {
            awards = stats.awards
            return
        }

        var progress = FirstFieldTripAchievementProgressStore.load(accountId: accountId)?
            .visible(eventsEnabled: FieldTripEventsAvailability.isEnabled)
        awards = stats.awards.mergingFirstFieldTripAchievement(progress)
        do {
            if let refreshedProgress = try await MerianNetworkClient.shared
                .getFirstFieldTripAchievementProgress()?
                .visible(eventsEnabled: FieldTripEventsAvailability.isEnabled) {
                guard SupabaseManager.shared.currentUser?.id.uuidString == accountId else {
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
        guard !FieldTripsAvailability.isEnabled else { return awards }
        return awards.filter { $0.type != .firstFieldTrip }
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

        inferenceEngine.load(from: record)
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
        return true
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        if openInsight(scanId: scanId) {
            HapticManager.shared.triggerSelectionPulse()
        } else {
            HapticManager.shared.triggerErrorThump()
        }
    }

    private func openFieldTripAuthorProfile(_ publication: FieldTripRecentPublication) {
        HapticManager.shared.triggerSelectionPulse()
        selectedFieldTripAuthorRoute = ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        )
    }
}

private extension [AwardPayload] {
    var completedCount: Int {
        filter(\.isCompleted).count
    }
}
