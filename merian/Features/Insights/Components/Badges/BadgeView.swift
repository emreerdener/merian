import SwiftUI

// MARK: - Helper Views
struct BadgeView: View {
    let text: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.footnote))
        .fontWeight(.bold)
        .foregroundColor(color == .white || color == .gray || color == .secondary ? .white : color.opacity(0.95))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color == .white || color == .gray || color == .secondary ? Color.white.opacity(0.15) : color.opacity(0.2))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(color == .white || color == .gray || color == .secondary ? Color.white.opacity(0.3) : color.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}
