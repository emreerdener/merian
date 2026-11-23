import AVKit
import SwiftUI

struct StagedVideoPreviewModal: View {
    let video: StagedVideo
    let onRemove: () -> Void
    let editor: CaptureVideoEditorState?
    let resources: CaptureDraftPresentationResources?
    let onPlaybackReady: ((MediaPlaybackLifetime) -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @State private var playback: StagedVideoPreviewPlayback

    init(video: StagedVideo, editor: CaptureVideoEditorState? = nil,
         resources: CaptureDraftPresentationResources? = nil,
         onPlaybackReady: ((MediaPlaybackLifetime) -> Void)? = nil, onRemove: @escaping () -> Void) {
        self.video = video
        self.editor = editor
        self.resources = resources
        self.onPlaybackReady = onPlaybackReady
        self.onRemove = onRemove
        _playback = State(initialValue: StagedVideoPreviewPlayback(video: video, previewURL: editor?.sourceURL))
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width, geometry.size.height - 210))
            VStack(spacing: 16) {
                HStack {
                    Button("Remove video", systemImage: "trash", role: .destructive) {
                        onRemove()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    Spacer()
                    if let editor {
                        HStack(spacing: 20) {
                            rotationButton(editor, clockwise: false)
                            rotationButton(editor, clockwise: true)
                        }
                        .padding(.horizontal, 12)
                        .modifier(CaptureTrayGlass())
                        Spacer()
                        Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal)
                VStack(spacing: 8) {
                    Text("Review video").font(.title2.bold())
                    if let editor {
                        Text(editor.crop.allowsReframing ? "Pinch to zoom, drag to move" : "Add a replacement video to change framing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                videoSurface(side: side)
                playbackControls
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: side, initial: true) { _, value in editor?.crop.resize(to: value) }
        }
        .task {
            do { try resources?.retainPlayback(playback.lifetime) } catch { return }
            onPlaybackReady?(playback.lifetime)
            await playback.lifetime.run {
                await playback.start(autoplay: false)
                while !Task.isCancelled {
                    playback.refreshProgress()
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.pauseForBackground() }
        }
        .onDisappear {
            playback.stop()
            Task {
                if let resources { await resources.releasePlayback(playback.lifetime) } else { await playback.close() }
            }
        }
        .disabled(playback.lifetime.isClosed)
    }

    @ViewBuilder private func videoSurface(side: CGFloat) -> some View {
        if let crop = editor?.crop {
            let ratio = crop.renderedImage.size.width / max(1, crop.renderedImage.size.height)
            let width = side * max(1, ratio), height = side * max(1, 1 / ratio)
            let swapped = crop.quarterTurns % 2 != 0
            MediaCoverVideoPlayer(player: playback.player, videoGravity: .resizeAspect)
                .frame(width: swapped ? height : width, height: swapped ? width : height)
                .rotationEffect(.degrees(Double(crop.quarterTurns) * 90))
                .scaleEffect(crop.scale)
                .offset(crop.offset)
                .frame(width: side, height: side)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { playback.pauseForEditing(); crop.drag($0.translation, ended: false) }
                    .onEnded { crop.drag($0.translation, ended: true) })
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { playback.pauseForEditing(); crop.magnify($0, ended: false) }
                    .onEnded { crop.magnify($0, ended: true) })
                .accessibilityLabel("Video crop preview")
                .accessibilityAction(named: "Zoom in") { playback.pauseForEditing(); crop.magnify(1.1, ended: true) }
                .accessibilityAction(named: "Zoom out") { playback.pauseForEditing(); crop.magnify(1 / 1.1, ended: true) }
                .accessibilityAction(named: "Move left") { moveCrop(crop, x: -20, y: 0) }
                .accessibilityAction(named: "Move right") { moveCrop(crop, x: 20, y: 0) }
                .accessibilityAction(named: "Move up") { moveCrop(crop, x: 0, y: -20) }
                .accessibilityAction(named: "Move down") { moveCrop(crop, x: 0, y: 20) }
        } else {
            MediaCoverVideoPlayer(player: playback.player, videoGravity: .resizeAspect)
                .frame(width: side, height: side).clipped().accessibilityLabel("Video preview")
        }
    }

    private func moveCrop(_ crop: CapturePhotoEditorState, x: CGFloat, y: CGFloat) {
        playback.pauseForEditing()
        crop.drag(.init(width: x, height: y), ended: true)
    }

    private func rotationButton(_ editor: CaptureVideoEditorState, clockwise: Bool) -> some View {
        Button {
            playback.pauseForEditing()
            editor.crop.rotate(clockwise: clockwise)
        } label: {
            Image(clockwise ? "capture-review-rotate-right" : "capture-review-rotate-left")
                .frame(width: 31, height: 31)
        }
        .accessibilityLabel(clockwise ? "Rotate right" : "Rotate left")
        .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
        .disabled(!editor.crop.allowsReframing)
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button((playback.isPlaying || playback.isStartingPlayback) ? "Pause video" : "Play video",
                   systemImage: (playback.isPlaying || playback.isStartingPlayback) ? "pause.fill" : "play.fill") {
                playback.togglePlayback()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            Slider(value: Binding(get: { min(playback.elapsed, max(playback.duration, 0.01)) },
                                  set: { playback.seek(to: $0) }),
                   in: 0...max(playback.duration, 0.01))
                .disabled(playback.duration <= 0 || playback.isSwitchingSource)
                .accessibilityLabel("Video position")
            Text(elapsedLabel).font(.subheadline.monospacedDigit())
                .accessibilityLabel("Elapsed \(elapsedLabel)")
            Button(playback.isMuted ? "Unmute video preview" : "Mute video preview",
                   systemImage: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                playback.toggleMute()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .tint(.white)
        .padding(.horizontal, 16)
    }

    private var elapsedLabel: String {
        let seconds = Int(playback.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct StagedAudioPreviewModal: View {
    let audio: StagedAudio
    let onRemove: () -> Void
    let resources: CaptureDraftPresentationResources?
    let onPlaybackReady: ((MediaPlaybackLifetime) -> Void)?
    @State private var lifetime = MediaPlaybackLifetime()
    @State private var isRegistered = false

    @State private var isBoostEnabled = false
    @State private var boostActionToken: UUID?
    @State private var boostSource = StagedPreviewAudioBoostSource()

    init(audio: StagedAudio, resources: CaptureDraftPresentationResources? = nil,
         onPlaybackReady: ((MediaPlaybackLifetime) -> Void)? = nil, onRemove: @escaping () -> Void) {
        self.audio = audio
        self.resources = resources
        self.onPlaybackReady = onPlaybackReady
        self.onRemove = onRemove
        _isBoostEnabled = State(initialValue: audio.prefersBoostedPreview)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width, geometry.size.height - 150))
            VStack(spacing: 16) {
                HStack {
                    Button("Remove audio recording", systemImage: "trash", role: .destructive) {
                        onRemove()
                    }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    Spacer()
                }
                .padding(.horizontal)
                VStack(spacing: 8) {
                    Text("Review audio").font(.title2.bold())
                    Text("Listen back before identifying.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isRegistered { playbackPage.frame(width: side, height: side).clipped() }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            do { try resources?.retainPlayback(lifetime) } catch { return }
            onPlaybackReady?(lifetime)
            isRegistered = !lifetime.isClosed
        }
        .onDisappear {
            lifetime.seal()
            Task {
                if let resources { await resources.releasePlayback(lifetime) } else { await lifetime.close() }
            }
        }
    }

    private var playbackPage: some View {
        AudioPlaybackCarouselPage(
            filePath: audio.filePath,
            isAudioBoostEnabled: $isBoostEnabled,
            audioBoostActionToken: boostActionToken,
            onAudioBoostActionFinished: { token in
                if boostActionToken == token { boostActionToken = nil }
            },
            onAudioBoostToggleRequested: {
                boostActionToken = isBoostEnabled ? nil : UUID()
                isBoostEnabled.toggle()
            },
            dependencies: boostSource.playbackDependencies(), lifetime: lifetime
        )
    }
}
