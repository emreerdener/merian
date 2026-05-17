import SwiftUI

// MARK: - Dynamic Fading ScrollView
public struct FadingScrollView<Content: View>: View {
    @ViewBuilder public let content: Content
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .background(
                    // Explicitly uses GeometryReader on a strict invisible Color.clear layer to globally 
                    // intercept CoordinateSpace offset tracking perfectly without hardcoding pixel widths!
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("FadingScrollSpace")).minX, initial: true) { _, newX in
                                if abs(offset - newX) > 1.0 {
                                    Task { @MainActor in offset = newX }
                                }
                            }
                            .onChange(of: geo.size.width, initial: true) { _, newW in
                                if abs(contentWidth - newW) > 1.0 {
                                    Task { @MainActor in contentWidth = newW }
                                }
                            }
                    }
                )
        }
        .coordinateSpace(name: "FadingScrollSpace")
        .defaultScrollAnchor(.trailing)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, newW in
                        if abs(containerWidth - newW) > 1.0 {
                            Task { @MainActor in containerWidth = newW }
                        }
                    }
            }
        )
        .mask(
            HStack(spacing: 0) {
                let showLeadingFade = offset < -10
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(showLeadingFade ? 0 : 1), .black]),
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 48)
                
                Rectangle().fill(Color.black)
                
                let maxScroll = max(0, contentWidth - containerWidth)
                let showTrailingFade = offset > -maxScroll + 10
                
                LinearGradient(
                    gradient: Gradient(colors: [.black, Color.black.opacity(showTrailingFade ? 0 : 1)]),
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 48)
            }
        )
    }
}
