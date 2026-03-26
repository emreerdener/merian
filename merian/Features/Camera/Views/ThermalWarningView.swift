import SwiftUI

struct ThermalWarningView: View {
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    
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
            .allowsHitTesting(false)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: hardwareOrchestrator.isCriticalHeatWarningActive)
    }
}
