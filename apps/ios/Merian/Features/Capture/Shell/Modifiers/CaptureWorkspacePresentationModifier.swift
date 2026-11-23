import SwiftData
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

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard, edges: viewModel.isFieldNotesOccupied ? [] : .bottom)
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
                        viewModel.saveStagedDescription(
                            at: selectedIndex,
                            text: newText,
                            pendingDraft: &observationContext
                        )
                        stagedDescriptionEditIndex = nil
                    },
                    onRemove: {
                        viewModel.removeStagedDescription(
                            at: selectedIndex,
                            pendingDraft: &observationContext
                        )
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
                viewModel: viewModel,
                onReviewSubmit: {
                        CaptureWorkspaceKeyboardService.dismissKeyboard()
                        var draft = viewModel.descriptionDraft
                        guard viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft) else { return }
                        await viewModel.submitStagedCapture(
                            modelContext: modelContext,
                            preferredGoal: preferredFieldTripGoal
                        )
                        cameraManager.resetZoom()
                },
                onDismiss: onFeaturePresentationDismissed
            ))
    }
}
