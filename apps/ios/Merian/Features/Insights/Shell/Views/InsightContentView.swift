import SwiftData
import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    /// Passed directly from `InsightSheetView` as a plain stored value so the router can use
    /// the queued snapshot during the brief window before `viewModel.queuedContext` is bound.
    var queuedScan: QueuedScanContext?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?

    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    @State private var isObservationSheetPresented = false
    @State private var observationPresentationScanId: String?
    @State private var observationPresentationGeneration: UInt64?
    @State private var fullscreenGalleryPresentation: InsightImageGalleryPresentation?
    @State private var fullscreenGalleryPresentationScanId: String?
    @State private var fullscreenGalleryPresentationGeneration: UInt64?
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
                    let activeIsProcessing = activeQueuedContext?.queueState == .inferencing
                        || (activeQueuedContext == nil && viewModel.isProcessing)

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

        // Modal Routings
        .sheet(isPresented: safariPresentedBinding) {
            if let scanId = viewModel.state.safariPresentationScanId,
               let generation =
                viewModel.state.safariPresentationGeneration,
               viewModel.isPresentingLocalRecord(
                   scanId: scanId,
                   generation: generation
               ),
               let safeUrl = viewModel.state.selectedWikiURL {
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
        .sheet(isPresented: communityRequestPresentedBinding) {
            let requestId =
                viewModel.state.communityRequestPresentationRequestId
            if let scanId = viewModel.state.communityRequestPresentationScanId,
               let communityGeneration =
                viewModel.state.communityRequestPresentationGeneration,
               viewModel.isPresentingLocalRecord(
                   scanId: scanId,
                   generation: communityGeneration
               ),
               optionalIdentifiersMatch(
                   requestId,
                   viewModel.state.sharedCommunityIdentificationRequestId
               ),
               let speciesData = inferenceEngine.speciesData,
               speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame {
                CommunityIdentificationRequestSheet(
                    speciesName: viewModel.resolvedHeaderTitle,
                    scientificName: speciesData.scientificName,
                    existingRequestId: requestId,
                    initialNote: nil,
                    initialLocationSharing: viewModel.state.sharedExploreLocationSharing,
                    shouldLoadExistingRequestDetail: true,
                    isSubmitting: viewModel.state.isRequestingCommunityIdentification,
                    onLoadFailed: { message in
                        guard viewModel.isPresentingLocalRecord(
                            scanId: scanId,
                            generation: communityGeneration
                        ) else {
                            return
                        }
                        viewModel.state.toastMessage = message
                    },
                    onSubmit: { note, locationSharing in
                        guard isCommunityRequestPresentationCurrent(
                            scanId: scanId,
                            generation: communityGeneration,
                            requestId: requestId
                        ) else {
                            return
                        }
                        Task {
                            if requestId != nil {
                                await viewModel.updateCommunityIdentificationRequest(
                                    note: note,
                                    locationSharing: locationSharing,
                                    expectedScanId: scanId,
                                    expectedGeneration: communityGeneration
                                )
                            } else {
                                await viewModel.requestCommunityIdentification(
                                    note: note,
                                    locationSharing: locationSharing,
                                    expectedScanId: scanId,
                                    expectedGeneration: communityGeneration,
                                    modelContext: modelContext
                                )
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: explorePostComposerPresentedBinding) {
            explorePostComposerSheet
        }
        .sheet(isPresented: candidateSwipePresentedBinding) {
            let candidates = viewModel.candidateSwipeCandidates
            if let scanId = viewModel.state.candidateSwipePresentationScanId,
               let candidateGeneration =
                viewModel.state.candidateSwipePresentationGeneration,
               let candidateEngineGeneration =
                viewModel.state.candidateSwipeEnginePresentationGeneration,
               viewModel.isPresentingLocalRecord(
                   scanId: scanId,
                   generation: candidateGeneration
               ),
               candidateEngineGeneration ==
                inferenceEngine.scanPresentationGeneration,
               let speciesData = inferenceEngine.speciesData,
               speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame,
               !candidates.isEmpty {
                CandidateSwipeModal(
                    isPresented: candidateSwipePresentedBinding,
                    scanId: scanId,
                    presentationGeneration: candidateEngineGeneration,
                    candidates: candidates,
                    aiScientificName: speciesData.scientificName,
                    confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                    onConfirmOriginal: {
                        guard viewModel.isPresentingLocalRecord(
                            scanId: scanId,
                            generation: candidateGeneration
                        ) else {
                            return
                        }
                        Task { @MainActor in
                            guard viewModel.isPresentingLocalRecord(
                                scanId: scanId,
                                generation: candidateGeneration
                            ) else {
                                return
                            }
                            await inferenceEngine.confirmAIIdentification(
                                expectedScanId: scanId,
                                modelContext: modelContext
                            )
                        }
                    },
                    onAskCommunity: {
                        if viewModel.canRequestCommunityIdentification {
                            viewModel.presentCommunityIdentificationRequest(
                                expectedScanId: scanId,
                                expectedGeneration: candidateGeneration
                            )
                        }
                    },
                    onRefineScan: {
                        guard viewModel.isPresentingLocalRecord(
                            scanId: scanId,
                            generation: candidateGeneration
                        ) else {
                            return
                        }
                        HapticManager.shared.triggerSelectionPulse()
                        AppEventPublisher.shared.send(.triggerRefinement(
                            scanId: scanId,
                            initialDescription: viewModel.shareableFieldNotes
                        ))
                    }
                )
            }
        }
        .sheet(isPresented: fieldNotesPresentedBinding) {
            if let fieldNotesScanId = viewModel.state.fieldNotesPresentationScanId,
               let fieldNotesGeneration =
                viewModel.state.fieldNotesPresentationGeneration,
               fieldNotesGeneration == viewModel.scanBoundActionGeneration,
               viewModel.currentFieldNotesScanId?
                .caseInsensitiveCompare(fieldNotesScanId) == .orderedSame {
                FieldNotesSheet(
                    text: Binding(
                        get: { viewModel.fieldNotesText },
                        set: {
                            viewModel.updateFieldNotes(
                                $0,
                                expectedScanId: fieldNotesScanId,
                                expectedGeneration: fieldNotesGeneration,
                                modelContext: modelContext
                            )
                        }
                    ),
                    promptContext: viewModel.fieldNotesPromptContext,
                    visibilityConfiguration: viewModel.isPresentingLocalRecord(
                        scanId: fieldNotesScanId
                    ) && viewModel.state.sharedExplorePostId != nil
                        ? FieldNotesVisibilityConfiguration(
                            initialIsPublic: viewModel.state.exploreFieldNotesArePublic,
                            onSave: { text, isPublic in
                                await viewModel.saveFieldNotesAndExploreVisibility(
                                    text,
                                    isPublic: isPublic,
                                    expectedScanId: fieldNotesScanId,
                                    expectedGeneration: fieldNotesGeneration,
                                    modelContext: modelContext
                                )
                            }
                        )
                        : nil
                )
            }
        }
        .sheet(isPresented: observationPresentedBinding) {
            if let scanId = observationPresentationScanId,
               let generation = observationPresentationGeneration,
               viewModel.isPresentingMedia(
                   scanId: scanId,
                   generation: generation
               ),
               let context = viewModel.observationContext {
                InsightDescriptionSheet(text: context.freeText)
            }
        }
        .fullScreenCover(item: fullscreenGalleryPresentedBinding) { presentation in
            InsightFullscreenImageCarousel(presentation: presentation)
        }
    }
}

// MARK: - Subcomponents
private extension InsightContentView {
    func carouselAudioBoostBinding(
        scanId: String?,
        generation: UInt64
    ) -> Binding<Bool> {
        guard let scanId else { return .constant(false) }
        return viewModel.audioBoostBinding(
            expectedScanId: scanId,
            expectedGeneration: generation
        )
    }

    var safariPresentedBinding: Binding<Bool> {
        let expectedScanId = viewModel.state.safariPresentationScanId
        let expectedGeneration =
            viewModel.state.safariPresentationGeneration
        let expectedURL = viewModel.state.selectedWikiURL
        return Binding(
            get: {
                guard viewModel.state.isSafariPresented,
                      let expectedScanId,
                      let expectedGeneration,
                      let expectedURL,
                      viewModel.state.safariPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.safariPresentationGeneration ==
                        expectedGeneration,
                      viewModel.state.selectedWikiURL == expectedURL else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      let expectedURL,
                      viewModel.state.safariPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.safariPresentationGeneration ==
                        expectedGeneration,
                      viewModel.state.selectedWikiURL == expectedURL else {
                    return
                }
                viewModel.state.isSafariPresented = false
                viewModel.state.selectedWikiURL = nil
                viewModel.state.safariPresentationScanId = nil
                viewModel.state.safariPresentationGeneration = nil
            }
        )
    }

    var observationPresentedBinding: Binding<Bool> {
        let expectedScanId = observationPresentationScanId
        let expectedGeneration = observationPresentationGeneration
        return Binding(
            get: {
                guard isObservationSheetPresented,
                      let expectedScanId,
                      let expectedGeneration,
                      observationPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      observationPresentationGeneration ==
                        expectedGeneration else {
                    return false
                }
                return viewModel.isPresentingMedia(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      observationPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      observationPresentationGeneration ==
                        expectedGeneration else {
                    return
                }
                isObservationSheetPresented = false
                observationPresentationScanId = nil
                observationPresentationGeneration = nil
            }
        )
    }

    var fullscreenGalleryPresentedBinding:
        Binding<InsightImageGalleryPresentation?> {
        let expectedPresentation = fullscreenGalleryPresentation
        let expectedScanId = fullscreenGalleryPresentationScanId
        let expectedGeneration = fullscreenGalleryPresentationGeneration
        return Binding(
            get: {
                guard let expectedPresentation,
                      let expectedScanId,
                      let expectedGeneration,
                      fullscreenGalleryPresentation == expectedPresentation,
                      fullscreenGalleryPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      fullscreenGalleryPresentationGeneration ==
                        expectedGeneration,
                      viewModel.isPresentingMedia(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return nil
                }
                return expectedPresentation
            },
            set: { presentation in
                guard presentation == nil else { return }
                guard let expectedPresentation,
                      let expectedScanId,
                      let expectedGeneration,
                      fullscreenGalleryPresentation == expectedPresentation,
                      fullscreenGalleryPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      fullscreenGalleryPresentationGeneration ==
                        expectedGeneration else {
                    return
                }
                fullscreenGalleryPresentation = nil
                fullscreenGalleryPresentationScanId = nil
                fullscreenGalleryPresentationGeneration = nil
            }
        )
    }

    var candidateSwipePresentedBinding: Binding<Bool> {
        let expectedScanId =
            viewModel.state.candidateSwipePresentationScanId
        let expectedGeneration =
            viewModel.state.candidateSwipePresentationGeneration
        let expectedEngineGeneration =
            viewModel.state.candidateSwipeEnginePresentationGeneration
        return Binding(
            get: {
                guard viewModel.state.isCandidateSwipePresented,
                      let expectedScanId,
                      let expectedGeneration,
                      let expectedEngineGeneration,
                      viewModel.state.candidateSwipePresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.candidateSwipePresentationGeneration ==
                        expectedGeneration,
                      viewModel.state
                        .candidateSwipeEnginePresentationGeneration ==
                        expectedEngineGeneration,
                      inferenceEngine.scanPresentationGeneration ==
                        expectedEngineGeneration else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      let expectedEngineGeneration,
                      viewModel.state.candidateSwipePresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.candidateSwipePresentationGeneration ==
                        expectedGeneration,
                      viewModel.state
                        .candidateSwipeEnginePresentationGeneration ==
                        expectedEngineGeneration else {
                    return
                }
                viewModel.state.isCandidateSwipePresented = false
                viewModel.state.candidateSwipePresentationSource = .standard
                viewModel.state.candidateSwipePresentationScanId = nil
                viewModel.state.candidateSwipePresentationGeneration = nil
                viewModel.state.candidateSwipeEnginePresentationGeneration = nil
            }
        )
    }

    var communityRequestPresentedBinding: Binding<Bool> {
        let expectedScanId =
            viewModel.state.communityRequestPresentationScanId
        let expectedGeneration =
            viewModel.state.communityRequestPresentationGeneration
        let expectedRequestId =
            viewModel.state.communityRequestPresentationRequestId
        return Binding(
            get: {
                guard let expectedScanId,
                      let expectedGeneration,
                      viewModel.state.communityRequestPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.communityRequestPresentationGeneration ==
                        expectedGeneration,
                      optionalIdentifiersMatch(
                          viewModel.state
                            .communityRequestPresentationRequestId,
                          expectedRequestId
                      ),
                      optionalIdentifiersMatch(
                          viewModel.state
                            .sharedCommunityIdentificationRequestId,
                          expectedRequestId
                      ) else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                ) &&
                    viewModel.state.isCommunityRequestSheetPresented
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      viewModel.state.communityRequestPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.communityRequestPresentationGeneration ==
                        expectedGeneration,
                      optionalIdentifiersMatch(
                          viewModel.state
                            .communityRequestPresentationRequestId,
                          expectedRequestId
                      ) else {
                    return
                }
                viewModel.state.isCommunityRequestSheetPresented = false
                viewModel.state.communityRequestPresentationScanId = nil
                viewModel.state.communityRequestPresentationGeneration = nil
                viewModel.state.communityRequestPresentationRequestId = nil
            }
        )
    }

    var fieldNotesPresentedBinding: Binding<Bool> {
        let expectedScanId = viewModel.state.fieldNotesPresentationScanId
        let expectedGeneration =
            viewModel.state.fieldNotesPresentationGeneration
        return Binding(
            get: {
                guard let expectedScanId,
                      let expectedGeneration,
                      viewModel.state.fieldNotesPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state.fieldNotesPresentationGeneration ==
                        expectedGeneration,
                      expectedGeneration == viewModel.scanBoundActionGeneration,
                      viewModel.currentFieldNotesScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
                    return false
                }
                return viewModel.state.isFieldNotesSheetPresented
            },
            set: { isPresented in
                if isPresented {
                    guard let expectedScanId,
                          let expectedGeneration,
                          viewModel.state.fieldNotesPresentationScanId?
                            .caseInsensitiveCompare(expectedScanId) ==
                            .orderedSame,
                          viewModel.state.fieldNotesPresentationGeneration ==
                            expectedGeneration,
                          viewModel.currentFieldNotesScanId?
                            .caseInsensitiveCompare(expectedScanId) ==
                            .orderedSame,
                          expectedGeneration ==
                            viewModel.scanBoundActionGeneration else {
                        return
                    }
                    viewModel.state.isFieldNotesSheetPresented = true
                } else {
                    guard let expectedScanId,
                          let expectedGeneration,
                          viewModel.state.fieldNotesPresentationScanId?
                            .caseInsensitiveCompare(expectedScanId) ==
                            .orderedSame,
                          viewModel.state.fieldNotesPresentationGeneration ==
                            expectedGeneration else {
                        return
                    }
                    viewModel.state.isFieldNotesSheetPresented = false
                    viewModel.state.fieldNotesPresentationScanId = nil
                    viewModel.state.fieldNotesPresentationGeneration = nil
                }
            }
        )
    }

    var explorePostComposerPresentedBinding: Binding<Bool> {
        let expectedScanId =
            viewModel.state.explorePostComposerPresentationScanId
        let expectedGeneration =
            viewModel.state.explorePostComposerPresentationGeneration
        let expectedPostId =
            viewModel.state.explorePostComposerPresentationPostId
        return Binding(
            get: {
                guard let expectedScanId,
                      let expectedGeneration,
                      let expectedPostId,
                      viewModel.state.explorePostComposerPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state
                        .explorePostComposerPresentationGeneration ==
                        expectedGeneration,
                      viewModel.state.explorePostComposerPresentationPostId?
                        .caseInsensitiveCompare(expectedPostId) == .orderedSame,
                      viewModel.state.sharedExplorePostId?
                        .caseInsensitiveCompare(expectedPostId) == .orderedSame else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                ) &&
                    viewModel.state.sharedExplorePostId != nil &&
                    viewModel.state.isExplorePostComposerPresented
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      let expectedPostId,
                      viewModel.state.explorePostComposerPresentationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      viewModel.state
                        .explorePostComposerPresentationGeneration ==
                        expectedGeneration,
                      viewModel.state.explorePostComposerPresentationPostId?
                        .caseInsensitiveCompare(expectedPostId) == .orderedSame else {
                    return
                }
                viewModel.state.isExplorePostComposerPresented = false
                viewModel.state.explorePostComposerPresentationScanId = nil
                viewModel.state.explorePostComposerPresentationGeneration = nil
                viewModel.state.explorePostComposerPresentationPostId = nil
            }
        )
    }

    @ViewBuilder
    var explorePostComposerSheet: some View {
        if let scanId = viewModel.state.explorePostComposerPresentationScanId,
           let composerGeneration =
            viewModel.state.explorePostComposerPresentationGeneration,
           let postId =
            viewModel.state.explorePostComposerPresentationPostId,
           viewModel.isPresentingLocalRecord(
               scanId: scanId,
               generation: composerGeneration
           ),
           viewModel.state.sharedExplorePostId?
            .caseInsensitiveCompare(postId) == .orderedSame,
           let speciesData = inferenceEngine.speciesData,
           speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame {
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
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: composerGeneration
                    ),
                          viewModel.state
                            .explorePostComposerPresentationScanId?
                            .caseInsensitiveCompare(scanId) == .orderedSame,
                          viewModel.state
                            .explorePostComposerPresentationGeneration ==
                            composerGeneration,
                          viewModel.state
                            .explorePostComposerPresentationPostId?
                            .caseInsensitiveCompare(postId) == .orderedSame,
                          viewModel.state.sharedExplorePostId?
                            .caseInsensitiveCompare(postId) == .orderedSame else {
                        return
                    }
                    Task {
                        await viewModel.updateExplorePostContent(
                            draft,
                            expectedScanId: scanId,
                            expectedGeneration: composerGeneration,
                            modelContext: modelContext
                        )
                    }
                    viewModel.state.isExplorePostComposerPresented = false
                    viewModel.state.explorePostComposerPresentationScanId = nil
                    viewModel.state.explorePostComposerPresentationGeneration = nil
                    viewModel.state.explorePostComposerPresentationPostId = nil
                }
            )
        }
    }

    func isCommunityRequestPresentationCurrent(
        scanId: String,
        generation: UInt64,
        requestId: String?
    ) -> Bool {
        viewModel.isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ) &&
            viewModel.state.communityRequestPresentationScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame &&
            viewModel.state.communityRequestPresentationGeneration ==
                generation &&
            optionalIdentifiersMatch(
                viewModel.state.communityRequestPresentationRequestId,
                requestId
            ) &&
            optionalIdentifiersMatch(
                viewModel.state.sharedCommunityIdentificationRequestId,
                requestId
            )
    }

    func optionalIdentifiersMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default:
            return false
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
