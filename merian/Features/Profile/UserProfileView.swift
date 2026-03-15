import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showPaywall = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // User Header
                    UserProfileHeaderView(supabase: supabase)
                        .padding(.top, 32)

                     // Lifetime Explorer Aggregates
                    VStack(alignment: .leading, spacing: 16) {
                        
                        UserProfileStatsView()
                        .padding(.horizontal, 24)
                    }
                    
   // Subscription Section
                    VStack(alignment: .leading, spacing: 16) {
                        Button(action: {
                            showPaywall = true
                        }) {
                            HStack {
                                Image(systemName: "star.fill")
                                Text("Manage plan")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.yellow.opacity(0.15))
                            .foregroundColor(.yellow)
                            .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .sheet(isPresented: $showPaywall) {
                            PaywallView()
                                .environmentObject(RevenueCatManager.shared)
                        }
                    }

                    // Authentication Layer
                    UserProfileAuthSection(supabase: supabase)
                        .padding(.horizontal, 24)
                    
                 
                    
                   
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
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}
