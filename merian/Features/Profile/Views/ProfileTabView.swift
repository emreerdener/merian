import SwiftUI
import SwiftData

/// The standalone layout hierarchy for the primary "Profile" tab.
/// This acts purely as a declarative composition module that groups all massive
/// visual data visualizations (Terrarium, Heatmap) and abstracts intense offline SQLite
/// hardware calculations completely away from the orchestrator logic natively.
struct ProfileTabView: View {
    var supabase: SupabaseManager
    @Environment(\.modelContext) private var modelContext
    @Binding var showPaywall: Bool
    
    // Natively isolated State variables dynamically mapped back from the background Actor mathematically.
    @State private var uniqueSpeciesCount: Int = 0
    @State private var currentStreak: Int = 0
    @State private var heatmapData: ProfileHeatmapData? = nil
    @State private var awards: [AwardPayload] = []
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            // MARK: - Core Profile Content
            VStack(spacing: 24) {
                // MARK: - Terrarium
                Terrarium()
                
                // MARK: - User Persona
                Persona(uniqueSpeciesCount: uniqueSpeciesCount)

                // MARK: - User Profile
                UserProfile(supabase: supabase)
                
                // MARK: - Stats
                UserStats(speciesCount: uniqueSpeciesCount, streak: currentStreak)
                
                // MARK: - Paywall & Subscriptions
                PlanCard(showPaywall: $showPaywall)
                
                // MARK: - Heatmap
                ScansHeatmap(heatmapData: heatmapData)
                
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
            // MARK: - Off-Thread SQLite Data Generation
            .task {
                // Decouples massive SwiftData queries explicitly into a `ModelActor` to completely 
                // prevent dropping frames on the physical UI Thread during millions of array computations.
                let container = modelContext.container
                let actor = ProfileDatabaseActor(modelContainer: container)
                let (species, streak) = await actor.calculateProfileStats()
                let heatmap = await actor.calculateHeatmapData()
                let fetchedAwards = await actor.calculateAwards()
                await MainActor.run {
                    self.uniqueSpeciesCount = species
                    self.currentStreak = streak
                    self.heatmapData = heatmap
                    self.awards = fetchedAwards
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry identical to SettingsTabView!
        .containerRelativeFrame(.horizontal)
    }
}
