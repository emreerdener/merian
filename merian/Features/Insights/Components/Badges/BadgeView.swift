import SwiftUI

// MARK: - Helper Views
struct BadgeView: View {
    let text: String
    let color: Color
    let icon: String
    
    private var isNeutralColor: Bool {
        color == .white || color == .gray || color == .secondary
    }
    
    private var foregroundColor: Color {
        isNeutralColor ? .white : color.opacity(0.95)
    }
    
    private var backgroundColor: Color {
        isNeutralColor ? Color.white.opacity(0.15) : color.opacity(0.2)
    }
    
    private var strokeColor: Color {
        isNeutralColor ? Color.white.opacity(0.3) : color.opacity(0.3)
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
        .background(backgroundColor)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(strokeColor, lineWidth: 0.5)
        )
    }
}
