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
        autoSubmitScans: Bool,
        isVideoRecording: Bool,
        isAudioRecording: Bool,
        hasPendingAudio: Bool,
        isCheckingScanAdmission: Bool,
        isStagingRefinement: Bool,
        isDescriptionEmpty: Bool,
        canStageRefinementDescription: Bool = true,
        isCapturing: Bool = false,
        isPreparingVideo: Bool = false,
        isDraftReadyForSubmission: Bool = true
    ) {
        let isAtCapacity = isRefining
            ? (captureMode == .describe ? !canStageRefinementDescription : availableStagedSlots == 0)
            : (captureMode != .describe && availableStagedSlots == 0)

        self.isAtCapacity = isAtCapacity
        photoSelectionCount = capacityLimit > 1
            ? max(1, availableStagedSlots)
            : 1
        showsPhotoLibrary = captureMode == .visual && !isVideoRecording && !isPreparingVideo
        isPhotoLibraryAvailable = captureMode == .visual
            && !isAtCapacity
            && !isCapturing
            && !isVideoRecording
        showsVideoCancel = captureMode == .visual && (isVideoRecording || isPreparingVideo)
        showsPromptList = captureMode == .describe && !isRefining
        showsAudioDelete = captureMode == .audio
            && (isAudioRecording || hasPendingAudio)
        showsFlash = captureMode == .visual
        isFlashAvailable = captureMode == .visual && !isAtCapacity && !isCapturing
        showsDictation = captureMode == .describe
        showsAudioDone = captureMode == .audio && isAudioRecording
        showsAudioReview = captureMode == .audio && hasPendingAudio
        willStageOnly = hasPendingAudio
            || hasStagedVisualMedia
            || hasStagedAudio
            || hasStagedDescription
            || isRefining
            || !autoSubmitScans
        isPrimaryActionDisabled = isAtCapacity
            || isCheckingScanAdmission
            || (captureMode == .visual && isCapturing && !isVideoRecording)
            || (captureMode == .describe && (isStagingRefinement || isDescriptionEmpty
                || (!willStageOnly && !isDraftReadyForSubmission)))
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
    var isCapturing: Bool = false

    var showsProcessingProgress: Bool {
        captureMode == .visual && isCapturing && !isVideoRecording
    }

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
