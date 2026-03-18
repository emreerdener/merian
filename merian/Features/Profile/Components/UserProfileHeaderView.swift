import SwiftUI
import SwiftData

struct UserProfileHeaderView: View {
    @ObservedObject var supabase: SupabaseManager
    @Query private var allRecords: [LocalScanRecord]
    
    var onSettingsTap: () -> Void
    
    private var uniqueSpeciesCount: Int {
        Set(allRecords.compactMap { $0.scientificName }).count
    }
    
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
                .frame(height: 240)
                .padding(.top, 8)
                .padding(.bottom, 24)
                
            // Persona Title & Description
            VStack(spacing: 8) {
                Text(persona)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(personaDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Smaller User Account Card
            Button(action: {
                if userName == nil {
                    onSettingsTap()
                }
            }) {
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
                        Text(userName ?? "Guest Explorer")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if userName == nil {
                            Text("Unlinked account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Connected account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if userName == nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 24)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
