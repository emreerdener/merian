import SwiftUI

// MARK: - Helper Views
struct Badge: View {
    let text: String
    var color: Color = .primary
    var icon: String? = nil
    var isFilled: Bool = false
    
    private var isNeutralColor: Bool {
        color == .white || color == .gray || color == .secondary || color == .primary
    }
    
    private var activeForegroundColor: Color {
        if isFilled { return .white } // Inverse typography
        return isNeutralColor ? .primary : color.opacity(0.95)
    }
    
    private var activeStrokeColor: Color {
        if isFilled { return Color.white.opacity(0.3) } // Apply a sleek white boundary globally
        return isNeutralColor ? Color.primary.opacity(0.15) : color.opacity(0.3)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if let validIcon = icon {
                Image(systemName: validIcon)
                    .imageScale(.medium)
            }
            Text(text)
                .lineLimit(1) 
                .truncationMode(.tail)
        }
        .font(.system(.subheadline, weight: .bold))
        .foregroundColor(activeForegroundColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false) // Auto-hug layout lock
        // Combines pristine system glass materials with a 15% dynamic color wash for heavily saturated, vibrant Apple-tier tinted background aesthetics natively.
        .background {
            if isFilled {
                Capsule()
                    .fill(color)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(color.opacity(0.15))
            }
        }
        .overlay(
            Capsule()
                .stroke(activeStrokeColor, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}
