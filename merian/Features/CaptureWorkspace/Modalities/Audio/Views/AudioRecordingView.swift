import SwiftUI

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
    private let idleImages = ["bird_tree", "frog", "owl", "cicadia", "cricket", "falcon", "rattlesnake", "whale"]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                let showSpectrogram = audioCaptureManager.isRecording || audioCaptureManager.pendingPlaybackPath != nil

                if showSpectrogram {
                    let centerY = proxy.size.height * composingCenter
                    let halfHeight = min(centerY - 100, proxy.size.height - controlBarHeight - centerY - 88)
                    let spectrogramHeight = max(180, halfHeight * 2)
                    spectrogramContent(height: spectrogramHeight)
                        .frame(width: proxy.size.width)
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

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(idleImages[idleImageIndex])
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 24)
                .id(idleImageIndex)
                .transition(.opacity)
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
            columnCap: AudioCaptureManager.columnCap
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
                                    isScrubbing = true
                                    audioCaptureManager.seekPlayback(to: Double(value.location.x / geo.size.width))
                                }
                                .onEnded { _ in isScrubbing = false }
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
