import AVFoundation
import Combine
import SwiftUI

struct CarouselPageBuilder {
    static func buildPages(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        selectedIndex: Binding<Int> = .constant(0),
        isVideoMuted: Binding<Bool> = .constant(true),
        videoPlaybackCoordinator: InsightCarouselVideoPlaybackCoordinator? = nil,
        isAudioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onImageFailure: @escaping (String) -> Void,
        onDescriptionTap: (() -> Void)?
    ) -> [CarouselPageItem] {
        var pages: [CarouselPageItem] = []
        var stillImageSourceIndex = 0
        
        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                let focusRegion = activeMedia.focusRegionsBySourceIndex[stillImageSourceIndex]
                stillImageSourceIndex += 1
                pages.append(CarouselPageItem(
                    id: "liveImage-\(data.hashValue)",
                    mediaKind: .visual,
                    view: AnyView(LiveCapturePageView(data: data)),
                    focusRegion: focusRegion
                ))
            case .image(let path):
                let focusRegion = activeMedia.focusRegionsBySourceIndex[stillImageSourceIndex]
                stillImageSourceIndex += 1
                pages.append(CarouselPageItem(id: "image-\(path)", mediaKind: .visual, view: AnyView(
                    AsyncLocalImageView(
                        path: path,
                        fallbackImageUrl: nil,
                        onImageLoadFailed: { onImageFailure(path) }
                    )
                ), focusRegion: focusRegion))
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
                    view: AnyView(AudioPlaybackCarouselPage(
                        filePath: resolvedPath,
                        isAudioBoostEnabled: isAudioBoostEnabled,
                        audioBoostActionToken: audioBoostActionToken,
                        onAudioBoostActionFinished: onAudioBoostActionFinished,
                        onAudioBoostToggleRequested: onAudioBoostToggleRequested
                    ))
                ))
            case .video(let resolvedPath):
                let pageIndex = pages.count
                pages.append(CarouselPageItem(
                    id: "video-\(resolvedPath)",
                    mediaKind: .video,
                    view: AnyView(VideoPlaybackCarouselPage(
                        path: resolvedPath,
                        pageIndex: pageIndex,
                        selectedIndex: selectedIndex,
                        isMuted: isVideoMuted,
                        playbackCoordinator: videoPlaybackCoordinator
                    ))
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
    let initialVideoMuted: Bool

    init(
        items: [InsightImageGalleryItem],
        initialSelectedIndex: Int,
        initialVideoMuted: Bool = true
    ) {
        self.items = items
        self.initialSelectedIndex = initialSelectedIndex
        self.initialVideoMuted = initialVideoMuted
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
        selectedCarouselPageID: String?,
        isVideoMuted: Bool = true
    ) -> InsightImageGalleryPresentation? {
        guard let selectedCarouselPageID else { return nil }

        let items = buildItems(for: activeMedia, referenceWikipediaUrl: referenceWikipediaUrl)
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedCarouselPageID }) else {
            return nil
        }

        return InsightImageGalleryPresentation(
            items: items,
            initialSelectedIndex: selectedIndex,
            initialVideoMuted: isVideoMuted
        )
    }
}

enum CarouselMediaKind {
    case visual
    case audio
    case video
    case description
}

enum InsightCarouselMediaInteractionPolicy {
    static let centerPlaybackHitSize: CGFloat = 96

    static func isCenterPlaybackTap(
        location: CGPoint,
        containerSize: CGSize,
        mediaKind: CarouselMediaKind
    ) -> Bool {
        guard case .video = mediaKind else { return false }

        let hitSize = centerPlaybackHitSize
        let hitFrame = CGRect(
            x: (containerSize.width - hitSize) / 2,
            y: (containerSize.height - hitSize) / 2,
            width: hitSize,
            height: hitSize
        )
        return hitFrame.contains(location)
    }
}

final class InsightCarouselVideoPlaybackCoordinator {
    private let pauseForFullscreenPresentationSubject = PassthroughSubject<Void, Never>()

    var pauseForFullscreenPresentationPublisher: AnyPublisher<Void, Never> {
        pauseForFullscreenPresentationSubject.eraseToAnyPublisher()
    }

    func pauseForFullscreenPresentation() {
        pauseForFullscreenPresentationSubject.send()
    }
}

struct InsightCenterVideoPlaybackControl: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.46), in: Circle())
                    .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: InsightCarouselMediaInteractionPolicy.centerPlaybackHitSize,
            height: InsightCarouselMediaInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
        .accessibilityAction {
            action()
        }
        .animation(.easeInOut(duration: 0.22), value: isPlaying)
    }
}

private struct VideoPlaybackCarouselPage: View {
    let path: String
    let pageIndex: Int
    @Binding var selectedIndex: Int
    @Binding var isMuted: Bool
    let playbackCoordinator: InsightCarouselVideoPlaybackCoordinator?

    @State private var player: AVPlayer?
    @State private var hasAutoplayed = false
    @State private var isPlaying = false
    @State private var playbackEndObserver: NSObjectProtocol?

    private var isSelected: Bool {
        selectedIndex == pageIndex
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                InsightCoverVideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onReceive(player.publisher(for: \.timeControlStatus).removeDuplicates()) { status in
                        switch status {
                        case .playing:
                            isPlaying = true
                        case .paused:
                            isPlaying = false
                        case .waitingToPlayAtSpecifiedRate:
                            break
                        @unknown default:
                            break
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }

            InsightCenterVideoPlaybackControl(
                isPlaying: isPlaying,
                action: togglePlayback
            )
        }
        .task(id: path) {
            configurePlayer()
        }
        .onChange(of: selectedIndex) { _, _ in
            updatePlaybackForSelection()
        }
        .onChange(of: isMuted) { _, newValue in
            guard !newValue else {
                player?.isMuted = true
                return
            }
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.insight.carousel.unmute"
                )
                guard activated, !isMuted else { return }
                player?.isMuted = false
            }
        }
        .onReceive(fullscreenPresentationPausePublisher) {
            player?.pause()
            isPlaying = false
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            removePlaybackEndObserver()
        }
    }

    private var fullscreenPresentationPausePublisher: AnyPublisher<Void, Never> {
        playbackCoordinator?.pauseForFullscreenPresentationPublisher
            ?? Empty().eraseToAnyPublisher()
    }

    private func configurePlayer() {
        player?.pause()
        removePlaybackEndObserver()
        hasAutoplayed = false
        isPlaying = false

        guard let url = resolvedURL(path) else {
            player = nil
            return
        }

        let configuredPlayer = AVPlayer(url: url)
        configuredPlayer.isMuted = isMuted
        configuredPlayer.actionAtItemEnd = .pause
        player = configuredPlayer
        installPlaybackEndObserver(for: configuredPlayer)
        updatePlaybackForSelection()
    }

    private func updatePlaybackForSelection() {
        guard let player else { return }

        if isSelected {
            if !hasAutoplayed {
                startPlayback(fromBeginning: true)
            }
        } else if !isSelected, isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    private func startPlayback(fromBeginning: Bool) {
        guard let player else { return }
        if fromBeginning {
            player.seek(to: .zero)
        }
        player.isMuted = isMuted
        hasAutoplayed = true
        play(player, source: "media.insight.carousel.autoplay")
    }

    private func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.55,
                source: "media.insight.carousel.pause"
            )
            player.pause()
            isPlaying = false
        } else {
            HapticManager.shared.triggerMediumPulse(source: "media.insight.carousel.play")
            hasAutoplayed = true
            play(player, source: "media.insight.carousel.play")
        }
    }

    private func installPlaybackEndObserver(for player: AVPlayer) {
        removePlaybackEndObserver()
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            guard isSelected else {
                isPlaying = false
                return
            }
            play(player, source: "media.insight.carousel.loop")
        }
    }

    private func play(_ player: AVPlayer, source: String) {
        guard isSelected else { return }
        guard !isMuted else {
            player.play()
            isPlaying = true
            return
        }

        Task { @MainActor in
            let activated = await MediaPlaybackAudioSession.activate(source: source)
            guard activated, self.player === player, isSelected, !isMuted else { return }
            player.isMuted = false
            player.play()
            isPlaying = true
        }
    }

    private func removePlaybackEndObserver() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
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

struct InsightCoverVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> InsightPlayerLayerView {
        let view = InsightPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: InsightPlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = videoGravity
    }

    static func dismantleUIView(_ view: InsightPlayerLayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

final class InsightPlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    let focusRegion: NormalizedImageFocusRegion?

    init(
        id: String,
        mediaKind: CarouselMediaKind,
        view: AnyView,
        referenceAttributionLabel: String? = nil,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.view = view
        self.referenceAttributionLabel = referenceAttributionLabel
        self.focusRegion = focusRegion
    }

    static func == (lhs: CarouselPageItem, rhs: CarouselPageItem) -> Bool {
        lhs.id == rhs.id && lhs.focusRegion == rhs.focusRegion
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
    @Binding var isAudioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?

    // MARK: - State
    @State private var selectedIndex: Int = 0
    @State private var isVideoMuted = true
    @State private var videoPlaybackCoordinator = InsightCarouselVideoPlaybackCoordinator()

    // MARK: - Body
    var body: some View {
        Group {
            if activeMedia.totalItems > 0 {
                GeometryReader { geometry in
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
                                AnalyzingMediaOverlay(
                                    kind: selectedMediaKind,
                                    focusRegion: selectedFocusRegion
                                )
                                    .transition(.opacity)
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                handleCarouselTap(at: value.location, containerSize: geometry.size)
                            }
                        )
                        .overlay(alignment: .bottomLeading) { videoMuteControl }
                }
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
            selectedIndex: $selectedIndex,
            isVideoMuted: $isVideoMuted,
            videoPlaybackCoordinator: videoPlaybackCoordinator,
            isAudioBoostEnabled: $isAudioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: onAudioBoostActionFinished,
            onAudioBoostToggleRequested: onAudioBoostToggleRequested,
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

    private var selectedFocusRegion: NormalizedImageFocusRegion? {
        carouselPages[safe: selectedIndex]?.focusRegion
    }

    // MARK: - Action Handlers
    private func handleCarouselTap(at location: CGPoint, containerSize: CGSize) {
        guard !InsightCarouselMediaInteractionPolicy.isCenterPlaybackTap(
            location: location,
            containerSize: containerSize,
            mediaKind: selectedMediaKind
        ) else { return }

        handleVisualImageTap()
    }

    private func handleVisualImageTap() {
        let selectedPageID = carouselPages[safe: selectedIndex]?.id
        guard let presentation = InsightImageGalleryBuilder.presentation(
            for: activeMedia,
            referenceWikipediaUrl: referenceWikipediaUrl,
            selectedCarouselPageID: selectedPageID,
            isVideoMuted: isVideoMuted
        ) else { return }

        videoPlaybackCoordinator.pauseForFullscreenPresentation()
        onVisualImageTap?(presentation)
    }

    private func handleImageFailure(identifier: String) {
        if activeMedia.totalItems > 1 {
            onImageFailure(identifier)
        }
    }
}

// MARK: - Analyzing Overlay
enum StillImageAnalyzingMode: Equatable {
    case fullImageScan
    case isolatedFocus(NormalizedImageFocusRegion)

    init(focusRegion: NormalizedImageFocusRegion?) {
        if let focusRegion {
            self = .isolatedFocus(focusRegion)
        } else {
            self = .fullImageScan
        }
    }
}

private struct AnalyzingMediaOverlay: View {
    let kind: CarouselMediaKind
    let focusRegion: NormalizedImageFocusRegion?

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
                case .visual:
                    switch StillImageAnalyzingMode(focusRegion: focusRegion) {
                    case .isolatedFocus(let focusRegion):
                        LensFocusOverlay(region: focusRegion)
                            .id(focusRegion)
                    case .fullImageScan:
                        visualScan(in: geometry.size)
                    }
                case .video:
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
        case .visual:
            if focusRegion == nil {
                Color.black.opacity(0.14)
            }
        case .video:
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
        if kind == .visual,
           case .isolatedFocus = StillImageAnalyzingMode(focusRegion: focusRegion) {
            return
        }

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

enum ImageFocusOverlayLayout {
    static func rect(
        for region: NormalizedImageFocusRegion,
        in containerSize: CGSize,
        imageAspectRatio: CGFloat = 1
    ) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageAspectRatio.isFinite,
              imageAspectRatio > 0 else { return .zero }

        let containerAspectRatio = containerSize.width / containerSize.height
        let renderedSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            renderedSize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
        } else {
            renderedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
        }
        let origin = CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
        return CGRect(
            x: origin.x + region.x * renderedSize.width,
            y: origin.y + region.y * renderedSize.height,
            width: region.width * renderedSize.width,
            height: region.height * renderedSize.height
        )
    }
}

private struct LensFocusOverlay: View {
    let region: NormalizedImageFocusRegion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isResolved = false
    @State private var scanProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let focusRect = ImageFocusOverlayLayout.rect(for: region, in: geometry.size)
            let shortestSide = min(geometry.size.width, geometry.size.height)
            let bracketArm = min(30, max(18, shortestSide * 0.075))
            let strokeWidth = min(5, max(3, shortestSide * 0.0125))
            let cornerRadius = min(12, max(8, shortestSide * 0.03))

            ZStack {
                Path { path in
                    path.addRect(bounds)
                    path.addRoundedRect(
                        in: focusRect,
                        cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                    )
                }
                .fill(.black.opacity(0.22), style: FillStyle(eoFill: true))
                .opacity(isResolved ? 1 : 0)

                if !reduceMotion {
                    LensFocusScanHighlight(
                        focusRect: focusRect,
                        cornerRadius: cornerRadius,
                        progress: scanProgress
                    )
                    .opacity(isResolved ? 1 : 0)
                }

                LensFocusBracketShape(
                    rect: focusRect,
                    armLength: bracketArm,
                    cornerRadius: cornerRadius
                )
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                .scaleEffect(reduceMotion || isResolved ? 1 : 0.985)
                .opacity(isResolved ? 1 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                isResolved = true
            } else {
                withAnimation(.easeOut(duration: 0.20)) {
                    isResolved = true
                }
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    scanProgress = 1
                }
            }
        }
    }
}

private struct LensFocusScanHighlight: View {
    let focusRect: CGRect
    let cornerRadius: CGFloat
    let progress: CGFloat

    var body: some View {
        let bandHeight = min(46, max(26, focusRect.height * 0.14))
        let travelDistance = focusRect.height + bandHeight

        LinearGradient(
            colors: [
                .clear,
                .cyan.opacity(0.035),
                .white.opacity(0.13),
                .cyan.opacity(0.035),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: focusRect.width, height: bandHeight)
        .offset(y: -travelDistance / 2 + travelDistance * progress)
        .frame(width: focusRect.width, height: focusRect.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .position(x: focusRect.midX, y: focusRect.midY)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

private struct LensFocusBracketShape: Shape {
    let rect: CGRect
    let armLength: CGFloat
    let cornerRadius: CGFloat

    func path(in _: CGRect) -> Path {
        let arm = min(armLength, rect.width / 2, rect.height / 2)
        let radius = min(cornerRadius, arm)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        return path
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {

    @ViewBuilder
    var videoMuteControl: some View {
        if selectedMediaKind == .video {
            Button {
                isVideoMuted.toggle()
                HapticManager.shared.triggerLightImpact(intensity: 0.45)
            } label: {
                Label(isVideoMuted ? "Muted" : "Sound on", systemImage: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.28))
                    }
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVideoMuted ? "Video muted" : "Video sound on")
            .accessibilityHint("Toggles video sound")
            .padding(.leading, 14)
            .padding(.bottom, 40)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVideoMuted)
        }
    }

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
