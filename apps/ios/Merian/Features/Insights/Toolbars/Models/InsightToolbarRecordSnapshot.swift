import Foundation

struct InsightToolbarRecordSnapshot: Equatable {
    let scanId: String
    let coverImagePath: String?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let habitatDescription: String?
    let weatherCondition: String?
    let semanticTags: [String]
    let imageQualityScore: Int?
    let collectionIds: Set<String>
    let captureDate: Date?
    let timestamp: Date
    let confirmedSpeciesId: String?
    let imageCount: Int
    let exploreMediaItems: [ExplorePostComposerMediaDraft]
    let isExploreShareEligible: Bool
    let isHumanSubject: Bool
    let shouldSuppressReferenceImages: Bool

    init(record: LocalScanRecord) {
        self.scanId = record.id
        self.coverImagePath = record.coverImagePath
        self.taxonomyKingdom = record.taxonomyKingdom
        self.taxonomyClass = record.taxonomyClass
        self.taxonomyOrder = record.taxonomyOrder
        self.taxonomyFamily = record.taxonomyFamily
        self.habitatDescription = record.habitatDescription
        self.weatherCondition = record.weatherCondition
        self.semanticTags = record.semanticTags
        self.imageQualityScore = record.imageQualityScore
        self.collectionIds = Set(record.collections?.map(\.id) ?? [])
        self.captureDate = record.captureDate
        self.timestamp = record.timestamp
        self.confirmedSpeciesId = record.confirmedSpeciesId
        self.imageCount = record.capturedMediaSnapshot.thumbnailImagePaths.count
        self.exploreMediaItems = ExplorePostComposerMediaDraft.eligibleItems(
            from: record.capturedMediaSnapshot,
            scanId: record.id
        )
        self.isExploreShareEligible = record.isExploreShareEligible
        self.isHumanSubject = record.isHumanSubject
        self.shouldSuppressReferenceImages = record.shouldSuppressReferenceImages
    }
}
