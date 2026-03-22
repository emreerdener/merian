import SwiftUI

/// Abstracted Profile identity component natively interpreting both Ghost mode states
/// and dynamically rendering high-fidelity Auth provider payloads seamlessly.
struct UserProfile: View {
    var supabase: SupabaseManager
    
    @State private var showSignOutConfirmation = false
    
    // Natively distills nested JSON metadata payloads dropping safely through multiple vendor formats securely
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
        VStack {
            if supabase.isGuestUser {
                // Ghost Mode: Sign In Flow
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
                    
                    // Uses Apple's `.ultraThinMaterial` bounded to a crisp `Circle()` stroke 
                    // dropping flawlessly over dynamic user photography directly.
                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.secondary.opacity(0.15))
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .confirmationDialog("Account options", isPresented: $showSignOutConfirmation, titleVisibility: .hidden) {
                        Button("Sign out", role: .destructive) {
                            Task {
                                // Forces a clean physical JWT removal across the device securely
                                // instantly rehydrating back into a zero-bound Ghost mode state.
                                await supabase.signOut()
                                await supabase.initializeGhostSession()
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
            }
        }
    }
}
