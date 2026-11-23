import SwiftUI

struct CaptureStagingToolbarMediaRow: View {
    let presentation: CaptureStagingToolbarPresentation
    var selectedNodeID: String?
    var addAccessibilityLabel = "Add photo"
    var isReview = false
    var isAddingMedia = false
    let isCheckingPhotoImportAdmission: Bool
    let onRequestPhotoPickerPresentation: (Int) -> Void
    let onUpgradeTap: () -> Void
    let onThumbnailTap: (Int) -> Void
    let onDescriptionTap: (Int) -> Void
    let onAudioTap: (Int) -> Void
    let onVideoTap: (Int) -> Void

    var body: some View {
        Group {
            ForEach(presentation.visibleNodes) { node in
                mediaButton(for: node)
                    .overlay {
                        if selectedNodeID == node.id { Circle().stroke(.tint, lineWidth: 2) }
                    }
                    .accessibilityAddTraits(selectedNodeID == node.id ? .isSelected : [])
            }

            ForEach(0..<presentation.emptyMediaSlotCount, id: \.self) { slot in
                Button {
                    onRequestPhotoPickerPresentation(presentation.emptyMediaSlotCount)
                } label: {
                    Group {
                        if isCheckingPhotoImportAdmission {
                            ProgressView().tint(.primary)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .modifier(CaptureStagingNodeSurface(isEmpty: true))
                    .accessibilityHidden(true)
                }
                .buttonStyle(PlainButtonStyle())
                .overlay { if isAddingMedia { Circle().stroke(.tint, lineWidth: 2) } }
                .accessibilityAddTraits(isAddingMedia ? .isSelected : [])
                .accessibilityIdentifier("StagedMediaPlaceholder_\(slot)")
                .disabled(isCheckingPhotoImportAdmission)
                .accessibilityLabel(
                    isCheckingPhotoImportAdmission
                        ? "Checking scan availability"
                        : addAccessibilityLabel
                )

            }

            if presentation.showsProMediaPlaceholder {
                Button(action: onUpgradeTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .modifier(CaptureStagingNodeSurface(isEmpty: true))
                        .overlay(alignment: .bottom) {
                            if !isReview { MerianProBadge() }
                        }
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .disabled(isCheckingPhotoImportAdmission)
                .accessibilityIdentifier("StagedMediaProPlaceholder")
                .accessibilityLabel(isReview ? "Add media" : "Add another media item with Pro")
                .accessibilityHint(isReview ? "Returns to capture" : "Opens upgrade options")
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
                    .modifier(CaptureStagingNodeSurface())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Review photo \(index + 1)")

        case .description(let index, _):
            Button {
                onDescriptionTap(index)
            } label: {
                StagedDescriptionBadge()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit historical description \(index + 1)")

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
                            .modifier(CaptureStagingNodeSurface())

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
                .accessibilityLabel("Review video \(index + 1)")
            }
        }
    }
}

private struct StagedDescriptionBadge: View {
    var body: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .modifier(CaptureStagingNodeSurface())
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct StagedAudioBadge: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .modifier(CaptureStagingNodeSurface())
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct ActiveScanTooltipOverlay: View {
    var body: some View {
        Text("Tap to edit")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white.opacity(0.9), .blue)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
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
