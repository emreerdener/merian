import SwiftUI

enum CollectionGridCardMetrics {
    static let aspectRatio: CGFloat = 1.0
    static let defaultCollectionAspectRatio: CGFloat = 1.28
    static let cornerRadius: CGFloat = 16
}

struct CollectionCardChrome: View {
    let title: String
    let count: Int
    let coverScan: LocalScanRecord?
    let emptyIconName: String

    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    var body: some View {
        ZStack {
            coverImage

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(count) Scans")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
        }
        .aspectRatio(
            CollectionGridCardMetrics.aspectRatio,
            contentMode: .fit
        )
        .cornerRadius(CollectionGridCardMetrics.cornerRadius)
        .clipped()
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverScan {
            GeometryReader { geometry in
                ScanThumbnail(
                    record: coverScan,
                    isOnline: offlineQueueManager.isOnline,
                    prefersReferenceForAudio: true
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.width
                )
                .clipped()
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: emptyIconName)
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                        .offset(y: -24)
                }
        }
    }
}
