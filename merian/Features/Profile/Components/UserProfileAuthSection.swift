import SwiftUI

struct UserProfileAuthSection: View {
    @ObservedObject var supabase: SupabaseManager
    
    var body: some View {
        if supabase.isGuestUser {
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
                    .cornerRadius(14)
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
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
                }
            }
        } else {
            VStack(spacing: 16) {
                Button(action: {
                    Task {
                        await supabase.signOut()
                        // Make sure User is sent anonymously again securely
                        await supabase.initializeGhostSession()
                    }
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(14)
                }
            }
        }
    }
}
