import RiveRuntime
import SwiftUI

// 1. Digital Terrarium Integration mapping directly to users' physical taxonomical growth
struct Terrarium: View {
    @Environment(GamificationManager.self) var gamificationManager
    
    // Safety check to prevent crashing if the .riv file hasn't been bundled by the designer yet
    private var isRiveFileBundled: Bool {
        Bundle.main.url(forResource: "merian_terrarium", withExtension: "riv") != nil
    }
    
    var body: some View {
        ZStack {
            if isRiveFileBundled {
                ActiveTerrariumRenderer()
            } else {
                // Temporary static orb placeholder
                Image("profile_scene")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.0)
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(Circle())
    }
}

/// Subview explicitly separating the Rive initialization so it isn't eagerly evaluated by the SwiftUI engine
private struct ActiveTerrariumRenderer: View {
    @Environment(GamificationManager.self) var gamificationManager
    
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
