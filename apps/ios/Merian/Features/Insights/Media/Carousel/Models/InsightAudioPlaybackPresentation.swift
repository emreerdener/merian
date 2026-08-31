import Foundation

struct InsightAudioPlaybackPresentation {
    let displayedProgress: Double
    let isControlPresented: Bool
    let isControlDisabled: Bool
    let monitorID: Int
    let pageAccessibilityIdentifier: String
    let controlAccessibilityIdentifier: String
    let accessibilityValue: String
    let boostPillState: InsightAudioBoostPillState?
    let elapsedText: String?
    let durationText: String?

    init(
        filePath: String,
        storedProgress: Double,
        currentTime: TimeInterval,
        duration: TimeInterval,
        hasPlayer: Bool,
        isPlaying: Bool,
        playerIsPlaying: Bool,
        playerGeneration: Int,
        isSeeking: Bool,
        isControlVisible: Bool,
        isHardwareDisabled: Bool,
        isPreparingBoost: Bool,
        isRevertingBoost: Bool,
        isBoostEnabled: Bool,
        isBoostedAudioReady: Bool,
        boostPreparationFailed: Bool,
        hasBoostToggleAction: Bool
    ) {
        displayedProgress = AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: storedProgress,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            playerIsPlaying: playerIsPlaying,
            isSeeking: isSeeking
        )
        isControlPresented = InsightAudioPlaybackControlPolicy.shouldPresent(
            isVisible: isControlVisible,
            isSeeking: isSeeking
        )
        isControlDisabled = InsightAudioPlaybackControlPolicy.shouldDisable(
            isHardwareDisabled: isHardwareDisabled,
            isPreparingSource: isPreparingBoost || isRevertingBoost,
            isPlaying: isPlaying
        )
        monitorID = isPlaying ? playerGeneration : -1

        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        pageAccessibilityIdentifier = "AudioPlaybackCarouselPage_\(fileName)"
        controlAccessibilityIdentifier = "AudioPlaybackControl_\(fileName)"
        accessibilityValue = duration > 0
            ? "\(Self.format(currentTime)) of \(Self.format(duration))"
            : "Unavailable"
        boostPillState = InsightAudioBoostPillState.resolve(
            isBoostEnabled: isBoostEnabled,
            isPreparingBoost: isPreparingBoost,
            isRevertingBoost: isRevertingBoost,
            isBoostedAudioReady:
                isBoostedAudioReady && !boostPreparationFailed,
            hasToggleAction: hasBoostToggleAction
        )
        let shouldPresentTimeBadge = hasPlayer && duration > 0
        elapsedText = shouldPresentTimeBadge ? Self.format(currentTime) : nil
        durationText = shouldPresentTimeBadge ? Self.format(duration) : nil
    }

    private static func format(_ seconds: TimeInterval) -> String {
        InsightAudioPlaybackTimeFormatter.string(from: seconds)
    }
}
