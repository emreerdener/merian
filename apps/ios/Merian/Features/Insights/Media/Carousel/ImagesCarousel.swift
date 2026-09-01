import SwiftUI

struct ImagesCarousel: View {
    let scanId: String?
    let activeMedia: ActiveScanMedia
    let referenceWikipediaUrl: String?
    /// Whether inference is currently in progress. Controls the dimming overlay.
    let isProcessing: Bool
    /// Triggers exclusively when tapping the interactive textual subcomponent.
    let onDescriptionTap: (() -> Void)?
    /// Triggers when the selected page can enter the full-screen visual gallery.
    let onVisualImageTap: ((MediaGalleryPresentation) -> Void)?
    @Binding var focusOverlayInteractionState: FocusOverlayInteractionState
    @Binding var isAudioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?
    let dependencies: MediaPlaybackDependencies

    @State private var selectedIndex = 0
    @State private var isVideoMuted = true
    @State private var videoPlaybackCoordinator =
        InsightCarouselVideoPlaybackCoordinator()
    @State private var unavailableImageIdentifiers: Set<String> = []
    @State private var loadedReferenceImageIdentifiers: Set<String> = []
    @State private var unavailableVideoPageIDs: Set<String> = []
    @State private var analyzingAnimationSession =
        AnalyzingMediaAnimationSession()

    init(
        scanId: String?,
        activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        isProcessing: Bool,
        onDescriptionTap: (() -> Void)?,
        onVisualImageTap: ((MediaGalleryPresentation) -> Void)?,
        focusOverlayInteractionState: Binding<FocusOverlayInteractionState>,
        isAudioBoostEnabled: Binding<Bool>,
        audioBoostActionToken: UUID?,
        onAudioBoostActionFinished: ((UUID) -> Void)?,
        onAudioBoostToggleRequested: (() -> Void)?,
        dependencies: MediaPlaybackDependencies? = nil
    ) {
        self.scanId = scanId
        self.activeMedia = activeMedia
        self.referenceWikipediaUrl = referenceWikipediaUrl
        self.isProcessing = isProcessing
        self.onDescriptionTap = onDescriptionTap
        self.onVisualImageTap = onVisualImageTap
        _focusOverlayInteractionState = focusOverlayInteractionState
        _isAudioBoostEnabled = isAudioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
        self.dependencies = dependencies ?? .insightLive
    }

    var body: some View {
        Group {
            if !carouselPages.isEmpty {
                GeometryReader { geometry in
                    NativePageCarousel(
                        selectedIndex: $selectedIndex,
                        pages: carouselPages.map(\.nativePage)
                    )
                    // Scan identity only: async page resolution must not rebuild
                    // the controller, and casing-only owner handoffs are equal.
                    .id(carouselScanIdentity ?? "null")
                    .ignoresSafeArea(.all, edges: .top)
                    .overlay(alignment: .bottom) {
                        MediaCarouselPaginationDots(
                            pageCount: carouselPages.count,
                            selectedIndex: selectedIndex
                        )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        referenceAttributionTag
                    }
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
                            let identity = selectedFocusInteractionIdentity
                            AnalyzingMediaOverlay(
                                kind: selectedMediaKind,
                                focusRegion: selectedFocusRegion,
                                focusInteractionIdentity: identity,
                                animationStartedAt:
                                    analyzingAnimationSession.startedAt,
                                dependencies: dependencies,
                                committedFocusRect: committedFocusRectBinding(
                                    for: identity
                                )
                            )
                            .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            handleCarouselTap(
                                at: value.location,
                                containerSize: geometry.size
                            )
                        }
                    )
                    .overlay(alignment: .bottomLeading) {
                        videoMuteControl
                    }
                }
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isProcessing)
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if UITestSeedCoordinator.isEnabled,
               isProcessing,
               !carouselPages.isEmpty {
                Color.clear
                    .frame(width: 1, height: 1)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Analyzing carousel continuity")
                    .accessibilityIdentifier("AnalyzingMediaCarousel")
                    .accessibilityValue(analyzingCarouselContinuityValue)
            }
        }
        #endif
        .onChange(of: carouselScanIdentity, initial: true) { _, newScanID in
            selectedIndex = 0
            isVideoMuted = true
            unavailableImageIdentifiers.removeAll()
            loadedReferenceImageIdentifiers.removeAll()
            unavailableVideoPageIDs.removeAll()
            if let newScanID {
                var updatedState = focusOverlayInteractionState
                updatedState.retainValues(forScanID: newScanID)
                focusOverlayInteractionState = updatedState
            }
            analyzingAnimationSession.update(
                scanID: newScanID,
                isProcessing: isProcessing
            )
        }
        .onChange(of: isProcessing) { _, isNowProcessing in
            analyzingAnimationSession.update(
                scanID: carouselScanIdentity,
                isProcessing: isNowProcessing
            )
        }
    }

    private var carouselPages: [CarouselPageItem] {
        CarouselImageAvailabilityPolicy.visiblePages(
            sourceCarouselPages,
            unavailableIdentifiers: unavailableImageIdentifiers,
            loadedReferenceIdentifiers: loadedReferenceImageIdentifiers,
            unavailableVideoPageIDs: unavailableVideoPageIDs
        )
    }

    private var sourceCarouselPages: [CarouselPageItem] {
        CarouselPageBuilder.buildPages(
            for: activeMedia,
            referenceWikipediaUrl: referenceWikipediaUrl,
            selectedIndex: $selectedIndex,
            isVideoMuted: $isVideoMuted,
            videoPlaybackCoordinator: videoPlaybackCoordinator,
            dependencies: dependencies,
            onVideoAvailabilityChange: handleVideoAvailabilityChange,
            isAudioBoostEnabled: $isAudioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: onAudioBoostActionFinished,
            onAudioBoostToggleRequested: onAudioBoostToggleRequested,
            onImageSuccess: { handleImageSuccess(identifier: $0) },
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

    private var selectedFocusInteractionIdentity: FocusInteractionIdentity {
        let selectedPage = carouselPages[safe: selectedIndex]
        return FocusInteractionIdentity(
            scanID: carouselScanIdentity,
            stillImageSourceIndex: selectedPage?.stillImageSourceIndex
        )
    }

    private var carouselScanIdentity: String? {
        focusOverlayInteractionState.resolvedScanID(for: scanId)
    }

    #if DEBUG
    private var analyzingCarouselContinuityValue: String {
        let pageID = carouselPages[safe: selectedIndex]?.id ?? "none"
        return "\(analyzingAnimationSession.continuityToken.uuidString)|\(pageID)"
    }
    #endif

    private func committedFocusRectBinding(
        for identity: FocusInteractionIdentity
    ) -> Binding<NormalizedFocusOverlayRect?> {
        Binding(
            get: { focusOverlayInteractionState[identity] },
            set: { committedRect in
                var updatedState = focusOverlayInteractionState
                updatedState[identity] = committedRect
                focusOverlayInteractionState = updatedState
            }
        )
    }

    private var isSelectedVideoUnavailable: Bool {
        guard let page = carouselPages[safe: selectedIndex],
              page.mediaKind == .video else {
            return false
        }
        return unavailableVideoPageIDs.contains(page.id)
    }

    @ViewBuilder
    private var videoMuteControl: some View {
        if selectedMediaKind == .video, !isSelectedVideoUnavailable {
            InsightCarouselVideoMuteControl(
                isMuted: $isVideoMuted,
                feedback: {
                    dependencies.lightImpactFeedback(0.45, nil)
                }
            )
        }
    }

    @ViewBuilder
    private var referenceAttributionTag: some View {
        if let label = selectedReferenceAttributionLabel {
            InsightCarouselReferenceAttributionTag(label: label)
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: label
                )
        }
    }

    private func handleCarouselTap(
        at location: CGPoint,
        containerSize: CGSize
    ) {
        guard !MediaCarouselInteractionPolicy.isCenterPlaybackTap(
            location: location,
            containerSize: containerSize,
            mediaKind: selectedMediaKind
        ) else { return }

        handleVisualImageTap()
    }

    private func handleVisualImageTap() {
        let pages = carouselPages
        guard let selectedPage = pages[safe: selectedIndex] else { return }
        guard !selectedPage.isUserMediaZeroState else { return }
        guard selectedPage.mediaKind != .video
            || !isSelectedVideoUnavailable else { return }
        if let imageIdentifier = selectedPage.imageIdentifier,
           unavailableImageIdentifiers.contains(imageIdentifier) {
            return
        }

        guard let presentation = InsightImageGalleryBuilder.presentation(
            items: pages.compactMap { page -> MediaGalleryItem? in
                if let identifier = page.imageIdentifier,
                   unavailableImageIdentifiers.contains(identifier) {
                    return nil
                }
                return page.galleryItem
            },
            selectedCarouselPageID: selectedPage.id,
            isVideoMuted: isVideoMuted
        ) else { return }

        videoPlaybackCoordinator.pauseForFullscreenPresentation()
        onVisualImageTap?(presentation)
    }

    private func handleVideoAvailabilityChange(
        pageID: String,
        isUnavailable: Bool
    ) {
        let previousPages = carouselPages
        let selectedPage = previousPages[safe: selectedIndex]
        var nextUnavailableVideoPageIDs = unavailableVideoPageIDs
        let didChange: Bool
        if isUnavailable {
            didChange = nextUnavailableVideoPageIDs.insert(pageID).inserted
        } else {
            didChange = nextUnavailableVideoPageIDs.remove(pageID) != nil
        }
        guard didChange else { return }

        let updatedPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourceCarouselPages,
            unavailableIdentifiers: unavailableImageIdentifiers,
            loadedReferenceIdentifiers: loadedReferenceImageIdentifiers,
            unavailableVideoPageIDs: nextUnavailableVideoPageIDs
        )
        unavailableVideoPageIDs = nextUnavailableVideoPageIDs
        selectedIndex = CarouselSelectionResolver.selectedIndex(
            preserving: selectedPage?.id,
            previousSelectedIndex: selectedIndex,
            in: updatedPages,
            loadedReferenceIdentifiers: loadedReferenceImageIdentifiers
        )
    }

    private func handleImageFailure(identifier: String) {
        updateImageAvailability(identifier: identifier, isUnavailable: true)
    }

    private func handleImageSuccess(identifier: String) {
        updateImageAvailability(identifier: identifier, isUnavailable: false)
    }

    private func updateImageAvailability(
        identifier: String,
        isUnavailable: Bool
    ) {
        let previousPages = carouselPages
        let selectedPage = previousPages[safe: selectedIndex]
        var nextUnavailableIdentifiers = unavailableImageIdentifiers
        var nextLoadedReferenceIdentifiers = loadedReferenceImageIdentifiers
        let imageOrigin = previousPages.first(where: {
            $0.imageIdentifier == identifier
        })?.imageOrigin ?? sourceCarouselPages.first(where: {
            $0.imageIdentifier == identifier
        })?.imageOrigin
        var didChange = false

        if isUnavailable {
            didChange = nextUnavailableIdentifiers.insert(identifier).inserted
                || didChange
            didChange = nextLoadedReferenceIdentifiers.remove(identifier) != nil
                || didChange
        } else {
            didChange = nextUnavailableIdentifiers.remove(identifier) != nil
                || didChange
            if imageOrigin == .reference {
                didChange = nextLoadedReferenceIdentifiers.insert(identifier)
                    .inserted || didChange
            }
        }
        guard didChange else { return }

        let updatedPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourceCarouselPages,
            unavailableIdentifiers: nextUnavailableIdentifiers,
            loadedReferenceIdentifiers: nextLoadedReferenceIdentifiers,
            unavailableVideoPageIDs: unavailableVideoPageIDs
        )
        unavailableImageIdentifiers = nextUnavailableIdentifiers
        loadedReferenceImageIdentifiers = nextLoadedReferenceIdentifiers
        selectedIndex = CarouselSelectionResolver.selectedIndex(
            preserving: selectedPage?.id,
            previousSelectedIndex: selectedIndex,
            in: updatedPages,
            loadedReferenceIdentifiers: nextLoadedReferenceIdentifiers
        )
    }
}
