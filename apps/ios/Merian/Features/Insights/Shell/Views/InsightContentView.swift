import SwiftData
import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    /// Passed directly from `InsightSheetView` as a plain stored property so it reflects
    /// the current struct value — unaffected by the `@State` initialization timing issue
    /// where `.sheet(isPresented:)` pre-evaluates the body with `scanToManage = nil`.
    var queuedScan: QueuedScanContext?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?

    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    @State private var isObservationSheetPresented = false
    @State private var fullscreenGalleryPresentation: InsightImageGalleryPresentation?
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
                        onDescriptionTap: { isObservationSheetPresented = true },
                        onVisualImageTap: { presentation in
                            fullscreenGalleryPresentation = presentation
                        },
                        isAudioBoostEnabled: $viewModel.state.isAudioBoostEnabled,
                        audioBoostActionToken: viewModel.state.audioBoostActionToken,
                        onAudioBoostActionFinished: viewModel.finishAudioBoostAction,
                        onAudioBoostToggleRequested: viewModel.toggleAudioBoostFromMedia
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
        .modifier(InsightTopScrollEdgeEffectModifier(
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
        .sheet(isPresented: Binding(
            get: {
                viewModel.state.sharedExplorePostId != nil &&
                    viewModel.state.isExplorePostComposerPresented
            },
            set: { viewModel.state.isExplorePostComposerPresented = $0 }
        )) {
            explorePostComposerSheet
        }
        .sheet(isPresented: candidateSwipePresentedBinding) {
            let candidates = viewModel.candidateSwipeCandidates
            if let speciesData = inferenceEngine.speciesData, !candidates.isEmpty {
                CandidateSwipeModal(
                    isPresented: candidateSwipePresentedBinding,
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
                promptContext: viewModel.fieldNotesPromptContext,
                visibilityConfiguration: viewModel.state.sharedExplorePostId == nil ? nil : FieldNotesVisibilityConfiguration(
                    initialIsPublic: viewModel.state.exploreFieldNotesArePublic,
                    onSave: { text, isPublic in
                        await viewModel.saveFieldNotesAndExploreVisibility(
                            text,
                            isPublic: isPublic,
                            modelContext: modelContext
                        )
                    }
                )
            )
        }
        .sheet(isPresented: $isObservationSheetPresented) {
            if let context = viewModel.observationContext {
                InsightDescriptionSheet(text: context.freeText)
            }
        }
        .fullScreenCover(item: $fullscreenGalleryPresentation) { presentation in
            InsightFullscreenImageCarousel(presentation: presentation)
        }
    }
}

private struct InsightTopScrollEdgeEffectModifier: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(isHidden, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Subcomponents
private extension InsightContentView {

    var candidateSwipePresentedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.isCandidateSwipePresented },
            set: { isPresented in
                viewModel.state.isCandidateSwipePresented = isPresented
                if !isPresented {
                    viewModel.state.candidateSwipePresentationSource = .standard
                }
            }
        )
    }

    @ViewBuilder
    var explorePostComposerSheet: some View {
        if let speciesData = inferenceEngine.speciesData {
            ExplorePostComposerView(
                mode: .edit,
                speciesName: viewModel.resolvedHeaderTitle,
                scientificName: speciesData.scientificName,
                heroImageUrl: viewModel.toolbarRecordSnapshot?.coverImagePath ??
                    inferenceEngine.activeMedia.imagePathsForUpload.first,
                publicLocationLabel: visiblePublicLocationLabel(from: speciesData.locationName),
                commonNameOptions: viewModel.allNamesForPicker,
                initialSelectedCommonName: viewModel.resolvedHeaderTitle,
                initialFieldNotes: viewModel.shareableFieldNotes,
                initialFieldNotesArePublic: viewModel.state.exploreFieldNotesArePublic,
                initialHashtags: viewModel.state.sharedExploreHashtags,
                initialLocationSharing: viewModel.state.sharedExploreLocationSharing ?? defaultLocationSharing,
                mediaItems: viewModel.toolbarRecordSnapshot?.exploreMediaItems ?? [],
                hashtagSuggestionContext: exploreHashtagSuggestionContext(for: speciesData),
                isSaving: viewModel.state.isUpdatingExplorePostContent,
                onSubmit: { draft in
                    Task {
                        await viewModel.updateExplorePostContent(
                            draft,
                            modelContext: modelContext
                        )
                    }
                    viewModel.state.isExplorePostComposerPresented = false
                }
            )
        }
    }

    private func exploreHashtagSuggestionContext(for speciesData: SpeciesData) -> ExploreHashtagSuggestionContext {
        ExploreHashtagSuggestionContext(
            speciesName: viewModel.resolvedHeaderTitle,
            scientificName: speciesData.scientificName,
            publicLocationLabel: visiblePublicLocationLabel(from: speciesData.locationName),
            fieldNotes: viewModel.shareableFieldNotes,
            ecologyType: speciesData.ecologyType,
            taxonomyKingdom: speciesData.taxonomy?.kingdom ?? viewModel.toolbarRecordSnapshot?.taxonomyKingdom,
            taxonomyClass: speciesData.taxonomy?.className ?? viewModel.toolbarRecordSnapshot?.taxonomyClass,
            taxonomyOrder: speciesData.taxonomy?.order ?? viewModel.toolbarRecordSnapshot?.taxonomyOrder,
            taxonomyFamily: speciesData.taxonomy?.family ?? viewModel.toolbarRecordSnapshot?.taxonomyFamily,
            habitatDescription: speciesData.habitatDescription ?? viewModel.toolbarRecordSnapshot?.habitatDescription,
            weatherCondition: speciesData.weatherCondition ?? viewModel.toolbarRecordSnapshot?.weatherCondition,
            colors: speciesData.colors ?? [],
            groupTags: speciesData.groupTags ?? [],
            semanticTags: viewModel.toolbarRecordSnapshot?.semanticTags ?? [],
            isInvasive: speciesData.isInvasive,
            imageQualityScore: speciesData.imageQualityScore ?? viewModel.toolbarRecordSnapshot?.imageQualityScore,
            lifeStage: speciesData.lifeStage,
            reproductiveCondition: speciesData.reproductiveCondition,
            ecologicalInteractions: speciesData.ecologicalInteractions ?? []
        )
        .updating(fieldNotes: viewModel.shareableFieldNotes)
    }

    private func visiblePublicLocationLabel(from locationName: String?) -> String? {
        ExploreLocationPrivacy.displayLabel(from: locationName)
    }

    private var defaultLocationSharing: ExplorePostLocationSharing {
        switch profileViewModel.defaultGeoprivacy {
        case "open":
            return .open
        case "private":
            return .privateLocation
        default:
            return .obscured
        }
    }

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
