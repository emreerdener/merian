import SwiftUI

// MARK: - Helper Views
struct Badge: View {
    let text: String
    let color: Color
    let icon: String
    var isFilled: Bool = false
    
    private var isNeutralColor: Bool {
        color == .white || color == .gray || color == .secondary
    }
    
    private var foregroundColor: Color {
        if isFilled { return .white } // Inverse typography
        return isNeutralColor ? .white : color.opacity(0.95)
    }
    
    private var backgroundColor: Color {
        if isFilled { return color.opacity(0.6) } // Synthesized Colored Liquid Glass
        return isNeutralColor ? Color.white.opacity(0.15) : color.opacity(0.2)
    }
    
    private var strokeColor: Color {
        if isFilled { return Color.white.opacity(0.3) } // Apply a sleek white boundary so it pops!
        return isNeutralColor ? Color.white.opacity(0.3) : color.opacity(0.3)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 16, height: 16)
            Text(text)
        }
        .font(.system(.footnote))
        .fontWeight(.bold)
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isFilled ? AnyShapeStyle(color) : AnyShapeStyle(backgroundColor),
            in: Capsule()
        )
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(strokeColor, lineWidth: 0.5)
        )
    }
}
