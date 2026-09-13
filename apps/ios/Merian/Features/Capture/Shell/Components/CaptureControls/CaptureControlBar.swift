import SwiftData
import SwiftUI

/// A horizontal control bar pinned to the bottom of the Capture workspace.
/// It orchestrates the primary capture action and the mode-specific secondary
/// controls while retaining view-owned task and lifecycle timing.
struct CaptureControlBar: View {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    let captureMode: CaptureMode
    @Binding var observationContext: ObservationContext
    let isSuppressed: Bool
    let coordinator: CaptureActionCoordinator

    @Environment(CameraManager.self) private var cameraManager
    @Environment(PhotoLibraryManager.self) private var photoLibraryManager
    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var audioRecordingStartTask: Task<Void, Never>?

    private var isRefining: Bool {
        viewModel.baseRefinementContext != nil
    }

    private var presentation: CaptureControlBarPresentation {
        let capacityLimit = viewModel.stagedCaptureLimit
        return CaptureControlBarPresentation(
            captureMode: captureMode,
            totalStagedItems: viewModel.stagedCapture.totalItemCount,
            availableStagedSlots: viewModel.availableStagedCaptureSlots,
            capacityLimit: capacityLimit,
            hasStagedVisualMedia: viewModel.stagedCapture.hasVisualMedia,
            hasStagedAudio: !viewModel.stagedCapture.audios.isEmpty,
            hasStagedDescription:
                !viewModel.stagedCapture.observationContexts.isEmpty,
            isRefining: isRefining,
            isMultiCaptureEnabled: viewModel.isMultiCaptureFunctionallyEnabled,
            requiresScanConfirmation: appSettings.requiresScanConfirmation,
            isVideoRecording: viewModel.isVideoRecording,
            isAudioRecording: audioCaptureManager.isRecording,
            hasPendingAudio: audioCaptureManager.pendingPlaybackPath != nil,
            isCheckingScanAdmission: viewModel.isCheckingScanAdmission,
            isStagingRefinement: viewModel.isStagingRefinement,
            isDescriptionEmpty: observationContext.isEmpty,
            canStageRefinementDescription: viewModel.stagedCapture.canStageRefinementDescription
        )
    }

    private func primaryActionPresentation(
        for presentation: CaptureControlBarPresentation
    ) -> CapturePrimaryActionPresentation {
        CapturePrimaryActionPresentation(
            captureMode: captureMode,
            willStageOnly: presentation.willStageOnly,
            isInputActive: presentation.isInputActive,
            isVisualCaptureAllowed:
                viewModel.isCaptureControlVisualCaptureAllowed,
            isVideoRecording: viewModel.isVideoRecording,
            videoRecordingProgress: viewModel.videoRecordingProgress,
            audioState: CaptureButtonAudioState(
                isRecording: audioCaptureManager.isRecording,
                isPaused: audioCaptureManager.isPaused,
                hasPendingRecording:
                    audioCaptureManager.pendingPlaybackPath != nil
            ),
            audioRecordingProgress: audioCaptureManager.recordingProgress
        )
    }

    var body: some View {
        let presentation = presentation

        VStack {
            Spacer()

            HStack(alignment: .center) {
                leadingControls(presentation)
                Spacer()
                primaryAction(presentation)
                Spacer()
                trailingControls(presentation)
            }
            .padding(.bottom, CaptureControlBarLayout.bottomInset)
        }
        .onChange(of: captureMode) { _, newMode in
            if newMode != .audio {
                cancelPendingAudioTransition()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                cancelPendingAudioTransition()
            }
        }
        .onDisappear {
            cancelPendingAudioTransition()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
            .spring(response: 0.35, dampingFraction: 0.8),
            value: viewModel.stagedCapture.images.count
        )
        .animation(
            .spring(response: 0.35, dampingFraction: 0.8),
            value: viewModel.stagedCapture.videos.count
        )
        .opacity(isSuppressed ? 0 : 1)
        .allowsHitTesting(!isSuppressed)
    }

    private func leadingControls(
        _ presentation: CaptureControlBarPresentation
    ) -> some View {
        ZStack(alignment: .leading) {
            PhotoLibraryButton(
                selectedPhotoItems: $viewModel.selectedPhotoItems,
                latestThumbnail: photoLibraryManager.latestThumbnail,
                maxSelectionCount: presentation.photoSelectionCount,
                isAvailable: presentation.isPhotoLibraryAvailable,
                onRequestPickerPresentation: {
                    await viewModel.requestImageImportEntryAdmission(
                        prospectiveImageCount: presentation.photoSelectionCount
                    )
                }
            )
            .opacity(
                presentation.showsPhotoLibrary
                    ? (presentation.isAtCapacity ? 0.5 : 1)
                    : 0
            )
            .allowsHitTesting(presentation.isPhotoLibraryAvailable)

            CaptureVideoCancelButton(onTap: cancelVideoCapture)
                .opacity(presentation.showsVideoCancel ? 1 : 0)
                .allowsHitTesting(presentation.showsVideoCancel)

            CapturePromptListButton(onTap: showPromptList)
                .opacity(presentation.showsPromptList ? 1 : 0)
                .allowsHitTesting(presentation.showsPromptList)

            CaptureAudioDeleteButton(
                isRecording: audioCaptureManager.isRecording,
                onTap: deleteAudioRecording
            )
            .opacity(presentation.showsAudioDelete ? 1 : 0)
            .allowsHitTesting(presentation.showsAudioDelete)
        }
        .animation(.easeInOut(duration: 0.2), value: captureMode)
        .animation(
            .easeInOut(duration: 0.2),
            value: viewModel.isVideoRecording
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: audioCaptureManager.isRecording
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: audioCaptureManager.pendingPlaybackPath == nil
        )
    }

    private func primaryAction(
        _ presentation: CaptureControlBarPresentation
    ) -> some View {
        CapturePrimaryActionButton(
            presentation: primaryActionPresentation(for: presentation),
            isInteractionEnabled:
                !isSuppressed && !presentation.isPrimaryActionDisabled,
            onAction: handlePrimaryAction,
            onVisualLongPress: handleVisualLongPress,
            onHapticFeedback: viewModel.performCaptureControlHapticFeedback
        )
        .animation(.easeInOut(duration: 0.2), value: captureMode)
        .opacity(presentation.isPrimaryActionDisabled ? 0.5 : 1)
        .disabled(presentation.isPrimaryActionDisabled)
    }

    private func trailingControls(
        _ presentation: CaptureControlBarPresentation
    ) -> some View {
        ZStack {
            CaptureFlashButton(
                isFlashEnabled: cameraManager.isFlashEnabled,
                onToggleFlash: toggleFlash
            )
            .opacity(
                presentation.showsFlash
                    ? (presentation.isAtCapacity ? 0.5 : 1)
                    : 0
            )
            .allowsHitTesting(presentation.isFlashAvailable)

            CaptureDescribeDictationButton(
                isRecording: coordinator.isDictationRequested,
                audioLevel: speechManager.audioLevel,
                onTap: toggleDictation
            )
            .opacity(presentation.showsDictation ? 1 : 0)
            .allowsHitTesting(presentation.showsDictation)

            CaptureAudioDoneButton(onTap: finishAudioRecording)
                .opacity(presentation.showsAudioDone ? 1 : 0)
                .allowsHitTesting(presentation.showsAudioDone)

            CaptureAudioReviewPlayButton(
                isPlaying: audioCaptureManager.isPlaying,
                onTap: toggleAudioReviewPlayback
            )
            .opacity(presentation.showsAudioReview ? 1 : 0)
            .allowsHitTesting(presentation.showsAudioReview)
        }
        .animation(.easeInOut(duration: 0.2), value: captureMode)
        .animation(
            .easeInOut(duration: 0.2),
            value: audioCaptureManager.isRecording
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: audioCaptureManager.pendingPlaybackPath == nil
        )
    }

    private func handlePrimaryAction() {
        switch captureMode {
        case .visual:
            handleVisualAction()
        case .audio:
            handleAudioAction()
        case .describe:
            handleDescribeAction()
        }
    }

    private func handleVisualAction() {
        if viewModel.isVideoRecording {
            viewModel.performCaptureControlHapticFeedback(
                .mediumPulse(.videoStop)
            )
            viewModel.stopVideoCapture()
        } else {
            viewModel.executeCapture(emitHaptic: false)
        }
    }

    private func handleVisualLongPress() {
        if viewModel.isCaptureControlProVideoAvailable {
            viewModel.startVideoCapture()
        } else {
            viewModel.presentCaptureControlPaywall()
        }
    }

    private func handleAudioAction() {
        if audioCaptureManager.pendingPlaybackPath != nil {
            confirmPendingAudio()
        } else if audioCaptureManager.isRecording {
            if audioCaptureManager.isPaused {
                audioCaptureManager.resumeRecording()
            } else {
                audioCaptureManager.pauseRecording()
            }
        } else {
            startAudioRecording()
        }
    }

    private func confirmPendingAudio() {
        guard audioRecordingStartTask == nil else { return }
        audioRecordingStartTask = Task {
            defer { audioRecordingStartTask = nil }
            guard await requestAudioScanAdmission() else { return }
            audioCaptureManager.confirmAndSubmit()
        }
    }

    private func startAudioRecording() {
        guard audioRecordingStartTask == nil else { return }
        audioRecordingStartTask = Task {
            defer { audioRecordingStartTask = nil }
            do {
                guard await requestAudioScanAdmission() else { return }
                guard scenePhase == .active else { return }
                try await audioCaptureManager
                    .requestMicrophonePermissionForRecording()
                try Task.checkCancellation()

                await cameraManager.stopSessionAndWait()
                try Task.checkCancellation()
                guard scenePhase == .active else { return }
                try await audioCaptureManager.startRecording(
                    autoSubmitOnMaxDuration:
                        !appSettings.requiresScanConfirmation
                )
            } catch is CancellationError {
                // Expected when the user leaves audio mode during startup.
            } catch {
                await MainActor.run {
                    viewModel.offlineToastMessage = .error(
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func requestAudioScanAdmission() async -> Bool {
        guard viewModel.hasAvailableStagedCaptureSlot else { return false }
        let route = await viewModel.requestScanAdmission(
            flashFallbackEligible: viewModel.stagedCapture.isEmpty
                && viewModel.baseRefinementContext == nil
        )
        return route != nil && viewModel.hasAvailableStagedCaptureSlot
    }

    private func handleDescribeAction() {
        viewModel.dismissCaptureControlKeyboard()
        Task { @MainActor in
            let didSubmit = await viewModel.submitDescribe(
                observationContext: observationContext,
                modelContext: modelContext
            )
            if didSubmit {
                coordinator.isDictationRequested = false
                observationContext = ObservationContext()
            }
        }
    }

    private func cancelVideoCapture() {
        viewModel.performCaptureControlHapticFeedback(
            .mediumPulse(.videoCancel)
        )
        viewModel.cancelVideoCapture()
    }

    private func showPromptList() {
        viewModel.performCaptureControlHapticFeedback(
            .mediumPulse(.describeTableOfContents)
        )
        coordinator.tocRequestID = UUID()
    }

    private func deleteAudioRecording() {
        viewModel.performCaptureControlHapticFeedback(
            .mediumPulse(.audioCancel)
        )
        if audioCaptureManager.isRecording {
            audioCaptureManager.cancelRecording()
        } else {
            audioCaptureManager.discardPending()
        }
    }

    private func toggleFlash() {
        viewModel.triggerMediumFeedback()
        cameraManager.toggleFlash()
    }

    private func toggleDictation() {
        viewModel.performCaptureControlHapticFeedback(
            .mediumPulse(.describeDictation)
        )
        coordinator.isDictationRequested.toggle()
    }

    private func finishAudioRecording() {
        viewModel.performCaptureControlHapticFeedback(.focusSnap(.audioDone))
        audioCaptureManager.stopRecordingEarly()
    }

    private func toggleAudioReviewPlayback() {
        if audioCaptureManager.isPlaying {
            viewModel.performCaptureControlHapticFeedback(
                .lightImpact(.audioReviewPause, intensity: 0.55)
            )
            audioCaptureManager.stopPlayback()
        } else {
            viewModel.performCaptureControlHapticFeedback(
                .mediumPulse(.audioReviewPlay)
            )
            audioCaptureManager.playPendingRecording()
        }
    }

    private func cancelPendingAudioTransition() {
        audioRecordingStartTask?.cancel()
        audioCaptureManager.cancelPendingRecordingTransition()
    }
}
