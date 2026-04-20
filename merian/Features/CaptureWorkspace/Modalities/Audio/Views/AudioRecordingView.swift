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
    private let idleImages = ["bird_tree", "frog", "owl"]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if audioCaptureManager.isRecording {
                    recordingContent
                        .position(x: proxy.size.width / 2, y: proxy.size.height * composingCenter)
                } else if audioCaptureManager.pendingPlaybackPath != nil {
                    reviewContent
                } else {
                    idleContent
                        .position(x: proxy.size.width / 2, y: proxy.size.height * composingCenter)
                }

            VStack {
                Spacer()
                
                if audioCaptureManager.pendingPlaybackPath == nil {
                    SNRGaugeView(snrLevel: audioCaptureManager.snrLevel)
                        .padding(.bottom, controlBarHeight + 16)
                }
            } // End VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            } // End ZStack
        } // End GeometryReader
        .environment(\.colorScheme, .dark)
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

    // MARK: - Recording

    private var recordingContent: some View {
        VStack(spacing: 0) {
            SpectrogramView(
                columns: audioCaptureManager.spectrogramColumns,
                columnCap: AudioCaptureManager.columnCap
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Review

    private var reviewContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Static spectrogram from the completed recording session
            SpectrogramView(
                columns: audioCaptureManager.spectrogramColumns,
                columnCap: AudioCaptureManager.columnCap
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            Spacer()

            Button {
                if audioCaptureManager.isPlaying {
                    audioCaptureManager.stopPlayback()
                } else {
                    audioCaptureManager.playPendingRecording()
                }
            } label: {
                Image(systemName: audioCaptureManager.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)

            HStack(spacing: 16) {
                Button("Discard") {
                    audioCaptureManager.discardPending()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(.white.opacity(0.12), in: Capsule())

                Button("Identify") {
                    audioCaptureManager.confirmAndSubmit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(.white, in: Capsule())
            }
            .padding(.bottom, 200)
        }
    }
}
