import Foundation

/// A value projection of every persisted scan field that can change collection
/// membership, smart-collection matching, ordering, or cover eligibility.
/// SwiftData model arrays preserve object identity across in-place mutations, so
/// views use this projection as their refresh task identity.
struct CollectionScanRefreshIdentity: Equatable {
    struct Scan: Equatable {
        let id: String
        let timestamp: Date
        let isBiological: Bool
        let locationName: String?
        let taxonomyKingdom: String?
        let taxonomyClass: String?
        let isInvasive: Bool
        let hazardType: String
        let confidenceBitPattern: UInt64?
        let candidatesData: Data?
        let userReviewState: String
        let inferenceTier: String?
        let scientificName: String
        let isHumanSubject: Bool
        let userIdentificationOverride: String?
        let userConfirmedIdentification: Bool
        let isFlagged: Bool
        let isEligibleCollectionCover: Bool
        let collectionIDs: [String]

        init(scan: LocalScanRecord) {
            id = scan.id
            timestamp = scan.timestamp
            isBiological = scan.isBiological
            locationName = scan.locationName
            taxonomyKingdom = scan.taxonomyKingdom
            taxonomyClass = scan.taxonomyClass
            isInvasive = scan.isInvasive
            hazardType = scan.hazardType
            confidenceBitPattern = scan.confidenceScore?.bitPattern
            candidatesData = scan.candidatesData
            userReviewState = scan.userReviewState.rawValue
            inferenceTier = scan.inferenceTier
            scientificName = scan.scientificName
            isHumanSubject = scan.isHumanSubject
            userIdentificationOverride = scan.userIdentificationOverride
            userConfirmedIdentification = scan.userConfirmedIdentification
            isFlagged = scan.isFlagged
            isEligibleCollectionCover = CollectionCoverPolicy.isEligible(scan)
            collectionIDs = (scan.collections ?? [])
                .map(\.id)
                .sorted()
        }
    }

    let scans: [Scan]

    init(scans: [LocalScanRecord]) {
        self.scans = scans.map(Scan.init)
    }
}

struct CollectionsCatalogRefreshIdentity: Equatable {
    struct Collection: Equatable {
        let id: String
        let name: String
        let createdAt: Date
        let isPendingDeletion: Bool

        init(collection: ScanCollection) {
            id = collection.id
            name = collection.name
            createdAt = collection.createdAt
            isPendingDeletion = collection.isPendingDeletion
        }
    }

    let scanIdentity: CollectionScanRefreshIdentity
    let collections: [Collection]
    let hiddenSmartCollectionIDs: [String]

    init(
        scans: [LocalScanRecord],
        collections: [ScanCollection],
        hiddenSmartCollectionIDs: Set<String>
    ) {
        scanIdentity = CollectionScanRefreshIdentity(scans: scans)
        self.collections = collections.map(Collection.init)
        self.hiddenSmartCollectionIDs = hiddenSmartCollectionIDs.sorted()
    }
}
