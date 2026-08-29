struct CollectionSummaryItem {
    let count: Int
    let coverScan: LocalScanRecord?

    static let empty = CollectionSummaryItem(count: 0, coverScan: nil)
}

enum CollectionCoverPolicy {
    /// Prefer a member that can render useful card content instead of letting
    /// an archived scan hide the rest of the collection.
    static func isEligible(_ scan: LocalScanRecord) -> Bool {
        let presentation = scan.scanThumbnailPresentation
        return presentation.imagePath != nil ||
            presentation.fallbackImageUrl != nil ||
            presentation.audioPath != nil ||
            presentation.placeholderStyle != .archived
    }
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
                    coverScan: Self.preferredCover(
                        current: current.coverScan,
                        candidate: scan
                    )
                )
            }
        }

        summariesByCollectionID = summaries
        memberIDsByCollectionID = memberIDs
    }

    func summary(for collectionID: String) -> CollectionSummaryItem {
        summariesByCollectionID[collectionID] ?? .empty
    }

    func contains(scanID: String, in collectionID: String) -> Bool {
        memberIDsByCollectionID[collectionID]?.contains(scanID) == true
    }

    func memberScans(
        for collectionID: String,
        from orderedScans: [LocalScanRecord]
    ) -> [LocalScanRecord] {
        guard let memberIDs = memberIDsByCollectionID[collectionID],
              !memberIDs.isEmpty else {
            return []
        }
        return orderedScans.filter { memberIDs.contains($0.id) }
    }

    static func refreshIdentity(
        for collectionID: String,
        from orderedScans: [LocalScanRecord]
    ) -> [String] {
        [collectionID] + orderedScans.compactMap { scan in
            let isMember = scan.collections?.contains {
                $0.id == collectionID
            } == true
            return isMember ? scan.id : nil
        }
    }

    private init(
        summariesByCollectionID: [String: CollectionSummaryItem],
        memberIDsByCollectionID: [String: Set<String>]
    ) {
        self.summariesByCollectionID = summariesByCollectionID
        self.memberIDsByCollectionID = memberIDsByCollectionID
    }

    private static func preferredCover(
        current: LocalScanRecord?,
        candidate: LocalScanRecord
    ) -> LocalScanRecord {
        guard let current else { return candidate }
        if !CollectionCoverPolicy.isEligible(current),
           CollectionCoverPolicy.isEligible(candidate) {
            return candidate
        }
        return current
    }
}
