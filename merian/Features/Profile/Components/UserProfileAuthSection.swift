import SwiftUI

struct UserProfileAuthSection: View {
    @ObservedObject var supabase: SupabaseManager
    
    var body: some View {
        if !supabase.isGuestUser {
            Button(action: {
                Task {
                    await supabase.signOut()
                    // Make sure User is sent anonymously again securely
                    await supabase.initializeGhostSession()
                }
            }) {
                Text("Sign out")
                    .foregroundColor(.red)
            }
        }
    }
}
