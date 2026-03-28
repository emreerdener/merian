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
    
    var body: some View {
        HStack(spacing: 6) {
            if let validIcon = icon {
                Image(systemName: validIcon)
                    .imageScale(.medium)
                    .frame(width: 16, alignment: .center)
            }
            Text(text)
                .lineLimit(1) 
                .truncationMode(.tail)
        }
        .font(.system(.subheadline, weight: .bold))
        // Adapt contrast based on the fill style
        .foregroundColor(isFilled ? .white : color)
        .shadow(color: isFilled ? .black.opacity(0.15) : .clear, radius: 2, x: 0, y: 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Group {
                if isFilled {
                    // Liquid Glass Background Stack applied globally
                    ZStack {
                        // Blurred System Glass Foundation
                        Capsule()
                            .fill(.ultraThickMaterial)
                        
                        // Volumetric Color Tint adapting to passed properties
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        isNeutralColor ? .gray.opacity(0.6) : color.opacity(0.9),
                                        isNeutralColor ? .gray.opacity(0.5) : color.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Glossy Inner Rim Highlight
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .white.opacity(0.0), .white.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                } else {
                    // Outlined metadata tag background
                    Capsule()
                        .fill(color.opacity(0.15))
                }
            }
        )
        // Ambient Static Glass Boundary
        .overlay(
            Capsule()
                .strokeBorder(isFilled ? (isNeutralColor ? .gray.opacity(0.2) : color.opacity(0.2)) : color.opacity(0.5), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}
