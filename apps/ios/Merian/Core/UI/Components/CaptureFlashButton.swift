import SwiftUI

/// A presentation-only flash toggle used by the shared capture control bar.
///
/// The owning capture feature supplies both feedback and camera mutations
/// through `onToggleFlash`; this component does not resolve either service.
struct CaptureFlashButton: View {
    let isFlashEnabled: Bool
    let onToggleFlash: () -> Void

    var body: some View {
        Button(action: onToggleFlash) {
            Image(
                systemName: isFlashEnabled
                    ? "bolt.fill"
                    : "bolt.slash.fill"
            )
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(isFlashEnabled ? .yellow : .white)
            .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}
