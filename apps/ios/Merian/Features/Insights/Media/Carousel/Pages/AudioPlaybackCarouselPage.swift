import AVFoundation
import SwiftUI
import UIKit

final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        onFinish()
    }
}

enum InsightAudioBoostPillState: Equatable {
    case boost
    case boosting
    case reverting
    case boosted

    static func resolve(
        isBoostEnabled: Bool,
        isPreparingBoost: Bool = false,
        isRevertingBoost: Bool = false,
        isBoostedAudioReady: Bool,
        hasToggleAction: Bool
    ) -> Self? {
        guard hasToggleAction else { return nil }
        if isBoostEnabled && isPreparingBoost { return .boosting }
        if !isBoostEnabled && isRevertingBoost { return .reverting }
        return isBoostEnabled && isBoostedAudioReady ? .boosted : .boost
    }

    var title: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting…"
        case .reverting: "Reverting…"
        case .boosted: "Boosted audio"
        }
    }

    var systemImage: String? {
        self == .boost ? "chevron.right" : nil
    }

    var accessibilityLabel: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting audio"
        case .reverting: "Reverting audio boost"
        case .boosted: "Turn off audio boost"
        }
    }
}

enum InsightAudioPlaybackControlPolicy {
    static let autoHideDelayNanoseconds: UInt64 = 1_000_000_000

    static func shouldAutoHide(isPlaying: Bool, isSeeking: Bool) -> Bool {
        isPlaying && !isSeeking
    }

    static func shouldPresent(isVisible: Bool, isSeeking: Bool) -> Bool {
        isVisible && !isSeeking
    }
}

struct AudioPlaybackCarouselPage: View {
    let filePath: String
    @Binding var isAudioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?
    
    @State private var player: AVAudioPlayer?
    @State private var playerDelegate = PlayerDelegate()
    @State private var columns: [SpectrogramColumn] = []
    @State private var playbackProgress: Double = 0.0
    @State private var isDecoding: Bool = true
    @State private var isPreparingAudioBoost = false
    @State private var isRevertingAudioBoost = false
    @State private var showsAudioBoostPreparationStatus = false
    @State private var audioBoostPreparationFailed = false
    @State private var isBoostedAudioReady = false
    @State private var hasTrackedBoostedPlaybackStart = false
    @State private var originalAudioLease: AudioSourceLease?
    @State private var isAudioSeeking = false
    @State private var audioSeekWasPlaying = false
    @State private var audioSeekStartProgress = 0.0
    @State private var showsPlaybackControl = true
    @State private var playbackControlFadeTask: Task<Void, Never>?
    
    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isPlaying: Bool = false
    private var isHardwareDisabled: Bool {
        speechManager.isRecording || audioCaptureManager.isRecording
    }

    private var isPlaybackControlPresented: Bool {
        InsightAudioPlaybackControlPolicy.shouldPresent(
            isVisible: showsPlaybackControl,
            isSeeking: isAudioSeeking
        )
    }
    
    // Captured session category across appearances
    @State private var previousSessionCategory: AVAudioSession.Category?
    @State private var previousSessionCategoryOptions: AVAudioSession.CategoryOptions?
    
    private var accessibilityIdentifier: String {
        "AudioPlaybackCarouselPage_\(URL(fileURLWithPath: filePath).lastPathComponent)"
    }

    init(
        filePath: String,
        isAudioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil
    ) {
        self.filePath = filePath
        self._isAudioBoostEnabled = isAudioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isDecoding {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
            } else if columns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.title)
                    Text("Audio Unavailable")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.6))
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        SpectrogramView(columns: columns, layout: .fitToData)
                            .equatable()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .allowsHitTesting(false)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture().onEnded { value in
                                    handleAudioSurfaceTap(
                                        to: AudioSpectrogramSeekingPolicy.normalizedProgress(
                                            locationX: value.location.x,
                                            width: proxy.size.width
                                        )
                                    )
                                }
                            )

                        if isPlaying || isAudioSeeking || playbackProgress > 0 {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 2)
                                .offset(x: AudioSpectrogramSeekingPolicy.playmarkerCenterX(
                                    progress: playbackProgress,
                                    width: proxy.size.width
                                ))
                                .allowsHitTesting(false)
                        }

                        Color.clear
                            .frame(
                                width: AudioSpectrogramSeekingPolicy.playmarkerHitWidth,
                                height: proxy.size.height
                            )
                            .contentShape(Rectangle())
                            .position(
                                x: min(
                                    proxy.size.width - AudioSpectrogramSeekingPolicy.playmarkerHitWidth / 2,
                                    max(
                                        AudioSpectrogramSeekingPolicy.playmarkerHitWidth / 2,
                                        AudioSpectrogramSeekingPolicy.playmarkerCenterX(
                                            progress: playbackProgress,
                                            width: proxy.size.width
                                        )
                                    )
                                ),
                                y: proxy.size.height / 2
                            )
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateAudioSeek(
                                            translationX: value.translation.width,
                                            width: proxy.size.width
                                        )
                                    }
                                    .onEnded { value in
                                        finishAudioSeek(
                                            translationX: value.translation.width,
                                            width: proxy.size.width
                                        )
                                    }
                            )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Audio position")
                    .accessibilityValue(accessibilityPlaybackValue)
                    .accessibilityAdjustableAction { direction in
                        let adjustment: AudioSeekAdjustment = direction == .increment ? .forward : .backward
                        seekAudioForAccessibility(adjustment)
                    }
                }

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(isHardwareDisabled)
                .opacity(isPlaybackControlPresented ? (isHardwareDisabled ? 0.3 : 1.0) : 0)
                .allowsHitTesting(isPlaybackControlPresented)
                .animation(.easeInOut(duration: 0.25), value: isPlaybackControlPresented)

                playbackBadges

                if isPreparingAudioBoost &&
                    showsAudioBoostPreparationStatus &&
                    onAudioBoostToggleRequested == nil {
                    Text("Boosting audio…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: Capsule())
                        .allowsHitTesting(false)
                }

                if audioBoostPreparationFailed {
                    Text("Audio boost unavailable. Playing original.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.68), in: Capsule())
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Audio playback page")
                .accessibilityIdentifier(accessibilityIdentifier)
                .allowsHitTesting(false)
        }
        .onAppear {
            captureAndSwitchSession()
        }
        .onDisappear {
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            player?.stop()
            isPlaying = false
            originalAudioLease?.release()
            originalAudioLease = nil
            restoreSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                showPlaybackControlPersistently()
                player?.stop()
                isPlaying = false
                playbackProgress = 0.0
                restoreSession()
            }
        }
        .task {
            await decodeAudio()
        }
        .task(id: isAudioBoostEnabled) {
            guard !isDecoding else { return }
            await updateAudioBoostMode()
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                guard let player, player.isPlaying, player.duration > 0 else { return }
                playbackProgress = player.currentTime / player.duration
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    @ViewBuilder
    private var playbackBadges: some View {
        VStack {
            Spacer()
            HStack(alignment: .center) {
                if let pillState = InsightAudioBoostPillState.resolve(
                    isBoostEnabled: isAudioBoostEnabled,
                    isPreparingBoost: isPreparingAudioBoost,
                    isRevertingBoost: isRevertingAudioBoost,
                    isBoostedAudioReady: isBoostedAudioReady && !audioBoostPreparationFailed,
                    hasToggleAction: onAudioBoostToggleRequested != nil
                ) {
                    Button {
                        onAudioBoostToggleRequested?()
                    } label: {
                        HStack(spacing: 4) {
                            Text(pillState.title)
                            if let systemImage = pillState.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .insightAudioBadgeStyle()
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(pillState == .boosting || pillState == .reverting)
                    .accessibilityLabel(pillState.accessibilityLabel)
                }

                Spacer()

                if let player, player.duration > 0 {
                    Text("\(Self.formattedTime(player.currentTime)) / \(Self.formattedTime(player.duration))")
                        .fontDesign(.monospaced)
                        .insightAudioBadgeStyle()
                        .allowsHitTesting(false)
                        .accessibilityLabel(
                            "\(Self.formattedTime(player.currentTime)) elapsed of \(Self.formattedTime(player.duration))"
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 40)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBoostedAudioReady)
    }

    static func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var accessibilityPlaybackValue: String {
        guard let player, player.duration > 0 else { return "Unavailable" }
        return "\(Self.formattedTime(player.currentTime)) of \(Self.formattedTime(player.duration))"
    }
    
    // MARK: - Handlers

    private func togglePlayback() {
        guard !isHardwareDisabled, let player = player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            showPlaybackControlPersistently()
            HapticManager.shared.triggerLightImpact(
                intensity: 0.55,
                source: "media.insight.audio.pause"
            )
        } else {
            // Guarantee audio session is hot before play
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            showPlaybackControlTemporarily()
            trackBoostedPlaybackStartedIfNeeded()
            HapticManager.shared.triggerMediumPulse(source: "media.insight.audio.play")
            } catch {
                HapticManager.shared.triggerErrorThump(source: "media.insight.audio.play.failed")
                MerianLog.general.debug("AudioPlaybackCarouselPage: session activation failed: \(error, privacy: .private)")
            }
        }
    }

    private func seekAudio(to progress: Double) {
        guard let player, player.duration > 0 else { return }
        let clampedProgress = min(1, max(0, progress))
        player.currentTime = AudioSpectrogramSeekingPolicy.seconds(
            progress: clampedProgress,
            duration: player.duration
        )
        playbackProgress = clampedProgress
    }

    private func seekAudioFromTap(to progress: Double) {
        guard player?.duration ?? 0 > 0 else { return }
        showPlaybackControlTemporarily()
        seekAudio(to: progress)
        HapticManager.shared.triggerSelectionPulse(source: "media.insight.audio.seek.tap")
    }

    private func handleAudioSurfaceTap(to progress: Double) {
        if showsPlaybackControl {
            seekAudioFromTap(to: progress)
        } else {
            showPlaybackControlTemporarily()
        }
    }

    private func updateAudioSeek(translationX: CGFloat, width: CGFloat) {
        guard let player, player.duration > 0, width > 0 else { return }
        if !isAudioSeeking {
            isAudioSeeking = true
            audioSeekWasPlaying = player.isPlaying
            audioSeekStartProgress = playbackProgress
            showPlaybackControlPersistently()
            HapticManager.shared.triggerLightImpact(
                intensity: 0.35,
                source: "media.insight.audio.seek.begin"
            )
            player.pause()
            isPlaying = false
        }
        seekAudio(to: audioSeekStartProgress + Double(translationX / width))
    }

    private func finishAudioSeek(translationX: CGFloat, width: CGFloat) {
        guard isAudioSeeking, let player else { return }
        seekAudio(to: audioSeekStartProgress + Double(translationX / width))
        let shouldResume = audioSeekWasPlaying
        isAudioSeeking = false
        audioSeekWasPlaying = false
        HapticManager.shared.triggerSelectionPulse(source: "media.insight.audio.seek.commit")
        if shouldResume {
            player.play()
            isPlaying = true
            showPlaybackControlTemporarily()
            trackBoostedPlaybackStartedIfNeeded()
        }
    }

    private func seekAudioForAccessibility(_ adjustment: AudioSeekAdjustment) {
        guard let player, player.duration > 0 else { return }
        let progress = AudioSpectrogramSeekingPolicy.progress(
            after: adjustment,
            currentProgress: playbackProgress,
            duration: player.duration
        )
        seekAudio(to: progress)
        HapticManager.shared.triggerSelectionPulse(source: "media.insight.audio.seek.accessibility")
        UIAccessibility.post(
            notification: .announcement,
            argument: Self.formattedTime(player.currentTime)
        )
    }

    private func showPlaybackControlTemporarily() {
        playbackControlFadeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            showsPlaybackControl = true
        }
        guard InsightAudioPlaybackControlPolicy.shouldAutoHide(
            isPlaying: isPlaying,
            isSeeking: isAudioSeeking
        ) else {
            playbackControlFadeTask = nil
            return
        }

        playbackControlFadeTask = Task {
            try? await Task.sleep(
                nanoseconds: InsightAudioPlaybackControlPolicy.autoHideDelayNanoseconds
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard InsightAudioPlaybackControlPolicy.shouldAutoHide(
                    isPlaying: isPlaying,
                    isSeeking: isAudioSeeking
                ) else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    showsPlaybackControl = false
                }
            }
        }
    }

    private func showPlaybackControlPersistently() {
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            showsPlaybackControl = true
        }
    }
    
    // MARK: - Hardware Lifecycle

    private func captureAndSwitchSession() {
        let session = AVAudioSession.sharedInstance()
        previousSessionCategory = session.category
        previousSessionCategoryOptions = session.categoryOptions
        
        do {
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
        } catch {
            MerianLog.general.debug("AudioPlaybackCarouselPage: setCategory failed: \(error, privacy: .private)")
        }
    }
    
    private func restoreSession() {
        guard let prev = previousSessionCategory else { return }
        let opts = previousSessionCategoryOptions ?? []
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(prev, options: opts)
        } catch {
            MerianLog.general.debug("AudioPlaybackCarouselPage: session restore failed: \(error, privacy: .private)")
        }
    }
    
    // MARK: - DSP Decoding Pipeline

    @MainActor
    private func decodeAudio() async {
        do {
            let lease = try await AudioBoostProcessor.shared.acquireSource(filePath)
            guard !Task.isCancelled else {
                lease.release()
                return
            }
            originalAudioLease = lease
            player = makePlayer(url: lease.url, resumeTime: 0, shouldPlay: false)
            columns = await AudioSpectrogramDecoder.decodeColumns(fromFilePath: lease.url.path)
        } catch {
            player = nil
            columns = []
        }
        isDecoding = false
        if isAudioBoostEnabled {
            await updateAudioBoostMode()
        }
    }

    @MainActor
    private func updateAudioBoostMode() async {
        let wasPlaying = player?.isPlaying == true
        let resumeTime = player?.currentTime ?? 0
        let shouldShowReverting = !isAudioBoostEnabled && isBoostedAudioReady
        isRevertingAudioBoost = shouldShowReverting
        defer {
            if shouldShowReverting { isRevertingAudioBoost = false }
        }

        if isAudioBoostEnabled {
            let actionToken = audioBoostActionToken
            isPreparingAudioBoost = true
            showsAudioBoostPreparationStatus = ExploreAudioBoostFeedbackPolicy.shouldPresent(
                actionToken: actionToken
            )
            audioBoostPreparationFailed = false
            defer {
                isPreparingAudioBoost = false
                showsAudioBoostPreparationStatus = false
                if let actionToken {
                    onAudioBoostActionFinished?(actionToken)
                }
            }
            do {
                let result = try await AudioBoostProcessor.shared.prepare(source: filePath)
                guard !Task.isCancelled else { return }
                guard let boostedPlayer = makePlayer(
                    url: result.url,
                    resumeTime: resumeTime,
                    shouldPlay: wasPlaying
                ) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                player = boostedPlayer
                isBoostedAudioReady = true
                AppTelemetry.trackInsightAudioBoost(event: "enabled", gainBand: result.gainBand)
                if wasPlaying {
                    trackBoostedPlaybackStartedIfNeeded()
                }
            } catch {
                guard !Task.isCancelled else { return }
                isBoostedAudioReady = false
                let shouldPresentFailure = ExploreAudioBoostFeedbackPolicy.shouldPresent(
                    actionToken: actionToken
                )
                audioBoostPreparationFailed = shouldPresentFailure
                if shouldPresentFailure {
                    HapticManager.shared.triggerErrorThump(
                        source: "media.insight.audioBoost.failed"
                    )
                }
                AppTelemetry.trackInsightAudioBoost(event: "preparation_failed")
            }
        } else {
            audioBoostPreparationFailed = false
            showsAudioBoostPreparationStatus = false
            guard isBoostedAudioReady else { return }
            guard let originalURL = originalAudioLease?.url else { return }
            player = makePlayer(url: originalURL, resumeTime: resumeTime, shouldPlay: wasPlaying)
            isBoostedAudioReady = false
            hasTrackedBoostedPlaybackStart = false
            AppTelemetry.trackInsightAudioBoost(event: "disabled")
        }
    }

    @MainActor
    private func makePlayer(url: URL, resumeTime: TimeInterval, shouldPlay: Bool) -> AVAudioPlayer? {
        guard let preparedPlayer = try? AVAudioPlayer(contentsOf: url) else { return nil }
        playerDelegate.onFinish = {
            playbackProgress = 0.0
            isPlaying = false
            showPlaybackControlPersistently()
        }
        preparedPlayer.delegate = playerDelegate
        preparedPlayer.prepareToPlay()
        preparedPlayer.currentTime = min(max(0, resumeTime), preparedPlayer.duration)
        if shouldPlay {
            preparedPlayer.play()
            isPlaying = true
        }
        return preparedPlayer
    }

    private func trackBoostedPlaybackStartedIfNeeded() {
        guard isAudioBoostEnabled, isBoostedAudioReady, !hasTrackedBoostedPlaybackStart else { return }
        hasTrackedBoostedPlaybackStart = true
        AppTelemetry.trackInsightAudioBoost(event: "boosted_playback_started")
    }
}

private extension View {
    func insightAudioBadgeStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            }
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}
