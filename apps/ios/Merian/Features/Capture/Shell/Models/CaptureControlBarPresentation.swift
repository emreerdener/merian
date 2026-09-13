struct CaptureControlBarPresentation: Equatable {
    let isAtCapacity: Bool
    let photoSelectionCount: Int
    let showsPhotoLibrary: Bool
    let isPhotoLibraryAvailable: Bool
    let showsVideoCancel: Bool
    let showsPromptList: Bool
    let showsAudioDelete: Bool
    let showsFlash: Bool
    let isFlashAvailable: Bool
    let showsDictation: Bool
    let showsAudioDone: Bool
    let showsAudioReview: Bool
    let willStageOnly: Bool
    let isPrimaryActionDisabled: Bool
    let isInputActive: Bool

    init(
        captureMode: CaptureMode,
        totalStagedItems: Int,
        availableStagedSlots: Int,
        capacityLimit: Int,
        hasStagedVisualMedia: Bool,
        hasStagedAudio: Bool,
        hasStagedDescription: Bool,
        isRefining: Bool,
        isMultiCaptureEnabled: Bool,
        requiresScanConfirmation: Bool,
        isVideoRecording: Bool,
        isAudioRecording: Bool,
        hasPendingAudio: Bool,
        isCheckingScanAdmission: Bool,
        isStagingRefinement: Bool,
        isDescriptionEmpty: Bool,
        canStageRefinementDescription: Bool = true
    ) {
        let isAtCapacity = isRefining
            ? (captureMode == .describe ? !canStageRefinementDescription : availableStagedSlots == 0)
            : totalStagedItems >= capacityLimit

        self.isAtCapacity = isAtCapacity
        photoSelectionCount = capacityLimit > 1
            ? max(1, availableStagedSlots)
            : 1
        showsPhotoLibrary = captureMode == .visual && !isVideoRecording
        isPhotoLibraryAvailable = captureMode == .visual
            && !isAtCapacity
            && !isVideoRecording
        showsVideoCancel = captureMode == .visual && isVideoRecording
        showsPromptList = captureMode == .describe && !isRefining
        showsAudioDelete = captureMode == .audio
            && (isAudioRecording || hasPendingAudio)
        showsFlash = captureMode == .visual
        isFlashAvailable = captureMode == .visual && !isAtCapacity
        showsDictation = captureMode == .describe
        showsAudioDone = captureMode == .audio && isAudioRecording
        showsAudioReview = captureMode == .audio && hasPendingAudio
        willStageOnly = hasStagedVisualMedia
            || hasStagedAudio
            || hasStagedDescription
            || isRefining
            || isMultiCaptureEnabled
            || requiresScanConfirmation
        isPrimaryActionDisabled = isAtCapacity
            || isCheckingScanAdmission
            || (captureMode == .describe && isStagingRefinement)
        isInputActive = captureMode != .describe || !isDescriptionEmpty
    }
}

struct CapturePrimaryActionPresentation: Equatable {
    let captureMode: CaptureMode
    let willStageOnly: Bool
    let isInputActive: Bool
    let isVisualCaptureAllowed: Bool
    let isVideoRecording: Bool
    let videoRecordingProgress: Double
    let audioState: CaptureButtonAudioState
    let audioRecordingProgress: Double

    var isAudioRecording: Bool {
        captureMode == .audio
            && (audioState == .recording || audioState == .paused)
    }

    var isAudioPaused: Bool {
        captureMode == .audio && audioState == .paused
    }

    var isAudioReview: Bool {
        captureMode == .audio && audioState == .review
    }

    var shouldShowRecordingChrome: Bool {
        isAudioRecording || (captureMode == .visual && isVideoRecording)
    }

    var recordingProgress: Double {
        captureMode == .visual && isVideoRecording
            ? videoRecordingProgress
            : audioRecordingProgress
    }

    var releaseHapticFeedback: CaptureButtonHapticFeedback {
        .releaseFeedback(
            captureMode: captureMode,
            isVideoRecording: isVideoRecording,
            isVisualCaptureAllowed: isVisualCaptureAllowed,
            audioState: audioState,
            isDescribeInputActive: isInputActive,
            willStageDescribeOnly: willStageOnly
        )
    }
}
