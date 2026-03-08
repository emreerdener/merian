import SwiftUI
import PhotosUI
import SwiftData

struct MerianActionBar: View {
    @Binding var isLifeListOpen: Bool
    @Binding var isPaywallOpen: Bool
    @Binding var isInsightSheetOpen: Bool
    @Binding var isAnalyzingFullscreen: Bool
    
    var onCaptureTriggered: () -> Void
    
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
                    Group {
                        if hardwareOrchestrator.isGlassmorphismEnabled {
                            VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                        } else {
                            Color.black.opacity(0.7)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    
                    Image(systemName: "book")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            
            // The Shutter / Analyze Button
            Button(action: {
                if usageManager.canPerformScan(isProActive: revenueCatManager.isProActive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCaptureTriggered()
                    Task {
                        do {
                            let captureData = try await cameraManager.captureImage()
                            OfflineQueueManager.shared.enqueueCapture(imageData: captureData)
                            
                            await MainActor.run {
                                inferenceEngine.analyze(imageData: captureData, modelContext: modelContext)
                                usageManager.recordSuccessfulScan()
                                gamificationManager.recordNewSpeciesDiscovered()
                                AppTelemetry.trackScan(isPro: revenueCatManager.isProActive)
                                isAnalyzingFullscreen = true
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
            .frame(maxWidth: .infinity)
            
            // User Profile Button
            Button(action: {
                isPaywallOpen = true
            }) {
                ZStack {
                    Group {
                        if hardwareOrchestrator.isGlassmorphismEnabled {
                            VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                        } else {
                            Color.black.opacity(0.7)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    
                    Image(systemName: "person")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .padding(.bottom, 24)
    }
}
