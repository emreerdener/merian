import SwiftUI
import RiveRuntime

// 1. Digital Terrarium Integration mapping directly to users' physical taxonomical growth
struct TerrariumView: View {
    @EnvironmentObject var gamificationManager: GamificationManager
    
    // Connect explicitly into the custom animated .riv asset file and corresponding state architecture
    @StateObject private var terrariumVM = RiveViewModel(
        fileName: "merian_terrarium",
        stateMachineName: "TerrariumInteractions"
    )
    
    var body: some View {
        ZStack {
            // Glassmorphic interactive circle backdrop
            Circle()
                .fill(.ultraThinMaterial)
            
            // Direct injection of the Rive Renderer layer via wrapper protocols
            terrariumVM.view()
                .clipShape(Circle())
        }
        .onTapGesture {
            // Explicit user engagement triggering kinetic environment shifts
            terrariumVM.triggerInput("UserTapped")
            HapticManager.shared.triggerSelectionPulse()
        }
        // 2. Continuous State Sync Pipeline observing changes passively
        .onChange(of: gamificationManager.unlockedSpeciesCount) { _, newValue in
            terrariumVM.setInput("TotalSpeciesCount", value: Double(newValue))
        }
        .onChange(of: gamificationManager.hasFireflyBadge) { _, newValue in
            terrariumVM.setInput("ShowFireflies", value: newValue)
        }
        // 3. Initial sync cascade
        .onAppear {
            terrariumVM.setInput("TotalSpeciesCount", value: Double(gamificationManager.unlockedSpeciesCount))
            terrariumVM.setInput("ShowFireflies", value: gamificationManager.hasFireflyBadge)
        }
    }
}
