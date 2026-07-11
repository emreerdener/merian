import SwiftUI

struct RecordingCountdownBadge: View {
    let progress: Double
    let duration: TimeInterval
    let accessibilityPrefix: String

    private var timeString: String {
        let clampedProgress = min(max(progress, 0), 1)
        let remainingSeconds = max(0, Int(ceil((1.0 - clampedProgress) * max(duration, 0))))
        return "0:\(String(format: "%02d", remainingSeconds))"
    }

    var body: some View {
        Text(timeString)
            .font(.subheadline.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .transition(.opacity)
            .accessibilityLabel("\(accessibilityPrefix) \(timeString)")
    }
}

// MARK: - Audio Recording View

/// Full-screen content view for the audio capture mode.
/// The capture button (start/stop) lives in CaptureControlBar; this view shows
/// three states: idle → recording (live spectrogram + SNR) → review (play/confirm/discard).
struct AudioRecordingView: View {
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.controlBarHeight) private var controlBarHeight
    @Environment(\.composingCenter) private var composingCenter

    // MARK: - Carousel State
    @State private var idleImageIndex: Int = 0
    private let idleImages = ["blue-bird", "frog", "owl", "cicada", "cricket", "falcon", "rattlesnake", "whale"]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                let showSpectrogram = audioCaptureManager.isRecording || audioCaptureManager.pendingPlaybackPath != nil

                if showSpectrogram {
                    let centerY = proxy.size.height * composingCenter
                    let halfHeight = min(centerY - 100, proxy.size.height - controlBarHeight - centerY - 88)
                    let spectrogramHeight = max(180, halfHeight * 2)
                    
                    VStack(spacing: 16) {
                        timerBadge
                        spectrogramContent(height: spectrogramHeight)
                            .frame(width: proxy.size.width)
                    }
                    .position(x: proxy.size.width / 2, y: proxy.size.height * composingCenter)
                } else {
                    idleContent
                        .position(x: proxy.size.width / 2, y: proxy.size.height * composingCenter)
                }

                VStack {
                    Spacer()
                    if !showSpectrogram || audioCaptureManager.pendingPlaybackPath == nil {
                        SNRGaugeView(snrLevel: audioCaptureManager.snrLevel)
                            .padding(.bottom, controlBarHeight + 16)
                            .opacity(audioCaptureManager.isRecording ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: audioCaptureManager.isRecording)
        .animation(.easeInOut(duration: 0.25), value: audioCaptureManager.pendingPlaybackPath == nil)
    }

    // MARK: - Timer Badge

    private var timerBadge: some View {
        let progress = audioCaptureManager.isRecording
            ? audioCaptureManager.recordingProgress
            : audioCaptureManager.playbackProgress

        return RecordingCountdownBadge(
            progress: progress,
            duration: AudioCaptureManager.maxDuration,
            accessibilityPrefix: audioCaptureManager.isRecording
                ? "Audio recording time remaining"
                : "Audio playback time remaining"
        )
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(idleImages[idleImageIndex])
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 24)
                .id(idleImageIndex)
                .transition(.opacity)
                .onTapGesture {
                    HapticManager.shared.triggerSelectionPulse()
                    withAnimation(.easeInOut(duration: 0.8)) {
                        idleImageIndex = (idleImageIndex + 1) % idleImages.count
                    }
                }
        }
        .onReceive(Timer.publish(every: 6.0, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                idleImageIndex = (idleImageIndex + 1) % idleImages.count
            }
        }
    }

    // MARK: - Spectrogram (recording + review)

    @State private var isScrubbing = false

    private func spectrogramContent(height: CGFloat) -> some View {
        let isReview = audioCaptureManager.pendingPlaybackPath != nil
        return SpectrogramView(
            columns: audioCaptureManager.spectrogramColumns,
            layout: isReview ? .fitToData : .liveHorizon(capacity: AudioCaptureManager.columnCap)
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .overlay {
            if isReview {
                GeometryReader { geo in
                    // Scrub gesture layer
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isScrubbing {
                                        HapticManager.shared.triggerLightImpact(
                                            intensity: 0.35,
                                            source: "media.capture.audio.seek.begin"
                                        )
                                    }
                                    isScrubbing = true
                                    audioCaptureManager.seekPlayback(to: Double(value.location.x / geo.size.width))
                                }
                                .onEnded { _ in
                                    guard isScrubbing else { return }
                                    isScrubbing = false
                                    HapticManager.shared.triggerSelectionPulse(
                                        source: "media.capture.audio.seek.commit"
                                    )
                                }
                        )

                    // Playhead — visible while playing/scrubbing, or when parked away from start
                    if audioCaptureManager.isPlaying || isScrubbing || audioCaptureManager.playbackProgress > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: max(0, min(geo.size.width - 2, geo.size.width * audioCaptureManager.playbackProgress)))
                            .allowsHitTesting(false)
                            .animation(isScrubbing ? nil : .linear(duration: 0.033), value: audioCaptureManager.playbackProgress)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
