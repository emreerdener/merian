import SwiftUI
import RiveRuntime

// 1. Digital Terrarium Integration mapping directly to users' physical taxonomical growth
struct TerrariumView: View {
    @EnvironmentObject var gamificationManager: GamificationManager
    
    // Safety check to prevent crashing if the .riv file hasn't been bundled by the designer yet
    private var isRiveFileBundled: Bool {
        Bundle.main.url(forResource: "merian_terrarium", withExtension: "riv") != nil
    }
    
    var body: some View {
        ZStack {
            // Glassmorphic interactive circle backdrop
            Circle()
                .fill(.ultraThinMaterial)
            
            if isRiveFileBundled {
                ActiveTerrariumRenderer()
            } else {
                // Graceful fallback placeholder alerting the team
                VStack(spacing: 12) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green.opacity(0.8))
                    Text("Digital Terrarium")
                        .font(.headline)
                    Text("merian_terrarium.riv missing from bundle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(40)
    }
}

/// Subview explicitly separating the Rive initialization so it isn't eagerly evaluated by the SwiftUI engine
private struct ActiveTerrariumRenderer: View {
    @EnvironmentObject var gamificationManager: GamificationManager
    
    @StateObject private var terrariumVM = RiveViewModel(
        fileName: "merian_terrarium",
        stateMachineName: "TerrariumInteractions"
    )
    
    var body: some View {
        terrariumVM.view()
            .clipShape(Circle())
            .onTapGesture {
                terrariumVM.triggerInput("UserTapped")
                HapticManager.shared.triggerSelectionPulse()
            }
            .onChange(of: gamificationManager.unlockedSpeciesCount) { _, newValue in
                terrariumVM.setInput("TotalSpeciesCount", value: Double(newValue))
            }
            .onChange(of: gamificationManager.hasFireflyBadge) { _, newValue in
                terrariumVM.setInput("ShowFireflies", value: newValue)
            }
            .onAppear {
                terrariumVM.setInput("TotalSpeciesCount", value: Double(gamificationManager.unlockedSpeciesCount))
                terrariumVM.setInput("ShowFireflies", value: gamificationManager.hasFireflyBadge)
            }
    }
}
