import SwiftUI

struct FeaturedCollectionCard: View {
    let snapshot: SmartCollectionSnapshot

    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @State private var featuredIndex = 0

    private let rotationTimer = Timer.publish(
        every: 5,
        on: .main,
        in: .common
    ).autoconnect()

    private var featuredScans: [LocalScanRecord] {
        let eligibleScans = snapshot.scans.filter(
            CollectionCoverPolicy.isEligible
        )
        return eligibleScans.isEmpty ? snapshot.scans : eligibleScans
    }

    private var featuredScan: LocalScanRecord? {
        guard !featuredScans.isEmpty else { return snapshot.coverScan }
        return featuredScans[featuredIndex % featuredScans.count]
    }

    var body: some View {
        ZStack {
            coverImage

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(snapshot.count) Scans")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .cornerRadius(CollectionGridCardMetrics.cornerRadius)
        .clipped()
        .onReceive(rotationTimer) { _ in
            guard featuredScans.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                featuredIndex = (featuredIndex + 1) % featuredScans.count
            }
        }
        .onChange(of: snapshot.scans.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                featuredIndex = 0
                return
            }
            featuredIndex = min(featuredIndex, ids.count - 1)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let featuredScan {
            GeometryReader { geometry in
                ScanThumbnail(
                    record: featuredScan,
                    isOnline: offlineQueueManager.isOnline,
                    prefersReferenceForAudio: true
                )
                .id(featuredScan.id)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.width
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
                .clipped()
                .transition(.opacity)
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: snapshot.iconName)
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                        .offset(y: -28)
                }
        }
    }
}
