import SwiftUI

/// Abstracted Profile identity component natively interpreting both Ghost mode states
/// and dynamically rendering high-fidelity Auth provider payloads seamlessly.
struct UserProfile: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    
    var body: some View {
        VStack {
            if profileViewModel.isGuestUser {
                // Ghost Mode: Sign In Flow
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await profileViewModel.signInWithApple()
                        }
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
                            await profileViewModel.signInWithGoogle()
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
                    if let avatarURL = profileViewModel.userAvatarURL {
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
                        Text(profileViewModel.userName ?? "Explorer")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(profileViewModel.userEmail ?? "Connected account")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    // Uses Apple's native `Menu` popover rendering to dynamically bind 
                    // a systemic "liquid glass" context menu perfectly blurring behind the options.
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                // Forces a clean physical JWT removal across the device securely
                                // instantly rehydrating back into a zero-bound Ghost mode state.
                                await profileViewModel.signOut()
                            }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
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
