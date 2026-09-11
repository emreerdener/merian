import SwiftUI

struct FadingScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .background(contentGeometryReader)
        }
        .coordinateSpace(name: "FadingScrollSpace")
        .defaultScrollAnchor(.trailing)
        .background(containerGeometryReader)
        .mask(fadeMask)
    }

    private var contentGeometryReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(
                    of: geometry.frame(
                        in: .named("FadingScrollSpace")
                    ).minX,
                    initial: true
                ) { _, newOffset in
                    guard abs(offset - newOffset) > 1 else { return }
                    Task { @MainActor in offset = newOffset }
                }
                .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                    guard abs(contentWidth - newWidth) > 1 else { return }
                    Task { @MainActor in contentWidth = newWidth }
                }
        }
    }

    private var containerGeometryReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                    guard abs(containerWidth - newWidth) > 1 else { return }
                    Task { @MainActor in containerWidth = newWidth }
                }
        }
    }

    private var fadeMask: some View {
        HStack(spacing: 0) {
            let showLeadingFade = offset < -10
            LinearGradient(
                colors: [
                    Color.black.opacity(showLeadingFade ? 0 : 1),
                    .black
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 48)

            Rectangle().fill(Color.black)

            let maxScroll = max(0, contentWidth - containerWidth)
            let showTrailingFade = offset > -maxScroll + 10

            LinearGradient(
                colors: [
                    .black,
                    Color.black.opacity(showTrailingFade ? 0 : 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 48)
        }
    }
}
