import SwiftUI
import SwiftData

struct UserProfileHeaderView: View {
    @ObservedObject var supabase: SupabaseManager
    @Environment(\.modelContext) private var modelContext
    
    var onSettingsTap: () -> Void
    
    @State private var uniqueSpeciesCount: Int = 0
    
    private var persona: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "Observer" }
        else if count < 10 { return "Novice Naturalist" }
        else if count < 50 { return "Field Naturalist" }
        else if count < 100 { return "Avid Naturalist" }
        else { return "Master Naturalist" }
    }
    
    private var personaDescription: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "Just starting to explore the natural world." }
        else if count < 10 { return "Learning to identify local flora and fauna." }
        else if count < 50 { return "Actively discovering new species." }
        else if count < 100 { return "A dedicated explorer with a keen eye." }
        else { return "An expert observer of the ecosystem." }
    }
    
    private var userName: String? {
        supabase.currentUser?.userMetadata["full_name"]?.stringValue ?? supabase.currentUser?.userMetadata["name"]?.stringValue
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
                    .font(.system(.title, design: .serif))
                    .fontWeight(.bold)
                
                Text(personaDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            UserProfileStatsView()

            // Authentication / User Profile Block
            VStack {
                if supabase.isGuestUser {
                    // Sign In Flow
                    VStack(spacing: 12) {
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
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("Connected account")
                                .font(.caption)
                                .foregroundColor(.secondary)
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

        }
        .task {
            let container = modelContext.container
            let actor = ProfileDatabaseActor(modelContainer: container)
            let (species, _) = await actor.calculateProfileStats()
            await MainActor.run {
                self.uniqueSpeciesCount = species
            }
        }
    }
}
