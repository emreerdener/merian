import SwiftUI

struct PrivateScanMapWaypoint: View {
    let point: PrivateScanMapPoint
    let isSelected: Bool
    let showsThumbnail: Bool
    let isOnline: Bool
    let onReferenceImageNeeded: @MainActor () -> Void

    var body: some View {
        Group {
            if showsThumbnail {
                ScanThumbnail(
                    isOnline: isOnline,
                    imagePath: point.thumbnail.imagePath,
                    fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                    audioPath: point.thumbnail.audioPath,
                    hasVideo: point.thumbnail.hasVideo,
                    hasAudio: point.thumbnail.hasAudio,
                    prefersReferenceForAudio: true,
                    maxDimension: 120,
                    placeholderStyle: point.thumbnail.placeholderStyle,
                    onReferenceImageNeeded: onReferenceImageNeeded
                )
                .frame(width: isSelected ? 50 : 42, height: isSelected ? 50 : 42)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Color.primary : Color.white,
                            lineWidth: isSelected ? 3 : 2
                        )
                }
            } else {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: isSelected ? 20 : 15, height: isSelected ? 20 : 15)
                    .overlay {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    }
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .accessibilityLabel(point.commonName)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

struct PrivateScanMapClusterBubble: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.footnote)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(minWidth: 38, minHeight: 38)
            .padding(3)
            .background(Color.accentColor)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
            .accessibilityLabel("\(count.formatted()) scans")
    }
}
