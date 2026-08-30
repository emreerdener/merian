import AVKit
import SwiftUI

struct StagedVideoPreviewModal: View {
    private static let dismissDragThreshold: CGFloat = 120
    private static let dismissPredictionThreshold: CGFloat = 260
    private static let dismissDirectionRatio: CGFloat = 1.2

    let video: StagedVideo
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var dismissDragOffset: CGFloat = 0

    init(video: StagedVideo, onRemove: @escaping () -> Void) {
        self.video = video
        self.onRemove = onRemove
        _player = State(initialValue: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            previewContent
                .offset(y: dismissDragOffset)
                .scaleEffect(previewScale)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDragGesture, including: .all)
        .onAppear {
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }

    private var previewContent: some View {
        ZStack {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            controlsOverlay
        }
    }

    private var controlsOverlay: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close video preview")

            Spacer()

            Button(role: .destructive) {
                player.pause()
                onRemove()
                dismiss()
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Remove video")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .environment(\.colorScheme, .dark)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard dismissDragOffset > 0 || isDismissDrag(value) else { return }
                dismissDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard dismissDragOffset > 0 || isDismissDrag(value) else {
                    resetDismissDragOffset()
                    return
                }

                if shouldDismiss(for: value) {
                    player.pause()
                    dismiss()
                } else {
                    resetDismissDragOffset()
                }
            }
    }

    private var backgroundOpacity: Double {
        let progress = min(dismissDragOffset / 360, 1)
        return 1 - Double(progress) * 0.45
    }

    private var previewScale: CGFloat {
        1 - min(dismissDragOffset / 3_000, 0.04)
    }

    private func isDismissDrag(_ value: DragGesture.Value) -> Bool {
        let verticalTranslation = value.translation.height
        guard verticalTranslation > 0 else { return false }
        let horizontalTranslation = abs(value.translation.width)
        return verticalTranslation > max(24, horizontalTranslation * Self.dismissDirectionRatio)
    }

    private func shouldDismiss(for value: DragGesture.Value) -> Bool {
        value.translation.height > Self.dismissDragThreshold
            || value.predictedEndTranslation.height > Self.dismissPredictionThreshold
    }

    private func resetDismissDragOffset() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            dismissDragOffset = 0
        }
    }
}

struct StagedAudioPreviewModal: View {
    let audio: StagedAudio
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AudioPlaybackCarouselPage(filePath: audio.filePath)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                controlsOverlay
            }
    }

    private var controlsOverlay: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close audio preview")

            Spacer()

            Button(role: .destructive) {
                onRemove()
                dismiss()
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Remove audio recording")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .environment(\.colorScheme, .dark)
    }
}
