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
    @State private var heatmapData: ProfileHeatmapData? = nil
    
    var body: some View {
        List {
            // MARK: - Core Profile Content
            Section {
                VStack(spacing: 24) {
                    // MARK: - Terrarium
                    Terrarium()
                    
                    // MARK: - User Persona
                    Persona(uniqueSpeciesCount: uniqueSpeciesCount)

                    // MARK: - User Profile
                    UserProfile(supabase: supabase)
                    
                    // MARK: - Stats
                    UserStats()
                    
                    // MARK: - Heatmap
                    ScansHeatmap(heatmapData: heatmapData)
          
                    // MARK: - Paywall & Subscriptions
                    PlanCard(showPaywall: $showPaywall)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                        .environment(RevenueCatManager.shared)
                }
                // MARK: - Off-Thread SQLite Data Generation
                // Background actor execution is explicitly tied to the native SwiftUI view lifecycle natively, 
                // guaranteeing absolute thread cancellation natively bounding memory leaks!
                .task {
                    // Decouples massive SwiftData queries explicitly into a `ModelActor` to completely 
                    // prevent dropping frames on the physical UI Thread during millions of array computations.
                    let container = modelContext.container
                    let actor = ProfileDatabaseActor(modelContainer: container)
                    let (species, _) = await actor.calculateProfileStats()
                    let heatmap = await actor.calculateHeatmapData()
                    await MainActor.run {
                        self.uniqueSpeciesCount = species
                        self.heatmapData = heatmap
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(InsetGroupedListStyle())
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry identical to SettingsTabView!
        .containerRelativeFrame(.horizontal)
    }
}
