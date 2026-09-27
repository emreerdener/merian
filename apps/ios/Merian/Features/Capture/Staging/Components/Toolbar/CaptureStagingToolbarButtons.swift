import SwiftUI

struct CaptureStagingCancelButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(discardColor)
                .frame(width: 48, height: 48)
                .modifier(CaptureTrayGlass(isCircular: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard scan")
    }

    private var discardColor: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.30, blue: 0.32)
            : Color(red: 0.75, green: 0.08, blue: 0.12)
    }
}

/// Native glass honors the same thermal/Expedition policy as camera effects.
struct CaptureTrayGlass: ViewModifier {
    var isCircular = false
    @Environment(HardwareOrchestrator.self) private var hardware
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if !hardware.isGlassmorphismEnabled || reduceTransparency {
            content.background(Color(UIColor.secondarySystemBackground), in: Capsule())
        } else if #available(iOS 26.0, *) {
            if isCircular {
                content.glassEffect(.regular.interactive(), in: Circle())
            } else {
                content.glassEffect(.regular, in: Capsule())
            }
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct CaptureStagingSubmitButton: View {
    let title: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        Button(action: onSubmit) {
            HStack(spacing: 6) {
                if title == "Analyze" {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(
                isDisabled
                    ? Color.primary.opacity(0.15)
                    : buttonColor
            )
            .foregroundColor(
                isDisabled ? Color.secondary : .white
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isDisabled ? .clear : buttonColor.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .overlay { if title == "Analyze" { shimmerOverlay } }
            .shadow(
                color: isDisabled ? .clear : buttonColor.opacity(0.25),
                radius: 10,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
        .onAppear {
            withAnimation(
                .linear(duration: 4.5)
                    .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 2.5
            }
        }
    }

    private var buttonColor: Color {
        title == "Analyze" ? Color(red: 0.11, green: 0.52, blue: 0.28) : .accentColor
    }

    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.9), location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: geometry.size.width)
                .offset(x: shimmerPhase * geometry.size.width * 2)
                .blendMode(.screen)
                .mask(Capsule().stroke(lineWidth: 1.5))
        }
        .allowsHitTesting(false)
        .opacity(isDisabled ? 0 : 1)
    }
}
