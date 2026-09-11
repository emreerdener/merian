import Photos
import PhotosUI
import SwiftUI

struct CaptureStagingToolbarMediaRow: View {
    let presentation: CaptureStagingToolbarPresentation
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var isPhotoPickerPresented: Bool
    let isCheckingPhotoImportAdmission: Bool
    let showTooltip: Bool
    let photoLibrary: PHPhotoLibrary
    let onRequestPhotoPickerPresentation: (Int) -> Void
    let onThumbnailTap: (Int) -> Void
    let onDescriptionTap: (Int) -> Void
    let onAudioTap: (Int) -> Void
    let onVideoTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(presentation.visibleNodes) { node in
                mediaButton(for: node)
            }

            if let selectionCount = presentation.photoSelectionCount {
                Button {
                    onRequestPhotoPickerPresentation(selectionCount)
                } label: {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4])
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Group {
                                if isCheckingPhotoImportAdmission {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .accessibilityHidden(true)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isCheckingPhotoImportAdmission)
                .accessibilityLabel(
                    isCheckingPhotoImportAdmission
                        ? "Checking scan availability"
                        : "Add photo"
                )
                .photosPicker(
                    isPresented: $isPhotoPickerPresented,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: selectionCount,
                    matching: .images,
                    photoLibrary: photoLibrary
                )
            }
        }
        .overlay(alignment: .bottom) {
            if showTooltip {
                ActiveScanTooltipOverlay()
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.95))
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func mediaButton(for node: StagedCaptureNode) -> some View {
        switch node {
        case .image(let index, let stagedImage):
            Button {
                onThumbnailTap(index)
            } label: {
                Image(uiImage: stagedImage.uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            Color.white.opacity(0.5),
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(PlainButtonStyle())

        case .description(let index, _):
            Button {
                onDescriptionTap(index)
            } label: {
                StagedDescriptionBadge()
            }
            .buttonStyle(.plain)

        case .audio(let index, _):
            Button {
                onAudioTap(index)
            } label: {
                StagedAudioBadge()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review audio recording")
            .accessibilityIdentifier("StagedAudioBadge_\(index)")

        case .video(let index, let stagedVideo):
            if let coverImage = stagedVideo.coverImage {
                Button {
                    onVideoTap(index)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: coverImage.uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    Color.white.opacity(0.5),
                                    lineWidth: 1
                                )
                            )

                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.62))
                            .clipShape(Circle())
                            .offset(x: 1, y: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StagedDescriptionBadge: View {
    var body: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.primary))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct StagedAudioBadge: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.primary))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct ActiveScanTooltipOverlay: View {
    var body: some View {
        Text("Tap to edit")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white.opacity(0.9), .blue)
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .offset(y: 40)
    }
}
