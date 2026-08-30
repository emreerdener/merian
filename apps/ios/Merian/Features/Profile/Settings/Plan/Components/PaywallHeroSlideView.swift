import SwiftUI

struct PaywallHeroSlideView: View {
    let slide: PaywallHeroSlide
    let isCompact: Bool
    let availableHeight: CGFloat

    var body: some View {
        let imageHeight: CGFloat = isCompact
            ? min(130, availableHeight * 0.18)
            : 184
        let containerHeight: CGFloat = isCompact
            ? min(200, availableHeight * 0.26)
            : 276

        VStack(spacing: isCompact ? 8 : 16) {
            ZStack {
                RadialGradient(
                    stops: [
                        .init(
                            color: slide.glowColor.opacity(0.26),
                            location: 0
                        ),
                        .init(
                            color: slide.glowColor.opacity(0.12),
                            location: 0.48
                        ),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 134
                )
                .frame(width: 350, height: containerHeight)
                .accessibilityHidden(true)

                Image(slide.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: imageHeight)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 10)
            }
            .frame(height: containerHeight)
            .frame(maxWidth: .infinity)

            VStack(spacing: isCompact ? 4 : 7) {
                Text(slide.title)
                    .font(
                        .system(
                            size: isCompact ? 22 : 29,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text(slide.subtitle)
                    .font(
                        .system(
                            size: isCompact ? 14 : 17,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: isCompact ? 300 : 360)
            .padding(.horizontal, isCompact ? 28 : 36)
        }
        .padding(.bottom, isCompact ? 12 : 26)
    }
}
