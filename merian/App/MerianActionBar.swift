import SwiftUI
import PhotosUI
import SwiftData

struct MerianActionBar: View {
    @Binding var isLifeListOpen: Bool
    @Binding var isPaywallOpen: Bool
    @Binding var isInsightSheetOpen: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @EnvironmentObject var usageManager: UsageManager
    @EnvironmentObject var gamificationManager: GamificationManager
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var hardwareOrchestrator = HardwareOrchestrator.shared
    
    var body: some View {
        HStack {
            // Life List
            Button(action: {
                isLifeListOpen = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            // Gamification
            Button(action: {
                gamificationManager.showTerrariumSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // The Shutter / Analyze Button
            Button(action: {
                if usageManager.canPerformScan(isProActive: revenueCatManager.isProActive) {
                    Task {
                        do {
                            let captureData = try await cameraManager.captureImage()
                            OfflineQueueManager.shared.enqueueCapture(imageData: captureData)
                            
                            await MainActor.run {
                                inferenceEngine.analyze(imageData: captureData, modelContext: modelContext)
                                usageManager.recordSuccessfulScan()
                                gamificationManager.recordNewSpeciesDiscovered()
                                AppTelemetry.trackScan(isPro: revenueCatManager.isProActive)
                                isInsightSheetOpen = true
                            }
                        } catch {
                            print("⚠️ Shutter failure: \(error.localizedDescription)")
                        }
                    }
                } else {
                    // User hit the strict architectural boundary of 3 free logs
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
            
            // Photo Library Picker Right Overlay
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: "photo.on.rectangle")
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // State-based Glassmorphism
        .background(
            Group {
                if hardwareOrchestrator.isGlassmorphismEnabled {
                    VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                } else {
                    Color.black.opacity(0.85)
                }
            }
        )
        .clipShape(Capsule())
        .padding(.horizontal, 30)
        .padding(.bottom, 40)
    }
}
