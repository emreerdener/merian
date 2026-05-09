import SwiftUI

/// Shared chrome for compact circular controls that already own their own
/// icon, color, haptics, action semantics, and accessibility labels.
struct CircularMaterialControlModifier: ViewModifier {
    let size: CGFloat
    let material: Material
    let colorScheme: ColorScheme?
    let borderColor: Color?
    let borderWidth: CGFloat

    func body(content: Content) -> some View {
        applyColorScheme(
            to: content
                .frame(width: size, height: size)
                .background(material, in: Circle())
                .overlay {
                    if let borderColor {
                        Circle()
                            .stroke(borderColor, lineWidth: borderWidth)
                    }
                }
        )
    }

    @ViewBuilder
    private func applyColorScheme<V: View>(to view: V) -> some View {
        if let colorScheme {
            view.environment(\.colorScheme, colorScheme)
        } else {
            view
        }
    }
}

extension View {
    func circularMaterialControl(
        size: CGFloat = 50,
        material: Material = .ultraThinMaterial,
        colorScheme: ColorScheme? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0.5
    ) -> some View {
        modifier(CircularMaterialControlModifier(
            size: size,
            material: material,
            colorScheme: colorScheme,
            borderColor: borderColor,
            borderWidth: borderWidth
        ))
    }
}
