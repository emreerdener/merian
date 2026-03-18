import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showSettings = false
    
    var body: some View {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape")
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

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}
