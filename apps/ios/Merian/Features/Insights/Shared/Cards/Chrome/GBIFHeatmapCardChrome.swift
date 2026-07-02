import SwiftUI

private struct GBIFHeatmapCardChromeModifier: ViewModifier {
    private let cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.3), lineWidth: 4)
                    .blur(radius: 6)
                    .offset(y: 2)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func gbifHeatmapCardChrome() -> some View {
        modifier(GBIFHeatmapCardChromeModifier())
    }
}
