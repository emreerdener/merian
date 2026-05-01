import SwiftData
import SwiftUI

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
        ZStack {
            if let firstScan = summary.coverScan {
                GeometryReader { geo in
                    ScanThumbnail(record: firstScan)
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
                .aspectRatio(1.0, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1.0, contentMode: .fill)
                    .overlay(
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                            // Natively shifts the icon mathematically up exactly half the height
                            // of the bottom text panel, centering it perfectly within the visible area.
                            .offset(y: -24)
                    )
            }
            
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(summary.count) Scans")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
        }
        .cornerRadius(12)
        .clipped()
    }
}
