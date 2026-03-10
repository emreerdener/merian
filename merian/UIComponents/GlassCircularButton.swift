import SwiftUI

struct GlassCircularButton: View {
    let iconName: String
    var iconColor: Color = .white
    let action: () -> Void
    
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if hardwareOrchestrator.isGlassmorphismEnabled {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .frame(width: 50, height: 50)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 50, height: 50)
                }
                
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }
        }
    }
}
