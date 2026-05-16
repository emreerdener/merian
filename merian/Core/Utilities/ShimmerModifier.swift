import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.35), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: geo.size.width * phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            }
            .clipped()
        )
        .clipped()
    }
}

enum GlowPulsingSkeletonStyle {
    case standard
    case raisedGrid
}

struct GlowPulsingSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGlowing = false

    var cornerRadius: CGFloat = 12
    var style: GlowPulsingSkeletonStyle = .standard

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(glowFill)
                    .opacity(isGlowing ? 1 : 0.35)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: shadowColor,
                radius: isGlowing ? shadowRadius : 4,
                x: 0,
                y: 0
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: isGlowing
            )
            .onAppear {
                isGlowing = true
            }
    }

    private var baseFill: Color {
        if style == .raisedGrid {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }

        return colorScheme == .dark
            ? Color(uiColor: .tertiarySystemFill)
            : Color(uiColor: .secondarySystemFill)
    }

    private var glowFill: LinearGradient {
        let whiteLeadingOpacity: Double
        let greenOpacity: Double
        let whiteTrailingOpacity: Double

        switch style {
        case .standard:
            whiteLeadingOpacity = colorScheme == .dark ? 0.06 : 0.28
            greenOpacity = colorScheme == .dark ? 0.18 : 0.14
            whiteTrailingOpacity = colorScheme == .dark ? 0.04 : 0.2
        case .raisedGrid:
            whiteLeadingOpacity = colorScheme == .dark ? 0.1 : 0.32
            greenOpacity = colorScheme == .dark ? 0.24 : 0.18
            whiteTrailingOpacity = colorScheme == .dark ? 0.06 : 0.24
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(whiteLeadingOpacity),
                Color.green.opacity(greenOpacity),
                Color.white.opacity(whiteTrailingOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        guard style == .raisedGrid else { return .clear }

        if colorScheme == .dark {
            return Color.white.opacity(isGlowing ? 0.16 : 0.08)
        } else {
            return Color.black.opacity(isGlowing ? 0.08 : 0.04)
        }
    }

    private var borderWidth: CGFloat {
        style == .raisedGrid ? 0.75 : 0
    }

    private var shadowColor: Color {
        switch style {
        case .standard:
            return Color.green.opacity(isGlowing ? 0.24 : 0.06)
        case .raisedGrid:
            return Color.green.opacity(isGlowing ? 0.28 : 0.08)
        }
    }

    private var shadowRadius: CGFloat {
        style == .raisedGrid ? 14 : 18
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
