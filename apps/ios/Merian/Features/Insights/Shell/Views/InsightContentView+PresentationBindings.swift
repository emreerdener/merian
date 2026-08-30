import SwiftUI

extension InsightContentView {
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

    func resumePendingCandidateSwipeDismissalRequest() {
        guard let pending = pendingCandidateSwipeDismissalRequest else { return }
        pendingCandidateSwipeDismissalRequest = nil

        let request = pending.request
        guard viewModel.isPresentingLocalRecord(
            scanId: request.scanId,
            generation: pending.localPresentationGeneration
        ),
        inferenceEngine.scanPresentationGeneration == request.presentationGeneration,
        inferenceEngine.speciesData?.scanId?
            .caseInsensitiveCompare(request.scanId) == .orderedSame else {
            return
        }

        switch request.action {
        case .applyOverride(let scientificName):
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(
                    scanId: request.scanId,
                    generation: pending.localPresentationGeneration
                ),
                inferenceEngine.scanPresentationGeneration ==
                    request.presentationGeneration else {
                    return
                }
                await inferenceEngine.applyIdentificationOverride(
                    scientificName: scientificName,
                    expectedScanId: request.scanId,
                    modelContext: modelContext
                )
            }
        case .confirmOriginal:
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(
                    scanId: request.scanId,
                    generation: pending.localPresentationGeneration
                ) else {
                    return
                }
                await inferenceEngine.confirmAIIdentification(
                    expectedScanId: request.scanId,
                    modelContext: modelContext
                )
            }
        case .askCommunity:
            guard viewModel.canRequestCommunityIdentification else { return }
            viewModel.presentCommunityIdentificationRequest(
                expectedScanId: request.scanId,
                expectedGeneration: pending.localPresentationGeneration
            )
        case .refineScan:
            viewModel.dependencies.selectionFeedback()
            viewModel.dependencies.requestRefinement(
                request.scanId,
                viewModel.shareableFieldNotes
            )
        }
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
}
