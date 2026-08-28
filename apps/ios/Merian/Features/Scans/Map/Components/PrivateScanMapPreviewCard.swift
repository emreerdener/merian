import SwiftUI

struct PrivateScanMapPreviewCard: View {
    let point: PrivateScanMapPoint
    let isOnline: Bool
    let onOpen: () -> Void
    let onReferenceImageNeeded: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ScanThumbnail(
                    isOnline: isOnline,
                    imagePath: point.thumbnail.imagePath,
                    fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                    audioPath: point.thumbnail.audioPath,
                    hasVideo: point.thumbnail.hasVideo,
                    hasAudio: point.thumbnail.hasAudio,
                    prefersReferenceForAudio: true,
                    maxDimension: 180,
                    placeholderStyle: point.thumbnail.placeholderStyle,
                    onReferenceImageNeeded: onReferenceImageNeeded
                )
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(point.privateMapDisplayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(point.scientificName)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(point.privateMapMetadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("View scan")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(Capsule(style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(
            "\(point.privateMapDisplayName), \(point.scientificName), View scan"
        )
        .accessibilityHint("Opens your private scan")
        .accessibilityIdentifier("PrivateScanMapPreview")
    }
}
