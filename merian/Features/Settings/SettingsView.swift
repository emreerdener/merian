import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showPaywall = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
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
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("Settings")
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
