import SwiftData
import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    /// Passed directly from `InsightSheetView` as a plain stored property so it reflects
    /// the current struct value — unaffected by the `@State` initialization timing issue
    /// where `.sheet(isPresented:)` pre-evaluates the body with `scanToManage = nil`.
    var queuedScan: QueuedScanContext?

    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    @State private var isObservationSheetPresented = false
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
                    let scrollY = proxy.frame(in: .named("InsightScrollSpace")).minY
                    // MASSIVE FIX: The 'bleedBuffer' forces the image to natively render 50px taller and shifted 50px upward out of viewport.
                    // This creates a physical pixel bridge seamlessly masking `TabView` vertical pan-gesture framework synchronization tearing.
                    let bleedBuffer: CGFloat = 50

                    let activeQueuedContext = presentationQueuedScan
                    let activeIsProcessing = activeQueuedContext?.queueState == .inferencing
                        || (activeQueuedContext == nil && viewModel.isProcessing)

                    let activeMedia = viewModel.resolvedMedia(for: activeQueuedContext)

                    ImagesCarousel(
                        scanId: activeQueuedContext?.id ?? viewModel.persistentScanId,
                        activeMedia: activeMedia,
                        referenceWikipediaUrl: inferenceEngine.speciesData?.wikipediaUrl,
                        isProcessing: activeIsProcessing,
                        onImageFailure: { path in
                            guard activeQueuedContext == nil else { return }
                            inferenceEngine.dropInvalidCarouselImage(path)
                        },
                        onDescriptionTap: { isObservationSheetPresented = true }
                    )
                        .frame(width: imageSize, height: scrollY > 0 ? imageSize + scrollY + bleedBuffer : imageSize + bleedBuffer)
                        .offset(y: scrollY > 0 ? -(scrollY + bleedBuffer) : -bleedBuffer)
                        .ignoresSafeArea(.all, edges: .top) // CRUESCIAL: Kills the 16pt sheet native dragging padding!
                }
                .frame(height: imageSize)
                .ignoresSafeArea(.all, edges: .top) // Ensure the entire geometry wrapper bypasses top safe area
                .zIndex(0)

                // 2. OVERLAPPING BOTTOM SHEET CONTENT
                InsightContentRouterView(viewModel: viewModel, queuedScan: presentationQueuedScan)
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
        // Forces native underlap of the translucent NavigationBar completely!
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent) // CRITICAL: Eradicates hidden iOS 17 interior scroll canvas offsets!
        .textSelection(.enabled)

        // Data Mapping Override
        .onAppear {
            viewModel.inferenceEngine = inferenceEngine
        }

        // Modal Routings
        .sheet(isPresented: $viewModel.state.isSafariPresented) {
            if let safeUrl = viewModel.state.selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $viewModel.state.isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                ReportInsightView(scanId: scanId) {
                    withAnimation { viewModel.state.toastMessage = "Report submitted. Thanks!" }
                }
            }
        }
        .sheet(isPresented: $viewModel.state.isCommunityRequestSheetPresented) {
            if let speciesData = inferenceEngine.speciesData {
                CommunityIdentificationRequestSheet(
                    speciesName: viewModel.resolvedHeaderTitle,
                    scientificName: speciesData.scientificName,
                    existingRequestId: viewModel.state.sharedCommunityIdentificationRequestId,
                    initialNote: nil,
                    initialLocationSharing: viewModel.state.sharedExploreLocationSharing,
                    shouldLoadExistingRequestDetail: true,
                    isSubmitting: viewModel.state.isRequestingCommunityIdentification,
                    onLoadFailed: { message in
                        viewModel.state.toastMessage = message
                    },
                    onSubmit: { note, locationSharing in
                        Task {
                            if viewModel.state.sharedCommunityIdentificationRequestId != nil {
                                await viewModel.updateCommunityIdentificationRequest(
                                    note: note,
                                    locationSharing: locationSharing
                                )
                            } else {
                                await viewModel.requestCommunityIdentification(
                                    note: note,
                                    locationSharing: locationSharing,
                                    modelContext: modelContext
                                )
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.state.isCandidateSwipePresented) {
            let candidates = viewModel.reviewAlternativeCandidates
            if let speciesData = inferenceEngine.speciesData, !candidates.isEmpty {
                CandidateSwipeModal(
                    isPresented: $viewModel.state.isCandidateSwipePresented,
                    candidates: candidates,
                    aiScientificName: speciesData.scientificName,
                    confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                    onConfirmOriginal: { Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) } },
                    onAskCommunity: {
                        viewModel.state.isCommunityRequestSheetPresented = true
                    },
                    onRefineScan: {
                        guard let scanIdStr = speciesData.scanId else { return }
                        HapticManager.shared.triggerSelectionPulse()
                        AppEventPublisher.shared.send(.triggerRefinement(
                            scanId: scanIdStr,
                            initialDescription: viewModel.shareableFieldNotes
                        ))
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.state.isFieldNotesSheetPresented) {
            FieldNotesSheet(
                text: Binding(
                    get: { viewModel.fieldNotesText },
                    set: { viewModel.updateFieldNotes($0, modelContext: modelContext) }
                ),
                promptContext: viewModel.fieldNotesPromptContext
            )
        }
        .sheet(isPresented: $isObservationSheetPresented) {
            if let context = viewModel.observationContext {
                InsightDescriptionSheet(text: context.freeText)
            }
        }
    }
}

// MARK: - Subcomponents
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
