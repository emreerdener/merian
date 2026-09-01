import SwiftUI

struct ScrollAwareToolbarTitleBadge: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let isVisible: Bool

    private var maximumWidth: CGFloat {
        horizontalSizeClass == .regular ? 320 : 200
    }

    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: maximumWidth)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                    )
                    .accessibilityLabel(title)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.8),
            value: isVisible
        )
        .accessibilityHidden(!isVisible || title.isEmpty)
    }
}
