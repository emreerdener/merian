import SwiftUI

struct ThermalWarningView: View {
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    
    var body: some View {
        Group {
            if hardwareOrchestrator.isCriticalHeatWarningActive {
                Text("DEVICE CRITICAL HEAT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hardwareOrchestrator.isCriticalHeatWarningActive)
    }
}
