import SwiftUI

// MARK: - Description Overlay Component

enum DescriptionTextCarouselLayout {
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 108
    static let cardVerticalOffset: CGFloat = 24
    static let cardCornerRadius: CGFloat = 32
    static let contentPadding: CGFloat = 28

    static func cardSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: max(0, containerSize.width - horizontalInset * 2),
            height: max(0, containerSize.height - verticalInset * 2)
        )
    }
}

/// Dedicated visual abstraction managing the abbreviated visual representation explicitly mapping
/// the textual node context dynamically anchored alongside photo assets within the timeline natively.
struct DescriptionTextCarouselPage: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let onTap: (() -> Void)?
    
    var body: some View {
        GeometryReader { geo in
            let cardSize = DescriptionTextCarouselLayout.cardSize(in: geo.size)

            ZStack {
                Color(uiColor: .systemBackground)
                    .opacity(0.95)
                
                Image("animals-background")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(Color.green)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.20)
                    .clipped()
                
                // Description card
                VStack(spacing: 16) {
                    Text(text)
                        .font(.system(size: 80, weight: .medium))
                        .lineLimit(6)
                        .minimumScaleFactor(0.3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(DescriptionTextCarouselLayout.contentPadding)
                .frame(width: cardSize.width, height: cardSize.height)
                .background(
                    colorScheme == .light
                        ? AnyShapeStyle(Color.white.opacity(0.8))
                        : AnyShapeStyle(.ultraThinMaterial.opacity(0.75)),
                    in: RoundedRectangle(
                        cornerRadius: DescriptionTextCarouselLayout.cardCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: DescriptionTextCarouselLayout.cardCornerRadius,
                        style: .continuous
                    )
                        .stroke(colorScheme == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .offset(y: DescriptionTextCarouselLayout.cardVerticalOffset)
                
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
        }
    }
}
