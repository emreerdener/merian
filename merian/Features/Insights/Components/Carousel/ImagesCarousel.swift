import SwiftUI

struct CarouselPageBuilder {
    static func buildPages(
        for activeMedia: ActiveScanMedia,
        onImageFailure: @escaping (String) -> Void,
        onDescriptionTap: (() -> Void)?
    ) -> [CarouselPageItem] {
        var pages: [CarouselPageItem] = []
        
        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                pages.append(CarouselPageItem(id: "liveImage-\(data.hashValue)", view: AnyView(LiveCapturePageView(data: data))))
            case .image(let path):
                pages.append(CarouselPageItem(id: "image-\(path)", view: AnyView(
                    AsyncLocalImageView(
                        path: path,
                        fallbackImageUrl: nil,
                        onImageLoadFailed: { onImageFailure(path) }
                    )
                )))
            case .description(let context):
                pages.append(CarouselPageItem(id: "description-\(context.serialized())", view: AnyView(DescriptionTextCarouselPage(text: context.serialized(), onTap: onDescriptionTap))))
            case .audio(let resolvedPath):
                pages.append(CarouselPageItem(id: "audio-\(resolvedPath)", view: AnyView(AudioPlaybackCarouselPage(filePath: resolvedPath))))
            }
        }
        
        switch activeMedia.referenceState {
        case .empty: break
        case .loading:
            pages.append(CarouselPageItem(id: "reference-loading", view: AnyView(
                ZStack {
                    Color(uiColor: .systemGray6)
                    ProgressView()
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )))
        case .loaded(let urls):
            for urlString in urls {
                pages.append(CarouselPageItem(id: "reference-\(urlString)", view: AnyView(
                    AsyncLocalImageView(
                        path: nil,
                        fallbackImageUrl: urlString,
                        onImageLoadFailed: { onImageFailure(urlString) }
                    )
                )))
            }
        }
        
        return pages
    }
}

// MARK: - Carousel Page Identity
/// Provides an explicit, stable identity for each page in the carousel.
/// This prevents positional diffing bugs where removing a page from the start/middle
/// of the array causes the tail controllers (like AudioPlayback) to be erroneously 
/// discarded and recreated, breaking their active state.
struct CarouselPageItem: Identifiable, Equatable {
    let id: String
    let view: AnyView
    
    static func == (lhs: CarouselPageItem, rhs: CarouselPageItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ImagesCarousel: View {
    // MARK: - Properties
    let scanId: String?
    let activeMedia: ActiveScanMedia
    /// Whether inference is currently in progress. Controls the dimming overlay.
    let isProcessing: Bool
    /// Called when a carousel image fails to load. The caller decides whether to
    /// propagate the failure to the engine (live path) or swallow it (queued path).
    let onImageFailure: (String) -> Void
    
    /// Triggers exclusively when tapping the interactive textual subcomponent.
    let onDescriptionTap: (() -> Void)?

    // MARK: - State
    @State private var selectedIndex: Int = 0

    // MARK: - Body
    var body: some View {
        Group {
            if activeMedia.totalItems > 0 {
                NativePageCarousel(selectedIndex: $selectedIndex, pages: carouselPages)
                    // scanId only — activeMedia.totalItems changes async when validHistoricImagePaths resolves.
                    // Keying on scanId prevents a full rebuild (and snap-back to page 0) on those updates.
                    .id(scanId ?? "null")
                    .ignoresSafeArea(.all, edges: .top)
                    .overlay(alignment: .bottom) { paginationDots }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [.black.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false)
                    }
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
    }

    // MARK: - Page Construction
    private var carouselPages: [CarouselPageItem] {
        CarouselPageBuilder.buildPages(
            for: activeMedia,
            onImageFailure: { handleImageFailure(identifier: $0) },
            onDescriptionTap: onDescriptionTap
        )
    }

    // MARK: - Action Handlers
    private func handleImageFailure(identifier: String) {
        if activeMedia.totalItems > 1 {
            onImageFailure(identifier)
        }
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {

    @ViewBuilder
    var paginationDots: some View {
        ZStack {
            if activeMedia.totalItems > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<activeMedia.totalItems, id: \.self) { index in
                        Circle()
                            .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2))
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 40)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: activeMedia.totalItems)
    }
}
