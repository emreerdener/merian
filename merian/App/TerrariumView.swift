import SwiftUI
import RiveRuntime

extension HapticManager {
    func triggerSelectionPulse() {
        print("Selection Pulse Haptic successfully fired.")
    }
}

// 1. Digital Terrarium Integration mapping directly to users' physical taxonomical growth
struct TerrariumView: View {
    // Stat dependencies pulling naturally from standard global bounds
    let unlockedSpeciesCount: Int
    let hasFireflyBadge: Bool
    
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
        .onChange(of: unlockedSpeciesCount) { _, newValue in
            terrariumVM.setInput("TotalSpeciesCount", value: Double(newValue))
        }
        .onChange(of: hasFireflyBadge) { _, newValue in
            terrariumVM.setInput("ShowFireflies", value: newValue)
        }
        // 3. Initial sync cascade
        .onAppear {
            terrariumVM.setInput("TotalSpeciesCount", value: Double(unlockedSpeciesCount))
            terrariumVM.setInput("ShowFireflies", value: hasFireflyBadge)
        }
    }
}
