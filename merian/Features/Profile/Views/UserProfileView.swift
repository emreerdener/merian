import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // User Header
                    UserProfileHeaderView(supabase: supabase) {
                        showSettings = true
                    }
                    .padding(.top, 32)

                     // Lifetime Explorer Aggregates
                    VStack(alignment: .leading, spacing: 16) {
                        
                        UserProfileStatsView()
                        .padding(.horizontal, 24)
                    }
                    

                    
                 
                    
                   
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}


