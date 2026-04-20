import SwiftUI

// MARK: - Audio Recording View

/// Full-screen content view for the audio capture mode.
/// The capture button (start/stop) lives in CaptureControlBar; this view shows
/// three states: idle → recording (live spectrogram + SNR) → review (play/confirm/discard).
struct AudioRecordingView: View {
    @Environment(AudioCaptureManager.self) private var audioCaptureManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if audioCaptureManager.isRecording {
                recordingContent
            } else if audioCaptureManager.pendingPlaybackPath != nil {
                reviewContent
            } else {
                idleContent
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: audioCaptureManager.isRecording)
        .animation(.easeInOut(duration: 0.25), value: audioCaptureManager.pendingPlaybackPath == nil)
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.6))

            Text("Tap the button below to start listening")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    // MARK: - Recording

    private var recordingContent: some View {
        VStack(spacing: 0) {
            SNRGaugeView(snrLevel: audioCaptureManager.snrLevel)
                .padding(.top, 120)

            Spacer()

            SpectrogramView(
                columns: audioCaptureManager.spectrogramColumns,
                columnCap: AudioCaptureManager.columnCap
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - Review

    private var reviewContent: some View {
        VStack(spacing: 0) {
            Text("Review Recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 120)

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
