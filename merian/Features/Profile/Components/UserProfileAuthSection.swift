import SwiftUI

struct UserProfileAuthSection: View {
    @ObservedObject var supabase: SupabaseManager
    
    var body: some View {
        if !supabase.isGuestUser {
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
