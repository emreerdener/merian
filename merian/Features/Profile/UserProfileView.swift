import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @Binding var showSettings: Bool
    
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
                    
                    // Settings List Item
                    VStack {
                        Button(action: { showSettings = true }) {
                            HStack {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 32)
                                
                                Text("Settings")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
            // Toolbars moved to MainTabView
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
