import SwiftUI
import PhotosUI

struct ThermalWarningOverlay: View {
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    var body: some View {
        if hardwareOrchestrator.isCriticalHeatWarningActive {
            VStack {
                Text("DEVICE CRITICAL HEAT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                Spacer()
            }
            .padding(.top, 40)
        }
    }
}

struct ViewfinderHintBanner: View {
    @EnvironmentObject var vui: ViewfinderIntelligence
    
    var body: some View {
        if !vui.isOptimal {
            Text(vui.currentHint.rawValue)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Capsule())
                .padding(.bottom, 16)
        }
    }
}


