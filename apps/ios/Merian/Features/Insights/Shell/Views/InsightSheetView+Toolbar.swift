import SwiftData
import SwiftUI

extension InsightSheetView {
    @ToolbarContentBuilder
    var sheetToolbar: some ToolbarContent {
        // Queued scan path: the standard ellipsis menu is suppressed (isAnalyzing == true),
        // so surface a dedicated trash button for the only available destructive action.
        if viewModel.queuedContext != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.state.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                            foregroundColor: .red
                        )
                }
                .tint(.red)
                .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
            }
        }

        TopToolbar(
            commonName: viewModel.resolvedHeaderTitle,
            isCommonNameScrolledPast: viewModel.state.isCommonNameScrolledPast,
            isSavingPhotos: $viewModel.state.isSavingPhotos,
            showDeleteConfirmation: $viewModel.state.showDeleteConfirmation,
            hasUserPhotos: viewModel.hasUserPhotos,
            leadingControl: presentationStyle.isEmbedded ? .back : .close,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            allowsFieldNotes: viewModel.contentMode != .nonBiological,
            hasFieldNotes: viewModel.hasFieldNotes,
            onFieldNotes: {
                viewModel.state.isFieldNotesSheetPresented = true
            },
            allowsCollectionActions: viewModel.contentMode != .nonBiological,
            collections: collections,
            selectedCollectionIds: viewModel.toolbarRecordSnapshot?.collectionIds ?? [],
            toggleScanInCollection: { collection in
                viewModel.toggleScanInCollection(collection, modelContext: modelContext)
            },
            showNewCollectionAlert: $viewModel.state.showNewCollectionAlert,
            hasCollectionScanId: viewModel.toolbarRecordSnapshot != nil || inferenceEngine.speciesData?.scanId != nil,
            onReanalyze: viewModel.canReanalyze ? {
                if RevenueCatManager.shared.isProActive {
                    if let record = viewModel.activeLocalRecord {
                        HapticManager.shared.triggerSelectionPulse()
                        AppEventPublisher.shared.send(.triggerRefinement(
                            scanId: record.id,
                            initialDescription: viewModel.shareableFieldNotes
                        ))
                    }
                } else {
                    viewModel.state.showPaywall = true
                }
            } : nil,
            onReviewAlternatives: viewModel.canReviewAlternatives ? {
                viewModel.presentCandidateSwipe()
            } : nil,
            onConfirmIdentification: viewModel.canConfirm ? {
                HapticManager.shared.triggerSuccessPulse()
                Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
            } : nil,
            onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                viewModel.state.isCommunityRequestSheetPresented = true
            } : nil,
            sharedExplorePostId: viewModel.state.sharedExplorePostId,
            sharedCommunityIdentificationRequestId: viewModel.state.sharedCommunityIdentificationRequestId,
            onEditExplorePost: viewModel.state.sharedExplorePostId != nil ? {
                viewModel.state.isExplorePostComposerPresented = true
            } : nil,
            onViewExplorePost: allowsExplorePresentation && viewModel.state.sharedExplorePostId != nil ? {
                viewModel.state.explorePresentationTarget = .post
                viewModel.state.showExploreSheet = true
            } : nil,
            onViewCommunityRequest: allowsExplorePresentation && viewModel.state.sharedCommunityIdentificationRequestId != nil ? {
                viewModel.state.explorePresentationTarget = .communityRequest
                viewModel.state.showExploreSheet = true
            } : nil,
            isAnalyzing: viewModel.isProcessing,
            isProActive: RevenueCatManager.shared.isProActive
        )

        InsightBottomToolbar(
            showBottomBarTools: viewModel.state.showBottomBarTools && !viewModel.isProcessing,
            recordSnapshot: viewModel.toolbarRecordSnapshot,
            canShowInsightChat: canShowInsightChat,
            onInsightChat: {
                if RevenueCatManager.shared.isProActive {
                    guard let scanId = inferenceEngine.speciesData?.scanId else { return }
                    Task { @MainActor in
                        let canPresent = await chatViewModel.prepareForPresentation(scanId: scanId)
                        if canPresent {
                            HapticManager.shared.triggerSheetSpring()
                            viewModel.state.isInsightChatSheetPresented = true
                        } else {
                            HapticManager.shared.triggerErrorThump()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                viewModel.state.toastMessage = chatViewModel.errorMessage
                                    ?? "Field chat isn't available for this scan."
                            }
                        }
                    }
                } else {
                    HapticManager.shared.triggerSelectionPulse()
                    viewModel.state.showPaywall = true
                }
            },
            shareExternally: { viewModel.shareDiscovery(inferenceEngine: inferenceEngine) },
            onShareToExplore: viewModel.canShareToExplore ? { draft in
                Task {
                    await viewModel.shareToExplore(draft, modelContext: modelContext)
                }
            } : nil,
            onEditExplorePost: viewModel.state.sharedExplorePostId != nil ? { draft in
                Task {
                    await viewModel.updateExplorePostContent(
                        draft,
                        modelContext: modelContext
                    )
                }
            } : nil,
            onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                viewModel.state.isCommunityRequestSheetPresented = true
            } : nil,
            onEditCommunityRequest: viewModel.state.sharedCommunityIdentificationRequestId != nil ? {
                viewModel.state.isCommunityRequestSheetPresented = true
            } : nil,
            isSharingToExplore: viewModel.state.isSharingToExplore,
            isUpdatingExplorePostContent: viewModel.state.isUpdatingExplorePostContent,
            displaySpeciesName: viewModel.resolvedHeaderTitle,
            commonNameOptions: viewModel.allNamesForPicker,
            fieldNotesPreview: viewModel.shareableFieldNotes,
            sharedExploreHashtags: viewModel.state.sharedExploreHashtags,
            sharedExplorePostId: viewModel.state.sharedExplorePostId,
            shareRecommendation: viewModel.shareRecommendation,
            sharedExploreLocationSharing: viewModel.state.sharedExploreLocationSharing,
            fieldNotesArePublicOnExplore: viewModel.state.exploreFieldNotesArePublic,
            onViewInExplore: allowsExplorePresentation ? {
                viewModel.state.explorePresentationTarget = .post
                viewModel.state.showExploreSheet = true
            } : nil,
            onViewCommunityRequest: allowsExplorePresentation && viewModel.state.sharedCommunityIdentificationRequestId != nil ? {
                viewModel.state.explorePresentationTarget = .communityRequest
                viewModel.state.showExploreSheet = true
            } : nil
        )
    }

    private var canShowInsightChat: Bool {
        guard !viewModel.isProcessing,
              let speciesData = inferenceEngine.speciesData,
              speciesData.isBiological,
              !speciesData.isHumanSubject,
              let scanId = speciesData.scanId,
              !scanId.isEmpty,
              !chatViewModel.isUnavailable(for: scanId) else {
            return false
        }

        return true
    }
}
