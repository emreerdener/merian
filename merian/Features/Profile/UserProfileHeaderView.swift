import SwiftUI

struct UserProfileHeaderView: View {
    @ObservedObject var supabase: SupabaseManager
    
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
        VStack(spacing: 8) {
            if let avatarURL = userAvatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .padding(.bottom, 8)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray)
                    .padding(.bottom, 8)
            }
            
            Text(userName ?? "Explorer Profile")
                .font(.title2)
                .fontWeight(.bold)
            Text("Connect an account to securely sync your life list across Apple devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
