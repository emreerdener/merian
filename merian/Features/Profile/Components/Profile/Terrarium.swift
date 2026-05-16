import RiveRuntime
import SwiftUI

// 1. Digital Terrarium Integration mapping directly to users' physical taxonomical growth
struct Terrarium: View {
    let uniqueSpeciesCount: Int
    
    // Safety check to prevent crashing if the .riv file hasn't been bundled by the designer yet
    private var isRiveFileBundled: Bool {
        Bundle.main.url(forResource: "merian_terrarium", withExtension: "riv") != nil
    }
    
    private var persona: UserPersona {
        UserPersona(speciesCount: uniqueSpeciesCount)
    }
    
    var body: some View {
        ZStack {
            if isRiveFileBundled {
                ActiveTerrariumRenderer(uniqueSpeciesCount: uniqueSpeciesCount)
            } else {
                // Conditional persona image placeholder
                Image(persona.imageName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 300, height: 260)
    }
}

/// Subview explicitly separating the Rive initialization so it isn't eagerly evaluated by the SwiftUI engine
private struct ActiveTerrariumRenderer: View {
    let uniqueSpeciesCount: Int
    @Environment(GamificationManager.self) var gamificationManager
    
    @StateObject private var terrariumVM = RiveViewModel(
        fileName: "merian_terrarium",
        stateMachineName: "TerrariumInteractions"
    )
    
    var body: some View {
        terrariumVM.view()
            .onTapGesture {
                terrariumVM.triggerInput("UserTapped")
                HapticManager.shared.triggerSelectionPulse()
            }
            .onChange(of: uniqueSpeciesCount, initial: true) { _, newValue in
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
