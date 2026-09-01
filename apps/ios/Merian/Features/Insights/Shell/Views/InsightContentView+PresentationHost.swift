import SwiftData
import SwiftUI

extension InsightContentView {
    var resolvedPresentation: InsightContentPresentation? {
        if let gallery = fullscreenGalleryPresentedBinding.wrappedValue,
           let scanId = fullscreenGalleryPresentationScanId,
           let generation = fullscreenGalleryPresentationGeneration {
            return .gallery(gallery, scanId: scanId, generation: generation)
        }
        if candidateSwipePresentedBinding.wrappedValue,
           let scanId = viewModel.state.candidateSwipePresentationScanId,
           let generation = viewModel.state.candidateSwipePresentationGeneration,
           let engineGeneration =
            viewModel.state.candidateSwipeEnginePresentationGeneration {
            return .candidate(
                scanId: scanId,
                generation: generation,
                engineGeneration: engineGeneration
            )
        }
        if communityRequestPresentedBinding.wrappedValue,
           let scanId = viewModel.state.communityRequestPresentationScanId,
           let generation = viewModel.state.communityRequestPresentationGeneration {
            return .community(
                scanId: scanId,
                generation: generation,
                requestId: viewModel.state.communityRequestPresentationRequestId
            )
        }
        if explorePostComposerPresentedBinding.wrappedValue,
           let scanId = viewModel.state.explorePostComposerPresentationScanId,
           let generation = viewModel.state.explorePostComposerPresentationGeneration,
           let postId = viewModel.state.explorePostComposerPresentationPostId {
            return .composer(
                scanId: scanId,
                generation: generation,
                postId: postId
            )
        }
        if fieldNotesPresentedBinding.wrappedValue,
           let scanId = viewModel.state.fieldNotesPresentationScanId,
           let generation = viewModel.state.fieldNotesPresentationGeneration {
            return .fieldNotes(scanId: scanId, generation: generation)
        }
        if safariPresentedBinding.wrappedValue,
           let scanId = viewModel.state.safariPresentationScanId,
           let generation = viewModel.state.safariPresentationGeneration,
           let url = viewModel.state.selectedWikiURL {
            return .safari(scanId: scanId, generation: generation, url: url)
        }
        if observationPresentedBinding.wrappedValue,
           let scanId = observationPresentationScanId,
           let generation = observationPresentationGeneration {
            return .observation(scanId: scanId, generation: generation)
        }
        return nil
    }

    var consolidatedSheetPresentationBinding: Binding<InsightContentPresentation?> {
        Binding(
            get: {
                guard resolvedPresentation?.usesFullscreenCover == false else {
                    return nil
                }
                return resolvedPresentation
            },
            set: { presentation in
                guard presentation == nil,
                      let active = resolvedPresentation,
                      !active.usesFullscreenCover else { return }
                dismissConsolidatedPresentation(active)
            }
        )
    }

    var consolidatedFullscreenPresentationBinding: Binding<InsightContentPresentation?> {
        Binding(
            get: {
                guard resolvedPresentation?.usesFullscreenCover == true else {
                    return nil
                }
                return resolvedPresentation
            },
            set: { presentation in
                guard presentation == nil,
                      let active = resolvedPresentation,
                      active.usesFullscreenCover else { return }
                dismissConsolidatedPresentation(active)
            }
        )
    }

    @ViewBuilder
    func consolidatedSheetContent(
        _ presentation: InsightContentPresentation
    ) -> some View {
        switch presentation {
        case .safari(let scanId, let generation, let url):
            if viewModel.isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ), viewModel.state.selectedWikiURL == url {
                SafariView(url: url)
                    .ignoresSafeArea()
            }

        case .community(let scanId, let communityGeneration, let requestId):
            if viewModel.isPresentingLocalRecord(
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
                        ) else { return }
                        viewModel.state.toastMessage = .error(message)
                    },
                    onSubmit: { note, locationSharing in
                        guard isCommunityRequestPresentationCurrent(
                            scanId: scanId,
                            generation: communityGeneration,
                            requestId: requestId
                        ) else { return }
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

        case .composer:
            explorePostComposerSheet

        case .candidate(let scanId, let candidateGeneration, let engineGeneration):
            let candidates = viewModel.candidateSwipeCandidates
            if viewModel.isPresentingLocalRecord(
                scanId: scanId,
                generation: candidateGeneration
            ),
            engineGeneration == inferenceEngine.scanPresentationGeneration,
            let speciesData = inferenceEngine.speciesData,
            speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame,
            !candidates.isEmpty {
                CandidateSwipeModal(
                    isPresented: candidateSwipePresentedBinding,
                    scanId: scanId,
                    presentationGeneration: engineGeneration,
                    candidates: candidates,
                    confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                    allowsAskCommunity: viewModel.canRequestCommunityIdentification,
                    allowsRefinement: true,
                    onRequestDismissalAction: { request in
                        pendingCandidateSwipeDismissalRequest =
                            InsightCandidateSwipeDismissalRequest(
                                request: request,
                                localPresentationGeneration: candidateGeneration
                            )
                    }
                )
            }

        case .fieldNotes(let scanId, let generation):
            if generation == viewModel.scanBoundActionGeneration,
               viewModel.currentFieldNotesScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame {
                FieldNotesSheet(
                    text: Binding(
                        get: { viewModel.fieldNotesText },
                        set: {
                            viewModel.updateFieldNotes(
                                $0,
                                expectedScanId: scanId,
                                expectedGeneration: generation,
                                modelContext: modelContext
                            )
                        }
                    ),
                    promptContext: viewModel.fieldNotesPromptContext,
                    visibilityConfiguration: viewModel.isPresentingLocalRecord(
                        scanId: scanId
                    ) && viewModel.state.sharedExplorePostId != nil
                        ? FieldNotesVisibilityConfiguration(
                            initialIsPublic: viewModel.state.exploreFieldNotesArePublic,
                            onSave: { text, isPublic in
                                await viewModel.saveFieldNotesAndExploreVisibility(
                                    text,
                                    isPublic: isPublic,
                                    expectedScanId: scanId,
                                    expectedGeneration: generation,
                                    modelContext: modelContext
                                )
                            }
                        )
                        : nil
                )
            }

        case .observation(let scanId, let generation):
            if viewModel.isPresentingMedia(
                scanId: scanId,
                generation: generation
            ), let context = viewModel.observationContext {
                InsightDescriptionSheet(text: context.freeText)
            }

        case .gallery:
            EmptyView()
        }
    }

    @ViewBuilder
    func consolidatedFullscreenContent(
        _ presentation: InsightContentPresentation
    ) -> some View {
        switch presentation {
        case .gallery(let gallery, let scanId, let generation):
            if viewModel.isPresentingMedia(
                scanId: scanId,
                generation: generation
            ) {
                FullscreenMediaGallery(
                    presentation: gallery,
                    dependencies: .insightLive
                )
            }
        case .candidate, .community, .composer, .fieldNotes,
             .safari, .observation:
            EmptyView()
        }
    }

    func dismissConsolidatedPresentation(
        _ presentation: InsightContentPresentation
    ) {
        guard resolvedPresentation?.id == presentation.id else { return }
        switch presentation {
        case .gallery:
            fullscreenGalleryPresentedBinding.wrappedValue = nil
        case .candidate:
            candidateSwipePresentedBinding.wrappedValue = false
        case .community:
            communityRequestPresentedBinding.wrappedValue = false
        case .composer:
            explorePostComposerPresentedBinding.wrappedValue = false
        case .fieldNotes:
            fieldNotesPresentedBinding.wrappedValue = false
        case .safari:
            safariPresentedBinding.wrappedValue = false
        case .observation:
            observationPresentedBinding.wrappedValue = false
        }
    }

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

}
