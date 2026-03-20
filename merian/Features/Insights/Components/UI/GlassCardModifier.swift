import SwiftUI

// MARK: - Global Liquid Glass Aesthetic Modifier
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
    }
}

extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}
