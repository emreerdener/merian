import SwiftData
import SwiftUI

enum CollectionGridCardMetrics {
    static let aspectRatio: CGFloat = 1.0
    static let defaultCollectionAspectRatio: CGFloat = 1.28
    static let cornerRadius: CGFloat = 16
}

struct CollectionSummaryItem {
    let count: Int
    let coverScan: LocalScanRecord?

    static let empty = CollectionSummaryItem(count: 0, coverScan: nil)
}

struct CollectionMembershipSnapshot {
    static let empty = CollectionMembershipSnapshot(
        summariesByCollectionID: [:],
        memberIDsByCollectionID: [:]
    )

    private let summariesByCollectionID: [String: CollectionSummaryItem]
    private let memberIDsByCollectionID: [String: Set<String>]

    init(scans: [LocalScanRecord]) {
        var summaries: [String: CollectionSummaryItem] = [:]
        var memberIDs: [String: Set<String>] = [:]

        for scan in scans {
            for collection in scan.collections ?? [] {
                var ids = memberIDs[collection.id] ?? []
                ids.insert(scan.id)
                memberIDs[collection.id] = ids

                let current = summaries[collection.id] ?? .empty
                summaries[collection.id] = CollectionSummaryItem(
                    count: current.count + 1,
                    coverScan: current.coverScan ?? scan
                )
            }
        }

        self.summariesByCollectionID = summaries
        self.memberIDsByCollectionID = memberIDs
    }

    private init(
        summariesByCollectionID: [String: CollectionSummaryItem],
        memberIDsByCollectionID: [String: Set<String>]
    ) {
        self.summariesByCollectionID = summariesByCollectionID
        self.memberIDsByCollectionID = memberIDsByCollectionID
    }

    func summary(for collectionID: String) -> CollectionSummaryItem {
        summariesByCollectionID[collectionID] ?? .empty
    }

    func contains(scanID: String, in collectionID: String) -> Bool {
        memberIDsByCollectionID[collectionID]?.contains(scanID) == true
    }

    func memberScans(for collectionID: String, from orderedScans: [LocalScanRecord]) -> [LocalScanRecord] {
        guard let memberIDs = memberIDsByCollectionID[collectionID], !memberIDs.isEmpty else {
            return []
        }
        return orderedScans.filter { memberIDs.contains($0.id) }
    }
}

struct CollectionCard: View {
    let collection: ScanCollection
    let summary: CollectionSummaryItem
    
    var body: some View {
        CollectionCardChrome(
            title: collection.name,
            count: summary.count,
            coverScan: summary.coverScan,
            emptyIconName: "photo.on.rectangle"
        )
    }
}

struct SmartCollectionCard: View {
    let snapshot: SmartCollectionSnapshot

    var body: some View {
        CollectionCardChrome(
            title: snapshot.title,
            count: snapshot.count,
            coverScan: snapshot.coverScan,
            emptyIconName: snapshot.iconName
        )
    }
}

struct FeaturedCollectionCard: View {
    let snapshot: SmartCollectionSnapshot

    @State private var featuredIndex = 0

    private let rotationTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    private var featuredScans: [LocalScanRecord] {
        snapshot.scans
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
            GeometryReader { geo in
                ScanThumbnail(
                    record: featuredScan,
                    prefersReferenceForAudio: true
                )
                    .id(featuredScan.id)
                    .frame(width: geo.size.width, height: geo.size.width)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .clipped()
                    .transition(.opacity)
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: snapshot.iconName)
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                        .offset(y: -28)
                )
        }
    }
}

private struct CollectionCardChrome: View {
    let title: String
    let count: Int
    let coverScan: LocalScanRecord?
    let emptyIconName: String

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
        .aspectRatio(CollectionGridCardMetrics.aspectRatio, contentMode: .fit)
        .cornerRadius(CollectionGridCardMetrics.cornerRadius)
        .clipped()
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverScan {
            GeometryReader { geo in
                ScanThumbnail(
                    record: coverScan,
                    prefersReferenceForAudio: true
                )
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: emptyIconName)
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                        // Shifts the icon up by half the bottom label panel height.
                        .offset(y: -24)
                )
        }
    }
}
