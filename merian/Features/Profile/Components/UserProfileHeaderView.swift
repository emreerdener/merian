import SwiftUI
import SwiftData

struct UserProfileHeaderView: View {
    @ObservedObject var supabase: SupabaseManager
    @Environment(\.modelContext) private var modelContext
    
    @Binding var showPaywall: Bool
    var onSettingsTap: () -> Void
    
    @State private var uniqueSpeciesCount: Int = 0
    @State private var heatmapData: ProfileHeatmapData? = nil
    
private var persona: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "The Observer" }
        else if count < 10 { return "Casual Explorer" }
        else if count < 50 { return "Dedicated Naturalist" }
        else if count < 100 { return "Verified Scholar" }
        else { return "Apex Observer" }
    }
    
    private var personaDescription: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "The viewfinder is ready. Step outside to log your first scan." }
        else if count < 10 { return "Starting your collection. Learning the language of local flora and fauna." }
        else if count < 50 { return "Mapping local biodiversity and building a vibrant library." }
        else if count < 100 { return "Curating a museum-grade archive of the natural world." }
        else { return "An absolute authority on the ecosystem. Your collection is a masterpiece." }
    }
    
    private var userName: String? {
        supabase.currentUser?.userMetadata["full_name"]?.stringValue ?? supabase.currentUser?.userMetadata["name"]?.stringValue
    }
    
    private var userEmail: String? {
        supabase.currentUser?.email
    }
    
    private var userAvatarURL: URL? {
        if let avatarStr = supabase.currentUser?.userMetadata["avatar_url"]?.stringValue ?? supabase.currentUser?.userMetadata["picture"]?.stringValue,
           let url = URL(string: avatarStr) {
            return url
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Digital Terrarium Hero Placeholer
            TerrariumView()
                
            // Persona Title & Description
            VStack(spacing: 8) {
                Text(persona)
                    .font(.system(.largeTitle, design: .serif))
                    .fontWeight(.bold)
                
                Text(personaDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            UserProfileStatsView()
            
            ProfileCaptureHeatmapView(heatmapData: heatmapData)

            // Authentication / User Profile Block
            VStack {
                if supabase.isGuestUser {
                    // Sign In Flow
                    VStack(spacing: 16) {
                        Button(action: {
                            supabase.startAppleSignIn()
                        }) {
                            HStack {
                                Image(systemName: "applelogo")
                                Text("Sign in with Apple")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        
                        Button(action: {
                            Task {
                                await supabase.signInWithGoogle()
                            }
                        }) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Authenticated User Profile Card
                    HStack(spacing: 12) {
                        if let avatarURL = userAvatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 48, height: 48)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(userName ?? "Explorer")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text(userEmail ?? "Connected account")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                }
            }
            
            // Manage plan Action Component
            UserProfilePlanComponent(showPaywall: $showPaywall)
        }
        .task {
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
}
