import SwiftData
import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(ProfileViewModel.self) var profileViewModel
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    /// Passed directly from `InsightSheetView` as a plain stored value so the router can use
    /// the queued snapshot during the brief window before `viewModel.queuedContext` is bound.
    var queuedScan: QueuedScanContext?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?

    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    @State var isObservationSheetPresented = false
    @State var observationPresentationScanId: String?
    @State var observationPresentationGeneration: UInt64?
    @State var fullscreenGalleryPresentation: InsightImageGalleryPresentation?
    @State var fullscreenGalleryPresentationScanId: String?
    @State var fullscreenGalleryPresentationGeneration: UInt64?
    @State var pendingCandidateSwipeDismissalRequest:
        InsightCandidateSwipeDismissalRequest?
    private var presentationQueuedScan: QueuedScanContext? {
        viewModel.queuedContext ?? (viewModel.activeLocalRecord == nil ? queuedScan : nil)
    }

    // MARK: - View
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {

                // 1. DYNAMIC STRETCHY CAROUSEL HEADER
                // Embeds firmly inside the native ScrollView to bypass NavigationStack safe area clipping perfectly.
                GeometryReader { proxy in
                    let heroFrame = proxy.frame(in: .named("InsightScrollSpace"))
                    let scrollY = heroFrame.minY
                    // MASSIVE FIX: The 'bleedBuffer' forces the image to natively render 50px taller and shifted 50px upward out of viewport.
                    // This creates a physical pixel bridge seamlessly masking `TabView` vertical pan-gesture framework synchronization tearing.
                    let bleedBuffer: CGFloat = 50

                    let activeQueuedContext = presentationQueuedScan
                    let carouselScanId =
                        activeQueuedContext?.id ?? viewModel.persistentScanId
                    let carouselGeneration = viewModel.scanBoundActionGeneration
                    let activeIsProcessing = viewModel.isCarouselAnalysisActive(
                        for: activeQueuedContext
                    )

                    let activeMedia = viewModel.resolvedMedia(for: activeQueuedContext)

                    ImagesCarousel(
                        scanId: carouselScanId,
                        activeMedia: activeMedia,
                        referenceWikipediaUrl: inferenceEngine.speciesData?.wikipediaUrl,
                        isProcessing: activeIsProcessing,
                        onDescriptionTap: {
                            guard let carouselScanId,
                                  viewModel.isPresentingMedia(
                                      scanId: carouselScanId,
                                      generation: carouselGeneration
                                  ) else {
                                return
                            }
                            observationPresentationScanId = carouselScanId
                            observationPresentationGeneration = carouselGeneration
                            isObservationSheetPresented = true
                        },
                        onVisualImageTap: { presentation in
                            guard let carouselScanId,
                                  viewModel.isPresentingMedia(
                                      scanId: carouselScanId,
                                      generation: carouselGeneration
                                  ) else {
                                return
                            }
                            fullscreenGalleryPresentationScanId = carouselScanId
                            fullscreenGalleryPresentationGeneration = carouselGeneration
                            fullscreenGalleryPresentation = presentation
                        },
                        focusOverlayInteractionState: $viewModel.focusOverlayInteractionState,
                        isAudioBoostEnabled: carouselAudioBoostBinding(
                            scanId: carouselScanId,
                            generation: carouselGeneration
                        ),
                        audioBoostActionToken: viewModel.state.audioBoostActionToken,
                        onAudioBoostActionFinished: viewModel.finishAudioBoostAction,
                        onAudioBoostToggleRequested: {
                            guard let carouselScanId else { return }
                            viewModel.toggleAudioBoostFromMedia(
                                expectedScanId: carouselScanId,
                                expectedGeneration: carouselGeneration
                            )
                        }
                    )
                        .frame(width: imageSize, height: scrollY > 0 ? imageSize + scrollY + bleedBuffer : imageSize + bleedBuffer)
                        .offset(y: scrollY > 0 ? -(scrollY + bleedBuffer) : -bleedBuffer)
                        .ignoresSafeArea(.all, edges: .top) // CRUESCIAL: Kills the 16pt sheet native dragging padding!
                        .onChange(of: heroFrame.maxY, initial: true) { _, newMaxY in
                            viewModel.evaluateHeroScrollOffset(maxY: newMaxY)
                        }
                }
                .frame(height: imageSize)
                .ignoresSafeArea(.all, edges: .top) // Ensure the entire geometry wrapper bypasses top safe area
                .zIndex(0)

                // 2. OVERLAPPING BOTTOM SHEET CONTENT
                InsightContentRouterView(
                    viewModel: viewModel,
                    queuedScan: presentationQueuedScan,
                    onOpenFieldTripOverview: onOpenFieldTripOverview
                )
                    .padding(.top, overlapRadius)
                    .frame(maxWidth: .infinity)
                    .background(contentSheetBackground)
                    .offset(y: -overlapRadius)
                    .padding(.bottom, -overlapRadius)
                    .zIndex(1)
            }
            .frame(width: imageSize) // CLAMP: Physically guarantees the content bounds can never expand left/right even if child views attempt to breach safe area X bounds.
        }
        .coordinateSpace(name: "InsightScrollSpace")
        .modifier(MediaHeroTopScrollEdgeEffectModifier(
            isHidden: viewModel.state.isTopScrollEdgeEffectHidden
        ))
        // Forces native underlap of the translucent NavigationBar completely!
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent) // CRITICAL: Eradicates hidden iOS 17 interior scroll canvas offsets!
        .textSelection(.enabled)

        // Data Mapping Override
        .onAppear {
            viewModel.inferenceEngine = inferenceEngine
        }

        // One typed modal owner prevents sibling SwiftUI sheet hosts from
        // racing when independent feature state changes in the same render.
        .sheet(
            item: consolidatedSheetPresentationBinding,
            onDismiss: resumePendingCandidateSwipeDismissalRequest
        ) { presentation in
            consolidatedSheetContent(presentation)
        }
        .fullScreenCover(item: consolidatedFullscreenPresentationBinding) { presentation in
            consolidatedFullscreenContent(presentation)
        }
    }
}

private extension InsightContentView {
    /// The rounded white background encapsulating the structural content cards smoothly.
    @ViewBuilder
    var contentSheetBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: overlapRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: overlapRadius
        )
        .fill(Color(uiColor: .systemBackground))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
        // OVERSCROLL PROTECTION: Physically expands the drawn background infinitely downwards without affecting structural layout height, sealing any visual gaps when the user pulls up past the bottom natively!
        .padding(.bottom, -1000)
    }
}
