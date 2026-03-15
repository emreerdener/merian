import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showPaywall = false
    
    private var uniqueSpeciesCount: Int {
        Set(allRecords.map { $0.scientificName }).count
    }
    
    private var userName: String? {
        supabase.currentUser?.userMetadata["full_name"]?.stringValue ?? supabase.currentUser?.userMetadata["name"]?.stringValue
    }
    
    private var userAvatarURL: URL? {
        if let avatarStr = supabase.currentUser?.userMetadata["avatar_url"]?.stringValue ?? supabase.currentUser?.userMetadata["picture"]?.stringValue,
           let url = URL(string: avatarStr) {
            return url
        }
        return nil
    }
    
    private var currentStreak: Int {
        let calendar = Calendar.current
        let sortedDates = Array(Set(allRecords.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        
        var streak = 0
        let today = calendar.startOfDay(for: Date())
        var expectedDate = today
        
        if !sortedDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), sortedDates.contains(yesterday) {
                expectedDate = yesterday
            } else {
                return 0
            }
        }
        
        for date in sortedDates {
            if calendar.isDate(date, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else {
                break
            }
        }
        
        return streak
    }
    
    private var rareFindsCount: Int {
        allRecords.filter { $0.ecologyType.lowercased() == "wild" && $0.isBiological }.count
    }
    
    private var persona: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "Observer" }
        else if count < 10 { return "Novice Botanist" }
        else if count < 50 { return "Field Explorer" }
        else if count < 100 { return "Avid Naturalist" }
        else { return "Master Biologist" }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // User Header
                    VStack(spacing: 8) {
                        if let avatarURL = userAvatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .padding(.bottom, 8)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                                .padding(.bottom, 8)
                        }
                        
                        Text(userName ?? "Explorer Profile")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Connect an account to securely sync your life list across Apple devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)

                     // Lifetime Explorer Aggregates
                    VStack(alignment: .leading, spacing: 16) {
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCardView(title: "Species", value: "\(uniqueSpeciesCount)", icon: "leaf.fill", color: .green)
                            StatCardView(title: "Current Streak", value: "\(currentStreak) Day\(currentStreak == 1 ? "" : "s")", icon: "flame.fill", color: .orange)
                            StatCardView(title: "Rare Finds", value: "\(rareFindsCount)", icon: "sparkles", color: .purple)
                            StatCardView(title: "Persona", value: persona, icon: "tree.fill", color: .teal)
                        }
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
                    if SupabaseManager.shared.isGuestUser {
                        VStack(spacing: 16) {
                            Button(action: {
                                SupabaseManager.shared.startAppleSignIn()
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
                                    await SupabaseManager.shared.signInWithGoogle()
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
                        .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 16) {
                            Button(action: {
                                Task {
                                    await SupabaseManager.shared.signOut()
                                    // Make sure User is sent anonymously again securely
                                    await SupabaseManager.shared.initializeGhostSession()
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
