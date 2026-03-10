import SwiftUI
import PhotosUI
import SwiftData

struct MerianActionBar: View {
    @Binding var isLifeListOpen: Bool
    @Binding var isPaywallOpen: Bool
    @Binding var isInsightSheetOpen: Bool
    @Binding var isAnalyzingFullscreen: Bool
    @Binding var isUserProfileOpen: Bool
    @Binding var imageToCrop: IdentifiableImage?
    
    var onCaptureTriggered: () -> Void
    
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @EnvironmentObject var usageManager: UsageManager
    @EnvironmentObject var gamificationManager: GamificationManager
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    var body: some View {
        HStack {
            // Life List
            GlassCircularButton(iconName: "book") {
                isLifeListOpen = true
            }
            
            Spacer()
            
            // The Shutter / Analyze Button
            Button(action: {
                if usageManager.canPerformScan(isProActive: revenueCatManager.isProActive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCaptureTriggered()
                    Task {
                        do {
                            let captureData = try await cameraManager.captureImage()
                            
                            // Actively push the original 12MP buffer down natively into the user's Camera Roll securely
                            await PhotoLibraryManager.shared.saveImageToLibrary(imageData: captureData)
                            
                            if let rawImage = UIImage(data: captureData) {
                                await MainActor.run {
                                    imageToCrop = IdentifiableImage(image: rawImage)
                                }
                            }
                        } catch {
                            print("⚠️ Shutter failure: \(error.localizedDescription)")
                        }
                    }
                } else {
                    AppTelemetry.trackPaywallImpression()
                    isPaywallOpen = true
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 62, height: 62)
                }
            }
            
            Spacer()
            
            // User Profile Button
            GlassCircularButton(iconName: "person") {
                isUserProfileOpen = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .padding(.bottom, 24)
    }
}

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // User Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.gray)
                            .padding(.bottom, 8)
                        
                        Text("Explorer Profile")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Connect an account to securely sync your life list across Apple devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)
                    
                    // Authentication Layer
                    if !SupabaseManager.shared.isAuthenticated {
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
                                    Text("Sign Out")
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
                    
                    // Lifetime Explorer Aggregates
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Lifetime Stats")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCardView(title: "Species", value: "4", icon: "leaf.fill", color: .green)
                            StatCardView(title: "Current Streak", value: "3 Days", icon: "flame.fill", color: .orange)
                            StatCardView(title: "Rare Finds", value: "1", icon: "sparkles", color: .purple)
                            StatCardView(title: "Persona", value: "Novice Botanist", icon: "tree.fill", color: .teal)
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
