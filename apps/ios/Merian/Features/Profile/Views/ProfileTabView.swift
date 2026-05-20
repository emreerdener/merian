import SwiftData
import SwiftUI

/// The standalone layout hierarchy for the primary "Profile" tab.
/// This acts purely as a declarative composition module that groups all massive
/// visual data visualizations (Terrarium, Heatmap) and abstracts intense offline SQLite
/// hardware calculations completely away from the orchestrator logic natively.
struct ProfileTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Binding var showPaywall: Bool
    
    // Natively isolated State variables dynamically mapped back from the background Actor mathematically.
    @State private var uniqueSpeciesCount: Int = 0
    @State private var currentStreak: Int = 0
    @State private var totalCaptures: Int = 0
    @State private var heatmapData: ProfileHeatmapData?
    @State private var awards: [AwardPayload] = []
    @State private var exploreViewModel = ExploreFeedViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            // MARK: - Core Profile Content
            VStack(spacing: 24) {
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
                .padding(.bottom, 16)

                // MARK: - User Profile
                UserProfile(
                    totalScans: totalCaptures,
                    completedAchievements: awards.completedCount
                )
                
                // MARK: - Stats
                UserStats(speciesCount: uniqueSpeciesCount, streak: currentStreak)
                
                // MARK: - Paywall & Subscriptions
                if !revenueCatManager.isProActive {
                    PlanCard(showPaywall: $showPaywall)
                }
                
                // MARK: - Heatmap
                ScansHeatmap(heatmapData: heatmapData)

                // MARK: - Public Explore Scans
                ProfilePublicScansPreview(
                    viewModel: exploreViewModel,
                    onOpenPost: openPublicScanPreview
                )
                
                // MARK: - Gamification Awards
                if !awards.isEmpty {
                    Achievements(awards: awards)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
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
                        allowsInsightPresentation: false
                    )
                }
            }
            // MARK: - Off-Thread SQLite Data Generation
            .task {
                // Decouples massive SwiftData queries explicitly into a `ModelActor` to completely 
                // prevent dropping frames on the physical UI Thread during millions of array computations.
                let container = modelContext.container
                let actor = ProfileDatabaseActor(modelContainer: container)
                let stats = await actor.calculateAll()
                await MainActor.run {
                    self.uniqueSpeciesCount = stats.speciesCount
                    self.currentStreak = stats.streak
                    self.totalCaptures = stats.heatmap.totalCaptures
                    self.heatmapData = stats.heatmap
                    self.awards = stats.awards
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry identical to SettingsTabView!
        .containerRelativeFrame(.horizontal)
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
}

private extension [AwardPayload] {
    var completedCount: Int {
        filter(\.isCompleted).count
    }
}
