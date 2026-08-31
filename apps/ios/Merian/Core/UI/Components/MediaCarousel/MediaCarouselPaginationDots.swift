import SwiftUI

/// Shared pagination treatment for square, full-bleed media carousels.
struct MediaCarouselPaginationDots: View {
    let pageCount: Int
    let selectedIndex: Int
    var bottomPadding: CGFloat = 40
    var accessibilityNoun = "Image"

    private var resolvedSelectedIndex: Int {
        max(0, min(selectedIndex, max(0, pageCount - 1)))
    }

    var body: some View {
        ZStack {
            if pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(
                                index == resolvedSelectedIndex
                                    ? Color.white
                                    : Color.white.opacity(0.4)
                            )
                            .frame(width: 6, height: 6)
                            .shadow(
                                color: .black.opacity(0.3),
                                radius: 2,
                                y: 1
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2))
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, bottomPadding)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(accessibilityNoun) " +
                        "\(resolvedSelectedIndex + 1) of \(pageCount)"
                )
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: resolvedSelectedIndex
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8),
            value: pageCount
        )
    }
}
