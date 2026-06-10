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
            isIdentificationFlagPresented: $viewModel.state.isIdentificationFlagPresented,
            isSavingPhotos: $viewModel.state.isSavingPhotos,
            showDeleteConfirmation: $viewModel.state.showDeleteConfirmation,
            hasUserPhotos: viewModel.hasUserPhotos,
            leadingControl: presentationStyle.isEmbedded ? .back : .close,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            hasFieldNotes: viewModel.hasFieldNotes,
            onFieldNotes: {
                viewModel.state.isFieldNotesSheetPresented = true
            },
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
                viewModel.state.isCandidateSwipePresented = true
            } : nil,
            onConfirmIdentification: viewModel.canConfirm ? {
                HapticManager.shared.triggerSuccessPulse()
                Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
            } : nil,
            isAlreadyFlagged: viewModel.isAlreadyFlagged,
            isAnalyzing: viewModel.isProcessing
        )

        InsightBottomToolbar(
            showBottomBarTools: viewModel.state.showBottomBarTools && !viewModel.isProcessing,
            collections: collections,
            recordSnapshot: viewModel.toolbarRecordSnapshot,
            toggleScanInCollection: { collection in
                viewModel.toggleScanInCollection(collection, modelContext: modelContext)
            },
            showNewCollectionAlert: $viewModel.state.showNewCollectionAlert,
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
            isSharingToExplore: viewModel.state.isSharingToExplore,
            isUpdatingExplorePostContent: viewModel.state.isUpdatingExplorePostContent,
            isUpdatingExploreFieldNotes: viewModel.state.isUpdatingExploreFieldNotes,
            fieldNotesPreview: viewModel.shareableFieldNotes,
            sharedExploreHashtags: viewModel.state.sharedExploreHashtags,
            sharedExplorePostId: viewModel.state.sharedExplorePostId,
            fieldNotesArePublicOnExplore: viewModel.state.exploreFieldNotesArePublic,
            onViewInExplore: allowsExplorePresentation ? {
                viewModel.state.showExploreSheet = true
            } : nil,
            onUpdateFieldNotesVisibility: { isPublic in
                await viewModel.updateExploreFieldNotesVisibility(
                    isPublic: isPublic,
                    modelContext: modelContext
                )
            }
        )
    }
}
