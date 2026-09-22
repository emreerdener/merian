import SwiftUI

/// Shared appearance for the Capture row's secondary controls. Callers retain
/// their foreground, animation, accessibility, and action semantics.
private struct CaptureAuxiliaryControlModifier: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .frame(width: 50, height: 50)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())
        } else {
            content
                .frame(width: 50, height: 50)
                .background(tint ?? .clear, in: Circle())
                .circularMaterialControl(
                    borderColor: .primary.opacity(0.15)
                )
        }
    }
}

extension View {
    func captureAuxiliaryControl(tint: Color? = nil) -> some View {
        modifier(CaptureAuxiliaryControlModifier(tint: tint))
    }
}
