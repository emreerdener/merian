enum CaptureButtonAudioState: Equatable, Sendable {
    case idle
    case recording
    case paused
    case review

    init(isRecording: Bool, isPaused: Bool, hasPendingRecording: Bool) {
        if hasPendingRecording {
            self = .review
        } else if isRecording {
            self = isPaused ? .paused : .recording
        } else {
            self = .idle
        }
    }
}

enum CaptureButtonHapticSource: String, Equatable, Sendable {
    case visualPhoto = "capture.photo"
    case videoStart = "capture.video.start"
    case videoStop = "capture.video.stop"
    case videoCancel = "capture.video.cancel"
    case audioStart = "capture.audio.start"
    case audioPause = "capture.audio.pause"
    case audioResume = "capture.audio.resume"
    case audioConfirm = "capture.audio.confirm"
    case audioCancel = "capture.audio.cancel"
    case audioDone = "capture.audio.done"
    case audioReviewPlay = "media.capture.audio.play"
    case audioReviewPause = "media.capture.audio.pause"
    case describeAdd = "capture.describe.add"
    case describeSubmit = "capture.describe.submit"
    case describeDictation = "capture.describe.dictation"
    case describeTableOfContents = "capture.describe.tableOfContents"
}

enum CaptureButtonHapticFeedback: Equatable, Sendable {
    case none
    case prepareHeavyImpact
    case heavyImpact(CaptureButtonHapticSource)
    case mediumPulse(CaptureButtonHapticSource)
    case lightImpact(CaptureButtonHapticSource, intensity: Double)
    case focusSnap(CaptureButtonHapticSource)

    static func releaseFeedback(
        captureMode: CaptureMode,
        isVideoRecording: Bool,
        isVisualCaptureAllowed: Bool,
        audioState: CaptureButtonAudioState,
        isDescribeInputActive: Bool,
        willStageDescribeOnly: Bool
    ) -> CaptureButtonHapticFeedback {
        switch captureMode {
        case .visual:
            return !isVideoRecording && isVisualCaptureAllowed
                ? .heavyImpact(.visualPhoto)
                : .none
        case .audio:
            switch audioState {
            case .idle:
                return .mediumPulse(.audioStart)
            case .recording:
                return .mediumPulse(.audioPause)
            case .paused:
                return .mediumPulse(.audioResume)
            case .review:
                return .mediumPulse(.audioConfirm)
            }
        case .describe:
            guard isDescribeInputActive else { return .none }
            return .mediumPulse(
                willStageDescribeOnly ? .describeAdd : .describeSubmit
            )
        }
    }
}
