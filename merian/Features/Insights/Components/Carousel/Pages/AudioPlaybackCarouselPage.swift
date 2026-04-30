import AVFoundation
import SwiftUI

final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        onFinish()
    }
}

struct AudioPlaybackCarouselPage: View {
    let filePath: String
    
    @State private var player: AVAudioPlayer?
    @State private var playerDelegate = PlayerDelegate()
    @State private var columns: [SpectrogramColumn] = []
    @State private var playbackProgress: Double = 0.0
    @State private var isDecoding: Bool = true
    
    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isPlaying: Bool = false
    private var isHardwareDisabled: Bool {
        speechManager.isRecording || audioCaptureManager.isRecording
    }
    
    // Captured session category across appearances
    @State private var previousSessionCategory: AVAudioSession.Category?
    @State private var previousSessionCategoryOptions: AVAudioSession.CategoryOptions?
    
    // 60FPS precision playhead
    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var accessibilityIdentifier: String {
        "AudioPlaybackCarouselPage_\(URL(fileURLWithPath: filePath).lastPathComponent)"
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
                    SpectrogramView(columns: columns, columnCap: columns.count)
                        .equatable()
                        .allowsHitTesting(false)
                        .overlay(alignment: .leading) {
                            if isPlaying || playbackProgress > 0 {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 2)
                                    .offset(x: proxy.size.width * playbackProgress)
                            }
                        }
                }
                .padding(.horizontal, 24) // Match SpectrogramView safe bounds

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(isHardwareDisabled)
                .opacity(isHardwareDisabled ? 0.3 : 1.0)
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
            player?.stop()
            isPlaying = false
            restoreSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                player?.stop()
                isPlaying = false
                playbackProgress = 0.0
                restoreSession()
            }
        }
        .task {
            await decodeAudio()
        }
        .onReceive(timer) { _ in
            guard let player = player, player.isPlaying, player.duration > 0 else { return }
            playbackProgress = player.currentTime / player.duration
        }
    }
    
    // MARK: - Handlers

    private func togglePlayback() {
        guard !isHardwareDisabled, let player = player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Guarantee audio session is hot before play
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                player.play()
                isPlaying = true
            } catch {
                MerianLog.general.debug("AudioPlaybackCarouselPage: session activation failed: \(error, privacy: .private)")
            }
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

    private nonisolated func decodeAudio() async {
        defer { Task { @MainActor in self.isDecoding = false } }
        
        let url = URL(fileURLWithPath: filePath)
        let playerURL = url
        let preparedPlayer: AVAudioPlayer? = try? await MainActor.run {
            let p = try AVAudioPlayer(contentsOf: playerURL)
            playerDelegate.onFinish = {
                playbackProgress = 0.0
                isPlaying = false
            }
            p.delegate = playerDelegate
            p.prepareToPlay()
            return p
        }
        await MainActor.run { self.player = preparedPlayer }

        let finalColumns = await AudioSpectrogramDecoder.decodeColumns(fromFilePath: url.path)
        await MainActor.run {
            self.columns = finalColumns
        }
    }
}
