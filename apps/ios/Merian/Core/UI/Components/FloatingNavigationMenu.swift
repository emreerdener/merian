import SwiftUI

struct FloatingNavigationMenu<Content: View>: View {
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat = FloatingNavigationMenuMetrics.itemSpacing,
        horizontalPadding: CGFloat = FloatingNavigationMenuMetrics.horizontalPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.vertical, FloatingNavigationMenuMetrics.verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 8)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

struct FloatingNavigationMenuButton: View {
    let iconName: String
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void
    var isDisabled: Bool = false
    var isSelected: Bool = false
    var showBadge: Bool = false
    var chipText: String?

    var body: some View {
        Button(action: action) {
            VStack(spacing: FloatingNavigationMenuMetrics.labelSpacing) {
                Image(systemName: iconName)
                    .font(.system(
                        size: FloatingNavigationMenuMetrics.iconSize,
                        weight: isSelected ? .semibold : .regular
                    ))
                    .frame(
                        width: FloatingNavigationMenuMetrics.iconFrameWidth,
                        height: FloatingNavigationMenuMetrics.iconFrameHeight
                    )
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }

                        if let chipText {
                            Text(chipText)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green)
                                )
                                .fixedSize()
                                .offset(x: 16, y: -10)
                        }
                    }

                Text(title)
                    .font(.system(size: FloatingNavigationMenuMetrics.labelFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(
                minWidth: FloatingNavigationMenuMetrics.itemMinWidth,
                minHeight: FloatingNavigationMenuMetrics.itemMinHeight
            )
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private enum FloatingNavigationMenuMetrics {
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 6
    static let itemSpacing: CGFloat = 12
    static let itemMinWidth: CGFloat = 78
    static let itemMinHeight: CGFloat = 52
    static let iconSize: CGFloat = 24
    static let iconFrameWidth: CGFloat = 34
    static let iconFrameHeight: CGFloat = 28
    static let labelFontSize: CGFloat = 11
    static let labelSpacing: CGFloat = 2
}
