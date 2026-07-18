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
    @State private var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
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
                        completedAchievements: awards.completedCount
                    )

                    // MARK: - Stats
                    UserStats(speciesCount: uniqueSpeciesCount, streak: currentStreak)
                }

                // MARK: - Public Explore Scans
                ProfilePublicScansPreview(
                    viewModel: exploreViewModel,
                    onOpenPost: openPublicScanPreview
                )

                // MARK: - Field trips
                if FieldTripsAvailability.isEnabled {
                    CurrentUserFieldTripProfilePreview { publicationId in
                        selectedFieldTripPublicationRoute = FieldTripPublicationRoute(publicationId: publicationId)
                    }
                }

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
                if !awards.isEmpty {
                    Achievements(awards: awards)
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
        awards = stats.awards
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
}

private extension [AwardPayload] {
    var completedCount: Int {
        filter(\.isCompleted).count
    }
}
