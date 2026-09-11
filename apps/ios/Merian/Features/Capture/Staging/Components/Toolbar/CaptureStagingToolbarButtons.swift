import SwiftUI

struct CaptureStagingCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(
                            color: .black.opacity(0.2),
                            radius: 15,
                            x: 0,
                            y: 8
                        )
                )
                .overlay(
                    Circle()
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
}

struct CaptureStagingSubmitButton: View {
    let title: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        Button(action: onSubmit) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(
                isDisabled
                    ? Color.white.opacity(0.15)
                    : buttonColor
            )
            .foregroundColor(
                isDisabled ? .white.opacity(0.6) : .white
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isDisabled ? .clear : buttonColor.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .overlay(shimmerOverlay)
            .shadow(
                color: isDisabled ? .clear : buttonColor.opacity(0.25),
                radius: 10,
                x: 0,
                y: 4
            )
        }
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
        Color(red: 0.11, green: 0.52, blue: 0.28)
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
