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

    @ViewBuilder
    func imageOverlayToolbarIconChrome(
        isFallbackActive: Bool,
        foregroundColor: Color = .white
    ) -> some View {
        if isFallbackActive {
            self
                .foregroundStyle(foregroundColor)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .circularMaterialControl(
                    size: 44,
                    material: .ultraThinMaterial,
                    colorScheme: .dark,
                    borderColor: .white.opacity(0.18),
                    borderWidth: 0.75
                )
        } else {
            self
        }
    }

    @ViewBuilder
    func imageOverlayToolbarButtonChrome(isFallbackActive: Bool) -> some View {
        if isFallbackActive {
            self
                .buttonStyle(.plain)
                .contentShape(Circle())
        } else {
            self
        }
    }
}

enum ImageOverlayToolbarChrome {
    static var shouldUseContainedBackground: Bool {
        if #available(iOS 26.0, *) {
            return false
        } else {
            return true
        }
    }
}
