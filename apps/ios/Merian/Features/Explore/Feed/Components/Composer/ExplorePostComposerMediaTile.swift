import SwiftUI

struct ExplorePostComposerMediaTile: View {
    let item: ExplorePostComposerMediaDraft
    let isCover: Bool
    let canDeselect: Bool
    let onToggle: () -> Void

    private let tileSize: CGFloat = 128
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                ExplorePostComposerImageView(
                    path: item.isAudio ? nil : item.previewPath,
                    maxDimension: Int(tileSize * 2),
                    placeholder: .media(item.kind)
                )
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(item.isIncluded ? 1 : 0.38)

                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(item.isIncluded ? Color.white : Color.secondary, item.isIncluded ? Color.accentColor : Color.clear)
                        .shadow(color: .black.opacity(item.isIncluded ? 0.28 : 0), radius: 4, y: 1)

                    if item.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    if item.isAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                }
                .padding(8)

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .bold))
                        Text(isCover ? "Cover" : item.kind.rawValue.capitalized)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.56))
                }
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isCover ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isCover ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDeselect && item.isIncluded)
        .accessibilityLabel(item.isAudio ? "Audio media" : item.isVideo ? "Video media" : "Image media")
        .accessibilityHint(isCover ? "Selected as the cover. Drag to reorder." : "Tap to include or exclude. Drag to reorder.")
    }
}

struct ExplorePostComposerMediaDropDelegate: DropDelegate {
    let targetItem: ExplorePostComposerMediaDraft
    @Binding var mediaItems: [ExplorePostComposerMediaDraft]
    @Binding var draggedMediaItemId: String?

    func dropEntered(info: DropInfo) {
        guard let draggedMediaItemId,
              draggedMediaItemId != targetItem.id,
              let fromIndex = mediaItems.firstIndex(where: { $0.id == draggedMediaItemId }),
              let toIndex = mediaItems.firstIndex(where: { $0.id == targetItem.id }) else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            mediaItems.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedMediaItemId = nil
        HapticManager.shared.triggerSelectionPulse()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
