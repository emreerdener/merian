import SwiftUI

struct CaptureWorkspacePresentationModifier: ViewModifier {
    @Environment(CameraManager.self) private var cameraManager
    @Environment(\.modelContext) private var modelContext

    let viewModel: CaptureWorkspaceViewModel
    let messageShareCacheRecords: [LocalScanRecord]
    let defaultGeoprivacy: String
    let canStartProScan: Bool
    let messageShareCacheSignature: String
    let feedbackPromptSignature: String
    @Binding var observationContext: ObservationContext
    let describePromptViewModel: DescribePromptViewModel
    @Binding var isDescribeQuestionsSheetPresented: Bool
    @Binding var stagedDescriptionEditIndex: Int?
    @Binding var stagedAudioReviewIndex: Int?
    @Binding var stagedVideoReviewIndex: Int?
    @Binding var showFeedbackSurvey: Bool
    let preferredFieldTripGoal: FieldTripPreferredGoal?
    let onArmFeedbackSurveyPrompt: () -> Void
    let onFeedbackSurveyDismissal: () -> Void
    let onFeaturePresentationDismissed: () -> Void
    let onRootPresentationDismissed: () -> Void

    private var isStagedDescriptionSheetPresented: Binding<Bool> {
        CaptureWorkspacePresentationBindings.isPresented(
            by: $stagedDescriptionEditIndex
        )
    }

    private var offlineToastMessageBinding: Binding<ToastPayload?> {
        CaptureWorkspacePresentationBindings.offlineToast(for: viewModel)
    }

    private var isStagedVideoReviewPresented: Binding<Bool> {
        CaptureWorkspacePresentationBindings.isPresented(
            by: $stagedVideoReviewIndex
        )
    }

    private var isStagedAudioReviewPresented: Binding<Bool> {
        CaptureWorkspacePresentationBindings.isPresented(
            by: $stagedAudioReviewIndex
        )
    }

    private var isCropSheetPresented: Binding<Bool> {
        CaptureWorkspacePresentationBindings.isPresented(
            by: Binding(
                get: { viewModel.imageToCrop },
                set: { viewModel.imageToCrop = $0 }
            )
        )
    }

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .merianSystemFeedback(
                toast: offlineToastMessageBinding,
                toastAlignment: .top
            )
            .environment(\.composingCenter, viewModel.composingZoneVerticalCenter)
            .modifier(ExternalImageImportRetryModifier(
                viewModel: viewModel,
                stagedItemCount: viewModel.stagedCapture.totalItemCount,
                stagedCaptureLimit: viewModel.stagedCaptureLimit,
                canStartProScan: canStartProScan
            ))
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .task(id: messageShareCacheSignature) {
                await MessageScanShareCacheWriter.refresh(
                    records: messageShareCacheRecords,
                    defaultGeoprivacy: defaultGeoprivacy
                )
            }
            .task(id: feedbackPromptSignature) {
                onArmFeedbackSurveyPrompt()
            }
            .sheet(
                isPresented: isStagedDescriptionSheetPresented,
                onDismiss: onFeaturePresentationDismissed
            ) {
                let selectedIndex = stagedDescriptionEditIndex ?? 0
                StagedDescriptionSheet(
                    initialText: viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex)
                        ? viewModel.stagedCapture.observationContexts[selectedIndex].context.freeText
                        : "",
                    onSave: { newText in
                        guard viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex) else { return }
                        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            viewModel.stagedCapture.observationContexts.remove(at: selectedIndex)
                        } else {
                            var updatedContext = viewModel.stagedCapture.observationContexts[selectedIndex].context
                            updatedContext.freeText = trimmed
                            let addedAt = viewModel.stagedCapture.observationContexts[selectedIndex].addedAt
                            viewModel.stagedCapture.observationContexts[selectedIndex] = StagedObservationContext(
                                context: updatedContext,
                                addedAt: addedAt
                            )
                            stagedDescriptionEditIndex = nil
                        }
                    },
                    onRemove: {
                        guard viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex) else { return }
                        viewModel.stagedCapture.observationContexts.remove(at: selectedIndex)
                        stagedDescriptionEditIndex = nil
                    }
                )
            }
            .sheet(
                isPresented: $isDescribeQuestionsSheetPresented,
                onDismiss: onFeaturePresentationDismissed
            ) {
                DescribeQuestionsSheet(
                    promptViewModel: describePromptViewModel,
                    hasInputs: !observationContext.freeText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty,
                    onReset: {
                        viewModel.triggerMediumFeedback()
                        observationContext.freeText = ""
                        describePromptViewModel.resetFunnel()
                        describePromptViewModel.activeQuestionIndex = 0
                        viewModel.offlineToastMessage = .information("Draft discarded")
                    }
                )
            }
            .fullScreenCover(
                isPresented: isStagedAudioReviewPresented,
                onDismiss: onFeaturePresentationDismissed
            ) {
                if let selectedIndex = stagedAudioReviewIndex,
                   viewModel.stagedCapture.audios.indices.contains(selectedIndex) {
                    StagedAudioPreviewModal(
                        audio: viewModel.stagedCapture.audios[selectedIndex],
                        onRemove: {
                            viewModel.removeStagedAudio(at: selectedIndex)
                            stagedAudioReviewIndex = nil
                        }
                    )
                }
            }
            .fullScreenCover(
                isPresented: isStagedVideoReviewPresented,
                onDismiss: onFeaturePresentationDismissed
            ) {
                if let selectedIndex = stagedVideoReviewIndex,
                   viewModel.stagedCapture.videos.indices.contains(selectedIndex) {
                    StagedVideoPreviewModal(
                        video: viewModel.stagedCapture.videos[selectedIndex],
                        onRemove: {
                            viewModel.removeStagedVideo(at: selectedIndex)
                            stagedVideoReviewIndex = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showFeedbackSurvey, onDismiss: {
                onFeedbackSurveyDismissal()
                onFeaturePresentationDismissed()
            }) {
                FeedbackSurveyView()
            }

            // MARK: - View Modifiers
            .cameraSheetRouter(viewModel: viewModel) {
                onRootPresentationDismissed()
            }
            .modifier(CropSheetModifier(
                isPresented: isCropSheetPresented,
                viewModel: viewModel,
                onRequiredCropReadyForSubmit: {
                    Task { @MainActor in
                        await viewModel.submitStagedCapture(
                            modelContext: modelContext,
                            preferredGoal: preferredFieldTripGoal
                        )
                        cameraManager.resetZoom()
                    }
                },
                onDismiss: onFeaturePresentationDismissed
            ))
    }
}
