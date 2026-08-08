import SwiftData
import SwiftUI

extension InsightSheetView {
    @ToolbarContentBuilder
    var sheetToolbar: some ToolbarContent {
        // Toolbar callbacks can outlive the render that created them. Capture
        // the immutable subject and its monotonic presentation generation now;
        // never resolve "the current scan" later inside an old callback.
        let toolbarGeneration = viewModel.scanBoundActionGeneration
        let toolbarQueuedScanId = viewModel.queuedContext?.id
        let toolbarLocalScanId = viewModel.presentedLocalRecordScanId
        let toolbarScanId = toolbarQueuedScanId ?? toolbarLocalScanId
        let toolbarFieldChatScanId = fieldChatScanId
        let toolbarRecordSnapshot = presentedRecordSnapshot
        let toolbarSharedExplorePostId = presentedSharedExplorePostId
        let toolbarCommunityRequestId = presentedCommunityRequestId
        let toolbarDeleteBinding = deleteConfirmationRequestBinding(
            expectedScanId: toolbarScanId,
            expectedGeneration: toolbarGeneration
        )
        let toolbarNewCollectionBinding = newCollectionRequestBinding(
            expectedScanId: toolbarLocalScanId,
            expectedGeneration: toolbarGeneration
        )

        // Queued scan path: the standard ellipsis menu is suppressed (isAnalyzing == true),
        // so surface a dedicated trash button for the only available destructive action.
        if toolbarQueuedScanId != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    toolbarDeleteBinding.wrappedValue = true
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
            isSavingMedia: $viewModel.state.isSavingMedia,
            showDeleteConfirmation: toolbarDeleteBinding,
            hasUserMedia: viewModel.hasUserMedia,
            leadingControl: presentationStyle.isEmbedded ? .back : .close,
            onSaveMedia: {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.saveUserMedia(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration,
                    inferenceEngine: inferenceEngine
                )
            },
            allowsFieldNotes: viewModel.contentMode != .nonBiological &&
                toolbarRecordSnapshot != nil,
            hasFieldNotes: toolbarRecordSnapshot != nil && viewModel.hasFieldNotes,
            onFieldNotes: {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentFieldNotes(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            },
            allowsCollectionActions: viewModel.contentMode != .nonBiological &&
                toolbarRecordSnapshot != nil,
            collections: collections,
            selectedCollectionIds: toolbarRecordSnapshot?.collectionIds ?? [],
            toggleScanInCollection: { collection in
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.toggleScanInCollection(
                    collection,
                    modelContext: modelContext,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            },
            showNewCollectionAlert: toolbarNewCollectionBinding,
            hasCollectionScanId: toolbarRecordSnapshot != nil,
            onReanalyze: viewModel.canReanalyze ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                if RevenueCatManager.shared.isProActive {
                    if let record = viewModel.activeLocalRecord,
                       record.id.caseInsensitiveCompare(scanId) == .orderedSame {
                        HapticManager.shared.triggerSelectionPulse()
                        AppDIContainer.shared.appRouteCoordinator.request(
                            .refinement(
                                scanId: record.id,
                                initialDescription: viewModel.shareableFieldNotes,
                                entryPoint: .standard
                            ),
                            source: .internalUserAction
                        )
                    }
                } else {
                    viewModel.state.showPaywall = true
                }
            } : nil,
            onReviewAlternatives: viewModel.canReviewAlternatives ? {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentCandidateSwipe(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            onConfirmIdentification: viewModel.canConfirm ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                HapticManager.shared.triggerSuccessPulse()
                Task { @MainActor in
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: toolbarGeneration
                    ) else {
                        return
                    }
                    await inferenceEngine.confirmAIIdentification(
                        expectedScanId: scanId,
                        modelContext: modelContext
                    )
                }
            } : nil,
            onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentCommunityIdentificationRequest(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            sharedExplorePostId: toolbarSharedExplorePostId,
            sharedCommunityIdentificationRequestId: toolbarCommunityRequestId,
            onEditExplorePost: toolbarSharedExplorePostId != nil ? {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentExplorePostComposer(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            onViewExplorePost: allowsExplorePresentation &&
                toolbarSharedExplorePostId != nil ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                viewModel.presentExplore(
                    target: .post,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            onViewCommunityRequest: allowsExplorePresentation &&
                toolbarCommunityRequestId != nil ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                viewModel.presentExplore(
                    target: .communityRequest,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            audioBoostEnabled: toolbarLocalScanId.flatMap { scanId in
                guard viewModel.audioBoostEligibleScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame else {
                    return nil
                }
                return viewModel.audioBoostBinding(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            },
            onAudioBoostEnableRequested: {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ),
                      viewModel.audioBoostEligibleScanId?
                        .caseInsensitiveCompare(scanId) == .orderedSame else {
                    return
                }
                viewModel.state.audioBoostActionToken = UUID()
            },
            isAnalyzing: viewModel.isProcessing,
            isProActive: RevenueCatManager.shared.isProActive
        )

        InsightBottomToolbar(
            showBottomBarTools: viewModel.state.showBottomBarTools && !viewModel.isProcessing,
            recordSnapshot: toolbarRecordSnapshot,
            scanId: toolbarLocalScanId ?? toolbarFieldChatScanId,
            scanPresentationGeneration: toolbarGeneration,
            canShowInsightChat: toolbarFieldChatScanId != nil &&
                !chatViewModel.isUnavailable(for: toolbarFieldChatScanId ?? ""),
            onInsightChat: {
                guard let scanId = toolbarFieldChatScanId,
                      toolbarGeneration == viewModel.scanBoundActionGeneration,
                      fieldChatScanId?
                        .caseInsensitiveCompare(scanId) == .orderedSame else {
                    return
                }
                if RevenueCatManager.shared.isProActive {
                    Task { @MainActor in
                        guard toolbarGeneration == viewModel.scanBoundActionGeneration,
                              fieldChatScanId?
                                .caseInsensitiveCompare(scanId) == .orderedSame else {
                            return
                        }
                        if let record = viewModel.activeLocalRecord {
                            guard record.id.caseInsensitiveCompare(scanId) == .orderedSame else {
                                presentFieldChatUnavailableToast(
                                    InsightChatViewModel.stillSyncingMessage,
                                    expectedScanId: scanId,
                                    expectedGeneration: toolbarGeneration
                                )
                                return
                            }
                            do {
                                let isAvailable = try await MerianNetworkClient.shared
                                    .ensureCloudScanAvailableForFieldChat(
                                        scan: record,
                                        expectedScanId: scanId
                                )
                                guard toolbarGeneration == viewModel.scanBoundActionGeneration else {
                                    return
                                }
                                guard isAvailable else {
                                    presentFieldChatUnavailableToast(
                                        InsightChatViewModel.stillSyncingMessage,
                                        expectedScanId: scanId,
                                        expectedGeneration: toolbarGeneration
                                    )
                                    return
                                }
                                chatViewModel.markAvailable(scanId: scanId)
                            } catch {
                                guard toolbarGeneration == viewModel.scanBoundActionGeneration,
                                      fieldChatScanId?
                                        .caseInsensitiveCompare(scanId) == .orderedSame else {
                                    return
                                }
                                presentFieldChatUnavailableToast(
                                    "Field chat is temporarily unavailable. Please try again.",
                                    expectedScanId: scanId,
                                    expectedGeneration: toolbarGeneration
                                )
                                return
                            }
                        }
                        guard toolbarGeneration == viewModel.scanBoundActionGeneration,
                              fieldChatScanId?
                                .caseInsensitiveCompare(scanId) == .orderedSame else {
                            return
                        }
                        let canPresent = await chatViewModel.prepareForPresentation(scanId: scanId)
                        guard toolbarGeneration == viewModel.scanBoundActionGeneration,
                              fieldChatScanId?
                                .caseInsensitiveCompare(scanId) == .orderedSame else {
                            return
                        }
                        if canPresent {
                            selectedInsightChatScanId = scanId
                            selectedInsightChatGeneration = toolbarGeneration
                            HapticManager.shared.triggerSheetSpring()
                            viewModel.state.isInsightChatSheetPresented = true
                        } else {
                            presentFieldChatUnavailableToast(
                                chatViewModel.errorMessage
                                    ?? "Field chat isn't available for this scan.",
                                expectedScanId: scanId,
                                expectedGeneration: toolbarGeneration
                            )
                        }
                    }
                } else {
                    HapticManager.shared.triggerSelectionPulse()
                    viewModel.state.showPaywall = true
                }
            },
            shareExternally: {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.shareDiscovery(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration,
                    inferenceEngine: inferenceEngine
                )
            },
            onShareToExplore: viewModel.canShareToExplore ? { draft in
                guard let scanId = toolbarLocalScanId else {
                    return false
                }
                return await viewModel.shareToExplore(
                    draft,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration,
                    modelContext: modelContext
                )
            } : nil,
            onEditExplorePost: toolbarSharedExplorePostId != nil ? { draft in
                guard let scanId = toolbarLocalScanId else { return }
                Task {
                    await viewModel.updateExplorePostContent(
                        draft,
                        expectedScanId: scanId,
                        expectedGeneration: toolbarGeneration,
                        modelContext: modelContext
                    )
                }
            } : nil,
            onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentCommunityIdentificationRequest(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            onEditCommunityRequest: toolbarCommunityRequestId != nil ? {
                guard let scanId = toolbarLocalScanId else { return }
                viewModel.presentCommunityIdentificationRequest(
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            isSharingToExplore: viewModel.state.isSharingToExplore,
            isUpdatingExplorePostContent: viewModel.state.isUpdatingExplorePostContent,
            displaySpeciesName: viewModel.resolvedHeaderTitle,
            commonNameOptions: viewModel.allNamesForPicker,
            fieldNotesPreview: viewModel.shareableFieldNotes,
            sharedExploreHashtags: toolbarRecordSnapshot == nil
                ? []
                : viewModel.state.sharedExploreHashtags,
            sharedExplorePostId: toolbarSharedExplorePostId,
            shareRecommendation: viewModel.shareRecommendation,
            sharedExploreLocationSharing: toolbarRecordSnapshot == nil
                ? nil
                : viewModel.state.sharedExploreLocationSharing,
            fieldNotesArePublicOnExplore: toolbarRecordSnapshot != nil &&
                viewModel.state.exploreFieldNotesArePublic,
            onViewInExplore: allowsExplorePresentation &&
                toolbarSharedExplorePostId != nil ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                viewModel.presentExplore(
                    target: .post,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil,
            onViewCommunityRequest: allowsExplorePresentation &&
                toolbarCommunityRequestId != nil ? {
                guard let scanId = toolbarLocalScanId,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: toolbarGeneration
                      ) else {
                    return
                }
                viewModel.presentExplore(
                    target: .communityRequest,
                    expectedScanId: scanId,
                    expectedGeneration: toolbarGeneration
                )
            } : nil
        )
    }

    private var presentedRecordSnapshot: InsightToolbarRecordSnapshot? {
        guard viewModel.presentedLocalRecordScanId != nil else { return nil }
        return viewModel.toolbarRecordSnapshot
    }

    private var presentedSharedExplorePostId: String? {
        guard presentedRecordSnapshot != nil else { return nil }
        return viewModel.state.sharedExplorePostId
    }

    private var presentedCommunityRequestId: String? {
        guard presentedRecordSnapshot != nil else { return nil }
        return viewModel.state.sharedCommunityIdentificationRequestId
    }

    private var fieldChatScanId: String? {
        guard !viewModel.isProcessing,
              let scanId = viewModel.presentedSpeciesScanId,
              let speciesData = inferenceEngine.speciesData,
              speciesData.isBiological,
              !speciesData.isHumanSubject,
              speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame,
              presentedScanId == nil ||
                presentedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return nil
        }

        return scanId
    }

    private func deleteConfirmationRequestBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let expectedScanId,
                      self.viewModel.state.showDeleteConfirmation,
                      self.pendingDeletionScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      self.pendingDeletionGeneration == expectedGeneration else {
                    return false
                }
                return self.viewModel.isPresentingScan(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { shouldPresent in
                guard shouldPresent else {
                    guard let expectedScanId,
                          self.pendingDeletionScanId?
                            .caseInsensitiveCompare(expectedScanId) ==
                            .orderedSame,
                          self.pendingDeletionGeneration ==
                            expectedGeneration else {
                        return
                    }
                    self.viewModel.state.showDeleteConfirmation = false
                    return
                }
                guard let expectedScanId,
                      self.viewModel.isPresentingScan(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                self.pendingDeletionScanId = expectedScanId
                self.pendingDeletionGeneration = expectedGeneration
                self.viewModel.state.showDeleteConfirmation = true
            }
        )
    }

    private func newCollectionRequestBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let expectedScanId,
                      self.viewModel.state.showNewCollectionAlert,
                      self.pendingNewCollectionScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      self.pendingNewCollectionGeneration == expectedGeneration else {
                    return false
                }
                return self.viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { shouldPresent in
                guard shouldPresent else {
                    guard let expectedScanId,
                          self.pendingNewCollectionScanId?
                            .caseInsensitiveCompare(expectedScanId) ==
                            .orderedSame,
                          self.pendingNewCollectionGeneration ==
                            expectedGeneration else {
                        return
                    }
                    self.viewModel.state.showNewCollectionAlert = false
                    return
                }
                guard let expectedScanId,
                      self.viewModel.isPresentingLocalRecord(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                self.pendingNewCollectionScanId = expectedScanId
                self.pendingNewCollectionGeneration = expectedGeneration
                self.viewModel.state.showNewCollectionAlert = true
            }
        )
    }

    @MainActor
    private func presentFieldChatUnavailableToast(
        _ message: String,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard expectedGeneration == viewModel.scanBoundActionGeneration,
              fieldChatScanId?
                .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return
        }
        HapticManager.shared.triggerErrorThump()
        viewModel.state.toastMessage = .error(message)
    }
}
