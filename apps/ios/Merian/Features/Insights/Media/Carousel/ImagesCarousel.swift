import AVKit
import SwiftUI

struct CarouselPageBuilder {
    static func buildPages(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        onImageFailure: @escaping (String) -> Void,
        onDescriptionTap: (() -> Void)?
    ) -> [CarouselPageItem] {
        var pages: [CarouselPageItem] = []
        
        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                pages.append(CarouselPageItem(
                    id: "liveImage-\(data.hashValue)",
                    mediaKind: .visual,
                    view: AnyView(LiveCapturePageView(data: data))
                ))
            case .image(let path):
                pages.append(CarouselPageItem(id: "image-\(path)", mediaKind: .visual, view: AnyView(
                    AsyncLocalImageView(
                        path: path,
                        fallbackImageUrl: nil,
                        onImageLoadFailed: { onImageFailure(path) }
                    )
                )))
            case .description(let context):
                pages.append(CarouselPageItem(
                    id: "description-\(context.serialized())",
                    mediaKind: .description,
                    view: AnyView(DescriptionTextCarouselPage(text: context.serialized(), onTap: onDescriptionTap))
                ))
            case .audio(let resolvedPath):
                pages.append(CarouselPageItem(
                    id: "audio-\(resolvedPath)",
                    mediaKind: .audio,
                    view: AnyView(AudioPlaybackCarouselPage(filePath: resolvedPath))
                ))
            case .video(let resolvedPath):
                pages.append(CarouselPageItem(
                    id: "video-\(resolvedPath)",
                    mediaKind: .video,
                    view: AnyView(VideoPlaybackCarouselPage(path: resolvedPath))
                ))
            }
        }
        
        switch activeMedia.referenceState {
        case .empty: break
        case .loading:
            pages.append(CarouselPageItem(id: "reference-loading", mediaKind: .visual, view: AnyView(
                ZStack {
                    Color(uiColor: .systemGray6)
                    ProgressView()
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )))
        case .loaded(let urls):
            for (index, urlString) in urls.enumerated() {
                let source = CarouselReferenceImageSource.source(
                    for: urlString,
                    wikipediaUrl: referenceWikipediaUrl,
                    index: index
                )
                pages.append(CarouselPageItem(id: "reference-\(urlString)", mediaKind: .visual, view: AnyView(
                    AsyncLocalImageView(
                        path: nil,
                        fallbackImageUrl: urlString,
                        onImageLoadFailed: { onImageFailure(urlString) }
                    )
                ), referenceAttributionLabel: source.label))
            }
        }
        
        return pages
    }
}

struct InsightImageGalleryItem: Identifiable, Equatable {
    enum Source: Equatable {
        case liveImage(Data)
        case imagePath(String)
        case videoPath(String)
        case referenceURL(String)
    }

    let id: String
    let source: Source
    let referenceAttributionLabel: String?
}

struct InsightImageGalleryPresentation: Identifiable, Equatable {
    let id: String
    let items: [InsightImageGalleryItem]
    let initialSelectedIndex: Int

    init(items: [InsightImageGalleryItem], initialSelectedIndex: Int) {
        self.items = items
        self.initialSelectedIndex = initialSelectedIndex
        self.id = "\(items.map(\.id).joined(separator: "|"))#\(initialSelectedIndex)"
    }
}

struct InsightImageGalleryBuilder {
    static func buildItems(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?
    ) -> [InsightImageGalleryItem] {
        var items: [InsightImageGalleryItem] = []

        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                items.append(InsightImageGalleryItem(
                    id: "liveImage-\(data.hashValue)",
                    source: .liveImage(data),
                    referenceAttributionLabel: nil
                ))
            case .image(let path):
                items.append(InsightImageGalleryItem(
                    id: "image-\(path)",
                    source: .imagePath(path),
                    referenceAttributionLabel: nil
                ))
            case .video(let path):
                items.append(InsightImageGalleryItem(
                    id: "video-\(path)",
                    source: .videoPath(path),
                    referenceAttributionLabel: nil
                ))
            case .audio, .description:
                break
            }
        }

        if case .loaded(let urls) = activeMedia.referenceState {
            for (index, urlString) in urls.enumerated() {
                let source = CarouselReferenceImageSource.source(
                    for: urlString,
                    wikipediaUrl: referenceWikipediaUrl,
                    index: index
                )
                items.append(InsightImageGalleryItem(
                    id: "reference-\(urlString)",
                    source: .referenceURL(urlString),
                    referenceAttributionLabel: source.label
                ))
            }
        }

        return items
    }

    static func presentation(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        selectedCarouselPageID: String?
    ) -> InsightImageGalleryPresentation? {
        guard let selectedCarouselPageID else { return nil }

        let items = buildItems(for: activeMedia, referenceWikipediaUrl: referenceWikipediaUrl)
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedCarouselPageID }) else {
            return nil
        }

        return InsightImageGalleryPresentation(items: items, initialSelectedIndex: selectedIndex)
    }
}

enum CarouselMediaKind {
    case visual
    case audio
    case video
    case description
}

private struct VideoPlaybackCarouselPage: View {
    let path: String

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                CoverVideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: path) {
            player?.pause()
            player = resolvedURL(path).map(AVPlayer.init(url:))
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func resolvedURL(_ rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" || url.scheme == "file" {
            return url
        }
        return URL(fileURLWithPath: trimmed)
    }
}

private struct CoverVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspectFill
        controller.showsPlaybackControls = true
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.videoGravity = .resizeAspectFill
    }
}

// MARK: - Carousel Page Identity
/// Provides an explicit, stable identity for each page in the carousel.
/// This prevents positional diffing bugs where removing a page from the start/middle
/// of the array causes the tail controllers (like AudioPlayback) to be erroneously 
/// discarded and recreated, breaking their active state.
struct CarouselPageItem: Identifiable, Equatable {
    let id: String
    let mediaKind: CarouselMediaKind
    let view: AnyView
    let referenceAttributionLabel: String?

    init(
        id: String,
        mediaKind: CarouselMediaKind,
        view: AnyView,
        referenceAttributionLabel: String? = nil
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.view = view
        self.referenceAttributionLabel = referenceAttributionLabel
    }

    static func == (lhs: CarouselPageItem, rhs: CarouselPageItem) -> Bool {
        lhs.id == rhs.id
    }
}

private enum CarouselReferenceImageSource {
    case wikipedia
    case gbif
    case merian

    var label: String {
        switch self {
        case .wikipedia:
            return "Wikipedia"
        case .gbif:
            return "GBIF"
        case .merian:
            return "Merian"
        }
    }

    static func source(for urlString: String, wikipediaUrl: String?, index: Int) -> Self {
        if let host = URL(string: urlString)?.host?.lowercased() {
            if host == "media.merian.app" || host.hasSuffix(".merian.app") {
                return .merian
            }

            if host.contains("wikipedia") || host.contains("wikimedia") {
                return .wikipedia
            }
        }

        let hasWikipediaUrl = !(wikipediaUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if index == 0 && hasWikipediaUrl {
            return .wikipedia
        }

        return .gbif
    }
}

struct ImagesCarousel: View {
    // MARK: - Properties
    let scanId: String?
    let activeMedia: ActiveScanMedia
    let referenceWikipediaUrl: String?
    /// Whether inference is currently in progress. Controls the dimming overlay.
    let isProcessing: Bool
    /// Called when a carousel image fails to load. The caller decides whether to
    /// propagate the failure to the engine (live path) or swallow it (queued path).
    let onImageFailure: (String) -> Void
    
    /// Triggers exclusively when tapping the interactive textual subcomponent.
    let onDescriptionTap: (() -> Void)?
    /// Triggers when the currently selected carousel page can be represented in
    /// the full-screen visual gallery.
    let onVisualImageTap: ((InsightImageGalleryPresentation) -> Void)?

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
                    .overlay(alignment: .bottomTrailing) { referenceAttributionTag }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [.black.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false)
                    }
                    .overlay {
                        if isProcessing {
                            AnalyzingMediaOverlay(kind: selectedMediaKind)
                                .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            handleVisualImageTap()
                        }
                    )
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isProcessing)
    }

    // MARK: - Page Construction
    private var carouselPages: [CarouselPageItem] {
        CarouselPageBuilder.buildPages(
            for: activeMedia,
            referenceWikipediaUrl: referenceWikipediaUrl,
            onImageFailure: { handleImageFailure(identifier: $0) },
            onDescriptionTap: onDescriptionTap
        )
    }

    private var selectedMediaKind: CarouselMediaKind {
        carouselPages[safe: selectedIndex]?.mediaKind ?? .visual
    }

    private var selectedReferenceAttributionLabel: String? {
        carouselPages[safe: selectedIndex]?.referenceAttributionLabel
    }

    // MARK: - Action Handlers
    private func handleVisualImageTap() {
        let selectedPageID = carouselPages[safe: selectedIndex]?.id
        guard let presentation = InsightImageGalleryBuilder.presentation(
            for: activeMedia,
            referenceWikipediaUrl: referenceWikipediaUrl,
            selectedCarouselPageID: selectedPageID
        ) else { return }

        onVisualImageTap?(presentation)
    }

    private func handleImageFailure(identifier: String) {
        if activeMedia.totalItems > 1 {
            onImageFailure(identifier)
        }
    }
}

// MARK: - Analyzing Overlay
private struct AnalyzingMediaOverlay: View {
    let kind: CarouselMediaKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepProgress: CGFloat = 0
    @State private var pulse = false

    private let visualBandHeight: CGFloat = 109.6
    private let descriptionBandHeight: CGFloat = 89.2

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                tintLayer

                switch kind {
                case .visual, .video:
                    visualScan(in: geometry.size)
                case .audio:
                    audioSweep(in: geometry.size)
                case .description:
                    descriptionReadSweep(in: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: startAnimation)
        }
    }

    @ViewBuilder
    private var tintLayer: some View {
        switch kind {
        case .visual, .video:
            Color.black.opacity(0.14)
        case .audio:
            Color.cyan.opacity(pulse ? 0.11 : 0.05)
                .blendMode(.screen)
        case .description:
            Color.green.opacity(pulse ? 0.08 : 0.04)
        }
    }

    private func visualScan(in size: CGSize) -> some View {
        horizontalScanBand(color: .cyan, coreHeight: 1.6, glowHeight: 54)
            .offset(y: verticalOffset(in: size, bandHeight: visualBandHeight))
            .blendMode(.plusLighter)
    }

    private func audioSweep(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(Color.cyan.opacity(0.08 + Double(index) * 0.018))
                    .frame(width: 1, height: size.height * (0.34 + CGFloat(index % 3) * 0.13))
                    .offset(x: horizontalOffset(in: size) - 42 + CGFloat(index) * 14)
                    .blendMode(.plusLighter)
            }

            LinearGradient(
                colors: [
                    .clear,
                    .cyan.opacity(0.32),
                    .white.opacity(0.72),
                    .cyan.opacity(0.28),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 96)
            .offset(x: horizontalOffset(in: size))
            .blur(radius: 0.5)
            .blendMode(.plusLighter)
        }
    }

    private func descriptionReadSweep(in size: CGSize) -> some View {
        horizontalScanBand(color: .green, coreHeight: 1.2, glowHeight: 44)
            .offset(y: verticalOffset(in: size, bandHeight: descriptionBandHeight))
            .blendMode(.screen)
            .opacity(0.85)
    }

    private func horizontalScanBand(color: Color, coreHeight: CGFloat, glowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, color.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: glowHeight)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(height: coreHeight)
                .shadow(color: color.opacity(0.9), radius: 7)

            LinearGradient(
                colors: [color.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: glowHeight)
        }
    }

    private func verticalOffset(in size: CGSize, bandHeight: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let startCenterY = -bandHeight / 2
        let endCenterY = size.height + bandHeight / 2
        let currentCenterY = startCenterY + (endCenterY - startCenterY) * sweepProgress
        return currentCenterY - size.height / 2
    }

    private func horizontalOffset(in size: CGSize) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return (sweepProgress * (size.width + 128)) - (size.width / 2) - 64
    }

    private func startAnimation() {
        guard !reduceMotion else {
            pulse = true
            return
        }

        sweepProgress = 0
        withAnimation(.easeInOut(duration: 2.15).repeatForever(autoreverses: true)) {
            sweepProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {

    @ViewBuilder
    var referenceAttributionTag: some View {
        if let label = selectedReferenceAttributionLabel {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.28))
                }
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .padding(.trailing, 14)
                .padding(.bottom, 40)
                .allowsHitTesting(false)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedReferenceAttributionLabel)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity
                ))
        }
    }

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
