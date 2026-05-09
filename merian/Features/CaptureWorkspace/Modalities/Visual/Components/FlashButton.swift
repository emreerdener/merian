import SwiftUI

struct FlashButton: View {
    let isFlashEnabled: Bool
    let onToggleFlash: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse()
            onToggleFlash()
        }) {
            Image(systemName: isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isFlashEnabled ? .yellow : .white)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}
